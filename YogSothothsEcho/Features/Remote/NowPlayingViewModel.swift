import Foundation
import Observation
import RemoteProtocol
import RemoteTransport

/// 目前曲與播放控制（sprint-4-detail.md §4.8）：Mac 推來的狀態＋本機補間；上一首／暫停繼續／下一首／拖進度。
/// 按鈕送出後 UI 不鎖死、不變淡（使用者會以為按了無效）：每次送出分開計數，等得比正常久（> slowControlThreshold）才標為慢；
/// busy／notApplied 給提示、不自動重送。連線世代守衛：舊連線的回覆與事件不改畫面
@MainActor
@Observable
final class NowPlayingViewModel {
    enum Control: Hashable { case toggle, next, previous, seek, genius }

    private(set) var clock: PlaybackClock?
    private(set) var isConnected = false
    /// 在途的每一次送出（同一按鈕連按各自一筆）；`isSlow`＝等得比正常久（角落轉圈）
    struct Pending: Equatable {
        let control: Control
        var isSlow = false
    }
    private(set) var inFlight: [Int: Pending] = [:]
    @ObservationIgnored private var nextRequest = 0
    /// 拖進度條期間與等待 seek 回覆期間顯示的預期值
    private(set) var seekPreview: Double?
    /// 放開由兩條路觸發（Slider 編輯結束、手指離開的手勢）：同一次拖曳只送一次
    @ObservationIgnored private var seekCommitting = false
    /// trackID → 曲目（曲名與逐曲歌手，CR-017）；按 albumID 取 album.tracks 後快取
    private(set) var songs: [String: TrackSummary] = [:]
    /// 由組裝根接上：albumID → 已載入的專輯（取專輯名）
    @ObservationIgnored var albumLookup: ((String) -> AlbumSummary?)?
    /// 每一筆被採用的狀態（DEBUG 量測工具用：到達判定與 D2 回條）
    @ObservationIgnored var onEventAdopted: ((PlaybackEvent) -> Void)?

    @ObservationIgnored private let now: @Sendable () -> Double
    private let fader: FadingNotice
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var client: (any PlaybackClient)?
    @ObservationIgnored private var ordering = PlaybackOrdering()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    /// 已取過或正在取曲名的專輯／已取完的專輯
    @ObservationIgnored private var titleRequests: Set<String> = []
    @ObservationIgnored private var fetchedAlbums: Set<String> = []

    init(now: @escaping @Sendable () -> Double = MonotonicNow.seconds,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.now = now
        self.sleep = sleep
        fader = FadingNotice(sleep: sleep)
    }

    var notice: PlaybackPresentation.Notice? { fader.current }

    /// 正常的換曲確認約 1.5 s；超過這個才轉圈（thecure 2026-10-18 暫定，N-01 實測 p95／p99 後定案）
    static let slowControlThreshold: Duration = .seconds(2)
    func pendingCount(_ control: Control) -> Int { inFlight.values.filter { $0.control == control }.count }
    func isSlow(_ control: Control) -> Bool { inFlight.values.contains { $0.control == control && $0.isSlow } }

    var currentTrackID: String? { clock?.event.trackID }
    var availability: PlaybackPresentation.Availability {
        PlaybackPresentation.availability(connected: isConnected, event: clock?.event.availability)
    }
    var trackTitle: String? { currentTrackID.flatMap { songs[$0]?.title } }
    var trackArtist: String? { currentTrackID.flatMap { songs[$0]?.artist } }
    var albumTitle: String? { currentAlbum?.title }
    /// 目前曲所屬的已載入專輯（曲庫清單還沒載到＝nil）
    var currentAlbum: AlbumSummary? { clock?.event.albumID.flatMap { albumLookup?($0) } }
    var duration: Double? { clock?.event.duration }
    /// Genius 鈕（CR-030）：跟著每筆事件的 genius 欄位
    var geniusButton: GeniusPresentation.Button { GeniusPresentation.button(connected: isConnected, event: clock?.event) }

    func position() -> Double? { seekPreview ?? clock?.position(at: now()) }

    /// 現在送控制指令會真的送出（唱機甩動不能送就不開始轉場，§4.4 v1.3）
    var canSendControls: Bool { client != nil && PlaybackPresentation.controlsEnabled(availability) }

    // MARK: 連線

    func attach(_ client: any PlaybackClient) {
        generation += 1
        self.client = client
        isConnected = true
        ordering.reset()
        titleRequests = fetchedAlbums   // 舊連線上還在取的作廢，新連線重取
        eventsTask?.cancel()
        let token = generation, events = client.playbackEvents()
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self, token == self.generation else { return }
                self.adopt(event)
            }
        }
    }

    func detach() {
        generation += 1
        client = nil
        isConnected = false
        eventsTask?.cancel()
        inFlight = [:]
        seekPreview = nil
    }

    /// 「重新同步」：清掉提示，以下一筆事件為準（Mac 有變化即推、至少每 10 s 校正一次；協定不新增讀狀態的 kind）
    func resync() { show(nil) }

    // MARK: 控制

    /// 回傳採用的回覆（唱機的甩動依此決定封面滑入或滑回）；按鈕呼叫端忽略
    @discardableResult func toggle() async -> ControlResult? { await run(.toggle) { client throws(EchoRequestError) in try await client.toggle() } }
    @discardableResult func next() async -> ControlResult? { await run(.next) { client throws(EchoRequestError) in try await client.next() } }
    @discardableResult func previous() async -> ControlResult? { await run(.previous) { client throws(EchoRequestError) in try await client.previous() } }

    /// Genius（CR-030）：未授權只給提示不送；結果走 Genius 專用處理（按了沒看到換曲＝無法確認，不說沒生效）
    func genius() async {
        let button = geniusButton
        guard GeniusPresentation.isPressable(button) else { return }
        guard GeniusPresentation.sends(button) else { return show(.needsAccessibility) }
        guard let result = await send(.genius, { client throws(EchoRequestError) in try await client.genius() }) else { return }
        if case .success(let reply) = result { adopt(reply.playback) }
        settle(GeniusPresentation.notice(for: result.map(\.outcome)))
    }

    /// 拖曳中：只改顯示
    func previewSeek(to seconds: Double) {
        if seekPreview == nil { SeekTrace.note("drag begin track=\(SeekTrace.short(currentTrackID)) at=\(Int(seconds)) dur=\(duration.map { String(Int($0)) } ?? "nil")") }
        seekPreview = seconds
    }

    /// 放開：送 seek（帶目前曲 ID，Mac 端曲目已換＝notApplied），回覆後回到事件值
    func commitSeek() async {
        guard !seekCommitting else { return }
        seekCommitting = true
        defer { seekCommitting = false }
        guard let target = seekPreview, let track = currentTrackID else {
            SeekTrace.note("commit skipped preview=\(seekPreview.map { String(Int($0)) } ?? "nil") track=\(SeekTrace.short(currentTrackID))")
            seekPreview = nil
            return
        }
        SeekTrace.note("commit track=\(SeekTrace.short(track)) to=\(Int(target)) canSend=\(canSendControls) client=\(client != nil) avail=\(availability)")
        let reply = await run(.seek) { client throws(EchoRequestError) in try await client.seek(trackID: track, seconds: target) }
        SeekTrace.note("reply \(reply.map { "outcome=\($0.outcome.rawValue) track=\(SeekTrace.short($0.playback.trackID)) pos=\(Int($0.playback.position))" } ?? "none") notice=\(notice.map { "\($0)" } ?? "-")")
        seekPreview = nil
    }

    /// 回傳採用的回覆（失敗、斷線或舊連線＝nil）；唱機甩動以讀回結果分路
    @discardableResult
    private func run(_ control: Control,
                     _ send: (any PlaybackClient) async throws(EchoRequestError) -> ControlResult) async -> ControlResult? {
        guard let result = await self.send(control, send) else { return nil }
        switch result {
        case .success(let reply):
            adopt(reply.playback)
            settle(reply.outcome == .notApplied ? .notApplied : nil)
            return reply
        case .failure(let error):
            show(PlaybackPresentation.notice(for: error))
            return nil
        }
    }

    /// 送出一次並記在途；nil＝沒送（不可控制）或回來時已是舊連線
    private func send(_ control: Control,
                      _ send: (any PlaybackClient) async throws(EchoRequestError) -> ControlResult) async -> Result<ControlResult, EchoRequestError>? {
        guard canSendControls, let client else { return nil }
        let token = generation
        let request = nextRequest
        nextRequest += 1
        inFlight[request] = Pending(control: control)
        let watch = watchSlow(request)
        defer { watch.cancel() }
        let result: Result<ControlResult, EchoRequestError>
        do { result = .success(try await send(client)) } catch { result = .failure(error) }
        guard token == generation else { return nil }
        inFlight[request] = nil
        return result
    }

    /// 到門檻還沒回來＝標為慢（回覆先到則取消，或已移出 inFlight 不再標）
    private func watchSlow(_ request: Int) -> Task<Void, Never> {
        let sleep = self.sleep
        return Task { [weak self] in
            await sleep(Self.slowControlThreshold)
            guard !Task.isCancelled, let self else { return }
            self.inFlight[request]?.isSlow = true   // 已回覆（移出 inFlight）就不標
        }
    }

    // MARK: 狀態

    /// 事件與控制回覆走同一個採用規則（§4.8）
    func adopt(_ event: PlaybackEvent) {
        guard ordering.admits(event) else {
            SeekTrace.note("event dropped(order) track=\(SeekTrace.short(event.trackID)) state=\(event.state.rawValue)")
            return
        }
        if event.trackID != clock?.event.trackID || event.state != clock?.event.state {
            SeekTrace.note("event track=\(SeekTrace.short(event.trackID)) state=\(event.state.rawValue) pos=\(Int(event.position)) dur=\(event.duration.map { String(Int($0)) } ?? "nil") avail=\(event.availability.rawValue)")
        }
        clock = PlaybackClock(event: event, receivedAt: now())
        onEventAdopted?(event)
        if event.availability == .ok, notice == .musicNotRunning || notice == .musicNotAuthorized { show(nil) }
        fetchTitles(event.albumID)
    }

    private func show(_ notice: PlaybackPresentation.Notice?) { fader.show(notice) }

    /// 控制有回覆後：有新提示就顯示；沒有就清掉會淡出的舊提示（權限、不確定等要使用者處理的留著）
    private func settle(_ notice: PlaybackPresentation.Notice?) {
        if let notice { show(notice) } else if self.notice.map(PlaybackPresentation.fades) == true { show(nil) }
    }

    /// 曲名與歌手以 album.tracks 取（分頁取完），按 albumID 快取；失敗下次再取
    private func fetchTitles(_ albumID: String?) {
        guard let albumID, let client, !titleRequests.contains(albumID) else { return }
        titleRequests.insert(albumID)
        let token = generation
        Task { [weak self] in
            guard let tracks = try? await client.allTracks(albumID: albumID) else {
                self?.titleRequests.remove(albumID)
                return
            }
            guard let self, token == self.generation else { return }
            self.songs.merge(tracks.songs.map { ($0.id, $0) }) { $1 }
            self.fetchedAlbums.insert(albumID)
        }
    }
}
