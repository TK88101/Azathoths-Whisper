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
    /// 換歌後 History.dat 重讀的時點（相對換歌事件的**絕對時點**；0ms＝換歌當下既有的讀檔）。
    /// 實測 Music 在換歌後 4.86–5.05 秒才寫履歴（4 次自然播完）；第一點晚於最大值，後兩點防負載尾端，
    /// 7 秒仍沒追上就放棄、交給 3 秒輪詢（F2，使用者 2026-09-27 拍板，計劃 2026-09-27-coverflow-f1-f2 §8.1、§9 乙）
    static let historyRecheckOffsets: [Duration] = [.milliseconds(5200), .seconds(6), .seconds(7)]

    /// 實際 sleep 的是相鄰時點的差（R1-5）
    static let historyRecheckGaps: [Duration] =
        zip(historyRecheckOffsets, [.zero] + historyRecheckOffsets.dropLast()).map { $0 - $1 }

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
    private let historyRecheckClock: any PollClock
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
    /// 每首歌最後一筆本 app 寫入的序號：reader 快取確認收到時只認最後一筆（計劃 §9.1）
    @ObservationIgnored private var latestWrites: [String: Int] = [:]
    @ObservationIgnored private var writeSerial = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var historyRecheckTask: Task<Void, Never>?
    /// 單調遞增：新的真實換歌、停止輪詢時加一。`Task.cancel()` 不保證對方已停，醒來的舊追趕以此自我作廢
    @ObservationIgnored private var historyRecheckGeneration = 0
    @ObservationIgnored private var isStopped = false
    /// 待入履歴的暫定左鄰卡（§12）。`baseline`＝建立時的履歴：尾端碰巧已是同一首的舊記錄時，
    /// 要等履歴**變了**且尾端是它才算追上
    @ObservationIgnored private var pendingPlayed: (card: DeckSnapshot.PendingPlayed, baseline: HistorySnapshot?)?

    init(
        configStore: ConfigStore,
        detailsReader: CardDetailsReader,
        queueSource: QueueFileSource,
        clock: any PollClock,
        historyRecheckClock: any PollClock,
        coverFlow: CoverFlowViewModel,
        isMusicRunning: @escaping () -> Bool,
        forceRefresh: @escaping () -> Void,
        cancelAutoFetch: @escaping (String) -> Void
    ) {
        self.configStore = configStore
        self.detailsReader = detailsReader
        self.queueSource = queueSource
        self.clock = clock
        self.historyRecheckClock = historyRecheckClock
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
        let finishedID = current?.persistentID     // 在 `current` 換成新歌之前取
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
        // 換歌平移的方向佐證要在推進位置**之前**取：往回跳時 `resolvingCurrent` 會把位置清成 nil
        let slideHint = isRealChange ? queue.slideHint(to: track.persistentID) : nil
        let previousIndex = queue.currentIndex
        let previousCardID = previousIndex.map { queue.cardID(at: $0) }
        // AC8：換歌（同一份清單）只移中心——以手上的快照推進位置；真實換歌才解除使用者接管（H-05）
        queue = queue.resolvingCurrent(persistentID: track.persistentID, isRealChange: isRealChange)
        if isRealChange {
            // 任何真實換歌先作廢舊的暫定卡；只有順向相鄰（清單的下一項）才記新的——往回跳時舊當前卡在右側
            pendingPlayed = nil
            if history != nil, let finishedID, !finishedID.isEmpty, let previousIndex, let previousCardID,
               queue.currentIndex == previousIndex + 1 {
                pendingPlayed = (DeckSnapshot.PendingPlayed(persistentID: finishedID, cardID: previousCardID), history)
            }
        }
        publish(isRealChange: isRealChange, slideHint: slideHint)
        // D16：每次換歌立即檢查兩個檔的屬性
        enqueue { model in await model.readSources(isPollTick: false) }
        if isRealChange {
            restartHistoryRecheck(expecting: finishedID)
        }
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
        let status = applyWrittenLyrics(text, for: persistentID)
        dispatch(.writeSucceeded(persistentID: persistentID, resultingStatus: status))
    }

    /// Batch 寫入成功（Import Selected／Import All 每首，2026-09-25 回報）。
    /// - 非當前曲：只更新卡片，**不經狀態機**——reducer 對非當前曲只會要求補讀，那是為「Editor 寫入期間
    ///   monitor busy」而設，Batch 匯入期間輪詢照跑（C-18）
    /// - 當前曲、有詞→有詞：畫面是使用者的選擇，**不經狀態機**（不升回）；仍讀回一次，讓當前曲收斂到 Music 的真值。
    ///   「寫入前」取此刻的狀態：`setLyrics` await 期間若有事件改了狀態，那正是 Music 的最新值（計劃 §9.2）
    /// - 其餘當前曲寫入：與 Editor 寫入同一條路（升回、補讀確認）
    func batchSaved(persistentID: String, text: String) {
        guard state.isCurrent(persistentID) else {
            _ = applyWrittenLyrics(text, for: persistentID)
            return
        }
        if state.status == .present, !LyricsText.isBlank(text) {
            _ = applyWrittenLyrics(text, for: persistentID)
            forceRefresh()
        } else {
            saved(persistentID: persistentID, text: text)
        }
    }

    func saveFailed(persistentID: String) {
        dispatch(.writeFailed(persistentID: persistentID))
    }

    /// AC5：「No lyrics for this song」。只接受已知缺詞的當前曲：有詞時標記無意義；
    /// 讀不到時「沒讀到」不能當成「沒有」；空 ID 拒絕（不同的歌會共用同一個空鍵）
    func markNoLyrics(persistentID: String) {
        guard state.isCurrent(persistentID), state.status == .missing, configStore.markNoLyrics(persistentID)
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
        isStopped = false
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
        isStopped = true
        pendingPlayed = nil
        cancelHistoryRecheck()
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

    #if DEBUG
    /// 測試用：目前的履歴追趕 task。只供測試判定追趕的「這一步做完了」（再度入睡或結束），不得用於產品邏輯
    var historyRecheckTaskForTesting: Task<Void, Never>? { historyRecheckTask }
    #endif

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
        riseTask = clock.schedule(after: Self.riseDelay) { [weak self] in
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
            pendingPlayed = nil
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
        _ = applyHistoryRead(await queueSource.readHistory(keepLast: Self.window))
        publish(isRealChange: false)
    }

    /// 履歴的狀態轉移只留這一處（輪詢讀檔與換歌後的短重讀共用）。回傳 `history` 的值是否真的變了
    private func applyHistoryRead(_ read: QueueFileSource.Read<HistorySnapshot>) -> Bool {
        let changed: Bool
        switch read {
        case .snapshot(let next):
            changed = history != next
            history = next
        case .missing:
            changed = history != nil
            history = nil               // 退回本 app 觀察到的歷史（AC8b）
        case .failed, .unchanged:
            return false                // 保留最後一份有效的履歴（R3-3 同一紀律）
        }
        // 暫定卡交棒：Music 寫進履歴了（同一首的 h: 卡原位接手），或履歴不可讀（觀察模式不需要它）
        if let pending = pendingPlayed,
           history == nil || hasCaughtUp(with: pending.card.persistentID, since: pending.baseline) {
            pendingPlayed = nil
        }
        return changed
    }

    // MARK: - 換歌後的履歴短重讀（F2）

    private func restartHistoryRecheck(expecting finishedID: String?) {
        cancelHistoryRecheck()
        guard !isStopped, let finishedID, !finishedID.isEmpty else { return }
        let generation = historyRecheckGeneration
        let baseline = history
        // 排在換歌當下那次讀檔之後：它已追上就不必重讀
        enqueue { model in
            model.scheduleHistoryRecheck(expecting: finishedID, since: baseline, generation: generation)
        }
    }

    private func cancelHistoryRecheck() {
        historyRecheckGeneration += 1
        historyRecheckTask?.cancel()
        historyRecheckTask = nil
    }

    /// 履歴相對換歌當下**變了**且尾端是剛離開的那首。只看尾端不夠：同一首先前播完過時，尾端本來就是它
    private func hasCaughtUp(with finishedID: String, since baseline: HistorySnapshot?) -> Bool {
        history != baseline && history?.recent.last?.persistentID == finishedID
    }

    private func scheduleHistoryRecheck(expecting finishedID: String, since baseline: HistorySnapshot?, generation: Int) {
        guard generation == historyRecheckGeneration, !hasCaughtUp(with: finishedID, since: baseline) else { return }
        let clock = historyRecheckClock
        historyRecheckTask = Task { [weak self] in
            for gap in Self.historyRecheckGaps {
                do {
                    try await clock.sleep(for: gap)
                } catch {
                    return
                }
                guard let self, generation == self.historyRecheckGeneration, !Task.isCancelled else { return }
                self.enqueue { model in await model.recheckHistory(generation: generation) }
                await self.workTask?.value
                // 本次或期間的輪詢已追上（不論讀到的是新內容還是 .unchanged）就停
                guard generation == self.historyRecheckGeneration,
                      !self.hasCaughtUp(with: finishedID, since: baseline)
                else { return }
            }
            // 7 秒仍沒寫：只播幾秒就跳過的歌 Music 不記——暫定卡移除，左側回到履歴的真相
            self?.enqueue { model in model.dropPendingPlayed(generation: generation) }
        }
    }

    private func dropPendingPlayed(generation: Int) {
        guard generation == historyRecheckGeneration, pendingPlayed != nil else { return }
        pendingPlayed = nil
        publish(isRealChange: false)
    }

    /// 只讀 History.dat（屬性沒變＝一次 stat）；履歴的值真的變了才 publish——publish 會順帶補讀詳情，
    /// 沒變就不多問 Music（R1-4）。讀完一律套用：讀到的是檔案的最新內容，丟掉它會讓屬性戳已更新的
    /// 那份內容永遠不再被讀到（因此讀完後不再比對世代，只在讀之前比對）
    private func recheckHistory(generation: Int) async {
        guard generation == historyRecheckGeneration else { return }
        if applyHistoryRead(await queueSource.readHistory(keepLast: Self.window)) {
            publish(isRealChange: false)
        }
    }

    private func publish(isRealChange: Bool, slideHint: SlideHint? = nil) {
        let played: DeckSnapshot.PlayedSource = history.map { .musicHistory($0) } ?? .observed(listening)
        let deck = DeckSnapshot.build(
            nowPlaying: current, played: played, pendingPlayed: pendingPlayed?.card, queue: queue, window: Self.window
        )
        upcoming = deck.upcoming
        if deck != coverFlow.deck || isRealChange {
            coverFlow.apply(deck, isRealChange: isRealChange, slideHint: slideHint)
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

    /// 寫入事實的資料面：標記與卡片。**不碰 `state`**（畫面由呼叫端決定要不要經狀態機）
    private func applyWrittenLyrics(_ text: String, for persistentID: String) -> LyricsStatus {
        reloadMarks()
        let status = LyricsStatus.resolve(lyrics: text, isMarked: marks.contains(persistentID))
        // AC5：日後寫入成功（非空）清除標記
        if status == .present, marks.contains(persistentID) {
            configStore.clearNoLyricsMark(persistentID)
            reloadMarks()
        }
        updateCardLyrics(text, for: persistentID)
        return status
    }

    /// 寫入成功後就地更新該卡的歌詞（徽章隨之改變），不重讀 Music
    private func updateCardLyrics(_ lyrics: String, for persistentID: String) {
        guard !persistentID.isEmpty else { return }
        if let existing = coverFlow.details[persistentID] {
            coverFlow.updateDetails([persistentID: existing.replacingLyrics(lyrics)])
        }
        writeSerial += 1
        let serial = writeSerial
        latestWrites[persistentID] = serial
        let reader = detailsReader
        enqueue { model in
            await reader.updateLyrics(lyrics, for: persistentID)
            model.writeAcknowledged(lyrics, for: persistentID, serial: serial)
        }
    }

    /// reader 快取已收到寫入（計劃 §9.1，評審 F1）。reader 的更新排在工作鏈上，在它之前發出的詳情讀取
    /// 可能命中舊快取，故在此收口：作廢所有在飛的讀取（ack 後才回來的被世代丟棄，該卡下次 publish 重讀），
    /// 並把寫入再套一次到卡片（ack 前已套上的舊值由此蓋正）。只認該首最後一筆寫入；**不得含 await**
    private func writeAcknowledged(_ lyrics: String, for persistentID: String, serial: Int) {
        guard latestWrites[persistentID] == serial else { return }
        latestWrites[persistentID] = nil
        detailsGeneration += 1
        if let existing = coverFlow.details[persistentID], existing.lyrics != lyrics {
            coverFlow.updateDetails([persistentID: existing.replacingLyrics(lyrics)])
        }
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
