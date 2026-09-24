import Foundation

/// 「Cover Flow × 找歌詞」的協調者（計劃 §6、D1、D4、D13–D17、AC8）。
///
/// 把狀態機（`LyricsFlowReducer`）、無詞標記（`ConfigStore`）、Queue.dat／History.dat（`QueueFileSource`）、
/// 卡片詳情（`CardDetailsReader`）與升回計時串起來，結果交給 `CoverFlowViewModel` 顯示。
///
/// - 事件處理是同步的（D7：事件迴圈內不 await 任何 AE）：換歌當下就以手上的佇列快照推進位置、
///   重建牌組——中心立刻換到新歌，不等讀檔
/// - 讀檔（Queue.dat／History.dat）排進單一串行工作鏈，只在檔案變了才重讀；讀回後以**最新**的當前曲
///   重建（await 期間可能又換了歌，用排工作時的舊值會把位置倒退回前一首）
/// - 真實換歌的位置推進只在事件當下做一次；讀檔後只做「同曲」解析，否則一次換歌會被算成兩次
/// - **不含任何播控**：Music 只經 `CardDetailsReader` 唯讀
@MainActor
@Observable
final class LyricsFlowModel {
    /// D5：寫入成功後等彩帶撒完才升回（單一來源：彩帶壽命）
    static let riseDelay: Duration = ConfettiTiming.lifetime
    /// D1：左右各幾張（S6：左右合計 ≤ 20 首一批讀詳情）
    static let window = 10

    private(set) var state = LyricsFlowState()
    /// 右側可用性（AC8b）：`unavailable` 時畫面標明「接下來的歌暫時讀不到」
    private(set) var upcoming: DeckSnapshot.Upcoming = .pending
    /// 無詞標記的可觀察鏡像（D4）
    private(set) var marks: Set<String>

    var surface: LyricsSurface { state.surface }
    var status: LyricsStatus { state.status }

    /// 每次狀態機處理完事件後回報目前畫面（可能未變；接收端須冪等）
    @ObservationIgnored var onSurfaceChanged: ((LyricsSurface) -> Void)?
    /// 寫入回報成功、讀回卻仍缺詞（使用者拍板①：提示寫入沒生效）
    @ObservationIgnored var onWriteNotConfirmed: ((String) -> Void)?

    private let configStore: ConfigStore
    private let detailsReader: CardDetailsReader
    private let queueSource: QueueFileSource
    private let clock: any PollClock
    private let coverFlow: CoverFlowViewModel
    private let isMusicRunning: () -> Bool
    private let forceRefresh: () -> Void
    private let cancelAutoFetch: (String) -> Void

    @ObservationIgnored private var queue = QueueSession()
    @ObservationIgnored private var history: HistorySnapshot?
    @ObservationIgnored private var listening = ListeningHistory()
    @ObservationIgnored private var current: DeckSnapshot.NowPlaying?
    @ObservationIgnored private var riseTask: Task<Void, Never>?
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var detailsGeneration = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        configStore: ConfigStore,
        detailsReader: CardDetailsReader,
        queueSource: QueueFileSource,
        clock: any PollClock,
        coverFlow: CoverFlowViewModel,
        isMusicRunning: @escaping () -> Bool,
        forceRefresh: @escaping () -> Void,
        cancelAutoFetch: @escaping (String) -> Void
    ) {
        self.configStore = configStore
        self.detailsReader = detailsReader
        self.queueSource = queueSource
        self.clock = clock
        self.coverFlow = coverFlow
        self.isMusicRunning = isMusicRunning
        self.forceRefresh = forceRefresh
        self.cancelAutoFetch = cancelAutoFetch
        self.marks = configStore.noLyricsMarks
        coverFlow.updateMarks(marks)
    }

    // MARK: - 輪詢事件

    func handle(_ event: PlaybackEvent) {
        switch event {
        case .trackChanged(let track, let lyrics):
            nowPlaying(track, lyrics: lyrics)
        case .notPlaying:
            dispatch(.notPlaying)
        case .permissionDenied:
            dispatch(.permissionDenied)
        case .albumChanged:
            break
        }
    }

    private func nowPlaying(_ track: TrackInfo, lyrics: String?) {
        let identity = NowPlayingIdentity(track: track)
        let isRealChange = identity != state.nowPlaying
        // AC8b：真實換歌時把「前一首」記進聆聽歷史（History.dat 不可讀時的左側來源）
        if isRealChange, let previous = current {
            listening = listening.recording(.init(persistentID: previous.persistentID, occurrence: previous.occurrence))
        }
        reloadMarks()
        let status = LyricsStatus.resolve(lyrics: lyrics, isMarked: marks.contains(track.persistentID))
        dispatch(.nowPlaying(identity, persistentID: track.persistentID, status: status))
        current = DeckSnapshot.NowPlaying(persistentID: track.persistentID, occurrence: state.occurrence)

        // 當前曲的詳情直接取自事件（同一次讀取，AC12），不再問 Music
        if !track.persistentID.isEmpty {
            coverFlow.updateDetails([track.persistentID: Self.details(of: track, lyrics: lyrics)])
            if let lyrics {
                let reader = detailsReader
                enqueue { _ in await reader.updateLyrics(lyrics, for: track.persistentID) }
            }
        }
        // AC8：換歌（同一份清單）只移中心——以手上的快照推進位置；真實換歌才解除使用者接管（H-05）
        queue = queue.resolvingCurrent(persistentID: track.persistentID, isRealChange: isRealChange)
        publish(isRealChange: isRealChange)
        // D16：每次換歌立即檢查兩個檔的屬性
        enqueue { model in await model.readSources(isPollTick: false) }
    }

    // MARK: - 使用者操作與 Editor 回報

    /// AC3：只有「正在播 ∧ 位於幾何正中」的卡可點（`isCentered` 由條帶幾何判定，D6）
    func tapPlayingCard(isCentered: Bool) {
        dispatch(.tapPlayingCard(isCentered: isCentered))
    }

    func toggleHandle() {
        dispatch(.toggleHandle)
    }

    func userEditedLyrics() {
        dispatch(.editorTextEdited)
    }

    /// Editor 寫入成功（目標與文字在寫入前擷取，D8③）
    func saved(persistentID: String, text: String) {
        reloadMarks()
        let status = LyricsStatus.resolve(lyrics: text, isMarked: marks.contains(persistentID))
        // AC5：日後寫入成功（非空）清除標記
        if status == .present, marks.contains(persistentID) {
            configStore.clearNoLyricsMark(persistentID)
            reloadMarks()
        }
        updateCardLyrics(text, for: persistentID)
        dispatch(.writeSucceeded(persistentID: persistentID, resultingStatus: status))
    }

    func saveFailed(persistentID: String) {
        dispatch(.writeFailed(persistentID: persistentID))
    }

    /// AC5：「No lyrics for this song」。只接受已知缺詞的當前曲：有詞時標記無意義；
    /// 讀不到時「沒讀到」不能當成「沒有」；空 ID 拒絕（不同的歌會共用同一個空鍵）
    func markNoLyrics(persistentID: String) {
        guard !persistentID.isEmpty, persistentID == state.nowPlayingPersistentID, state.status == .missing,
              configStore.markNoLyrics(persistentID)
        else { return }
        reloadMarks()
        dispatch(.markedNone(persistentID: persistentID))
    }

    func isMarkedNoLyrics(_ persistentID: String) -> Bool {
        marks.contains(persistentID)
    }

    // MARK: - 來源輪詢

    /// 每次輪詢 tick：只在檔案屬性變了才重讀（D13、D16）；Music 未執行 → 佇列 session 失效（D15）
    func refreshSources() async {
        enqueue { model in await model.readSources(isPollTick: true) }
        await workTask?.value
    }

    func startPolling(clock: any PollClock = SystemPollClock(), interval: Duration = NowPlayingMonitor.interval) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
                await self?.refreshSources()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 測試用：等工作鏈與詳情讀取都落地（期間若又排了新工作，一併等完）
    func settleForTesting() async {
        while true {
            let work = workTask
            let details = detailsTask
            await work?.value
            await details?.value
            if work == workTask, details == detailsTask { return }
        }
    }

    // MARK: - 狀態機

    private func dispatch(_ event: LyricsFlowEvent) {
        let (next, effects) = LyricsFlowReducer.reduce(state, event)
        state = next
        effects.forEach(perform)
        onSurfaceChanged?(state.surface)
    }

    private func perform(_ effect: LyricsFlowEffect) {
        switch effect {
        case .scheduleRise(let token):
            scheduleRise(token)
        case .cancelRise:
            riseTask?.cancel()
            riseTask = nil
        case .forceRefresh:
            forceRefresh()
        case .cancelAutoFetch(let persistentID):
            cancelAutoFetch(persistentID)
        case .writeNotConfirmed(let persistentID):
            onWriteNotConfirmed?(persistentID)
        }
    }

    private func scheduleRise(_ token: RiseToken) {
        riseTask?.cancel()
        let clock = self.clock
        riseTask = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.riseDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.dispatch(.riseDue(token))
        }
    }

    // MARK: - 牌組

    /// 單一串行工作鏈：讀檔、快取更新依排入順序執行
    private func enqueue(_ work: @escaping @MainActor (LyricsFlowModel) async -> Void) {
        let previous = workTask
        workTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
    }

    /// - Parameter isPollTick: 輪詢 tick 每次都做同曲解析（AC8b「連續 2 次輪詢找不到」才算讀不到）；
    ///   換歌後的讀檔只在清單重寫時解析（位置已在事件當下推進過）
    private func readSources(isPollTick: Bool) async {
        guard isMusicRunning() else {
            queue = queue.invalidated()
            await queueSource.forgetQueue()
            publish(isRealChange: false)
            return
        }
        var queueRewritten = false
        switch await queueSource.readQueue() {
        case .snapshot(let snapshot):
            queue = queue.applying(snapshot)
            queueRewritten = true
        case .missing:
            // 計劃 §1：Queue.dat 不存在 → 右側退回（空＋讀不到），不沿用舊清單
            queue = queue.invalidated().markingReadFailed()
        case .failed:
            queue = queue.markingReadFailed()
        case .unchanged:
            break
        }
        if isPollTick || queueRewritten, let current {
            queue = queue.resolvingCurrent(persistentID: current.persistentID, isRealChange: false)
        }
        switch await queueSource.readHistory(keepLast: Self.window) {
        case .snapshot(let snapshot):
            history = snapshot
        case .missing:
            history = nil
        case .failed, .unchanged:
            break       // 保留最後一份有效的履歴（R3-3 同一紀律）
        }
        publish(isRealChange: false)
    }

    private func publish(isRealChange: Bool) {
        let played: DeckSnapshot.PlayedSource = history.map { .musicHistory($0) } ?? .observed(listening)
        let deck = DeckSnapshot.build(nowPlaying: current, played: played, queue: queue, window: Self.window)
        upcoming = deck.upcoming
        if deck != coverFlow.deck || isRealChange {
            coverFlow.apply(deck, isRealChange: isRealChange)
        }
        fetchDetails(for: deck)
    }

    /// AC8d：只問牌組內還沒有詳情的歌；最新者勝（世代），當前曲以事件為準、不被覆蓋
    private func fetchDetails(for deck: DeckSnapshot) {
        let currentID = current?.persistentID
        let wanted = deck.cards.map(\.persistentID).filter {
            !$0.isEmpty && $0 != currentID && coverFlow.details[$0] == nil
        }
        guard !wanted.isEmpty else { return }
        detailsGeneration += 1
        let generation = detailsGeneration
        let reader = detailsReader
        detailsTask = Task { [weak self] in
            let fetched = await reader.details(for: wanted)
            guard let self, generation == self.detailsGeneration else { return }
            let currentID = self.current?.persistentID
            self.coverFlow.updateDetails(fetched.filter { $0.key != currentID })
        }
    }

    // MARK: - 內部

    /// 鏡像以設定為準：每次換歌、寫入前重讀（設定是唯一來源，鏡像只供畫面觀察）
    private func reloadMarks() {
        let stored = configStore.noLyricsMarks
        guard stored != marks else { return }
        marks = stored
        coverFlow.updateMarks(stored)
    }

    /// 寫入成功後就地更新該卡的歌詞（徽章隨之改變），不重讀 Music
    private func updateCardLyrics(_ lyrics: String, for persistentID: String) {
        guard !persistentID.isEmpty else { return }
        if let existing = coverFlow.details[persistentID] {
            coverFlow.updateDetails([persistentID: existing.replacingLyrics(lyrics)])
        }
        let reader = detailsReader
        enqueue { _ in await reader.updateLyrics(lyrics, for: persistentID) }
    }

    private static func details(of track: TrackInfo, lyrics: String?) -> TrackDetails {
        TrackDetails(
            persistentID: track.persistentID, artist: track.artist, title: track.title, album: track.album,
            discNumber: track.discNumber, trackNumber: track.trackNumber, lyrics: lyrics
        )
    }
}

extension TrackDetails {
    func replacingLyrics(_ lyrics: String?) -> TrackDetails {
        TrackDetails(
            persistentID: persistentID, artist: artist, title: title, album: album,
            discNumber: discNumber, trackNumber: trackNumber, lyrics: lyrics
        )
    }
}
