import CoreGraphics
import Observation
import RemoteProtocol
import UIKit

/// 開合轉場的協調（sprint-6-detail.md §4.5、§4.7、§4.9）：持有 `AlbumOpenTransition`，以時鐘推進到 open／browsing；
/// 封面落定即 open（曲目可點），文字在 open 內浮現；關閉時文字先倒放、封面再飛回、其他盒最後回來；關完請 VoiceOver 回到原專輯；
/// 封面先 spine、再換 `.opened` 的 detail 原檔。
/// 斷線而殼層換成連線畫面＝`reset`。晚到的結果以世代擋掉（S5 G7 同法）
@MainActor
@Observable
final class AlbumOpenController {
    typealias Cover = @MainActor (AlbumSummary) async -> UIImage?

    static let frame: Duration = .milliseconds(16)
    /// 殼層裡包住曲庫、詳情層、舞台的 ZStack 的座標空間名：側封回報自己的左上角，飛行封面據此換算
    static let space = "libraryArea"

    private(set) var transition = AlbumOpenTransition()
    /// 逐幀重畫中（轉場或文字浮現）；視圖的 TimelineView 據此暫停／恢復
    private(set) var isAnimating = false
    private(set) var album: AlbumSummary?
    /// 被點那張當下的 pose 與側封幾何（瀏覽區座標）；`browseOrigin`＝瀏覽區在殼層 ZStack 裡的左上角
    private(set) var start: BoxPose?
    private(set) var metrics: SpineCarouselMetrics?
    private(set) var browseOrigin: CGPoint = .zero
    private(set) var cover: UIImage?
    /// 關閉後要 VoiceOver 回焦的專輯（側封的無障礙容器取用後清掉）
    private(set) var focusRequest: String?
    /// 換版後專輯不在清單＝回程沒有槽位，改原地淡出（§4.5）
    var hasReturnSlot = true
    /// 開啟當下可見盒相對被點那張的方向（−1 左、+1 右）：整段轉場只用這份快照，換版重排也不改向；不在快照裡的盒子不位移
    private(set) var outward: [String: CGFloat] = [:]
    @ObservationIgnored var onOpen: ((AlbumSummary) -> Void)?
    @ObservationIgnored var onClosed: (() -> Void)?

    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private let spineCover: Cover
    @ObservationIgnored private let detailCover: Cover
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var coverTask: Task<Void, Never>?

    init(now: @escaping @MainActor () -> Double, sleep: @escaping @Sendable (Duration) async -> Void,
         spineCover: @escaping Cover, detailCover: @escaping Cover) {
        self.now = now
        self.sleep = sleep
        self.spineCover = spineCover
        self.detailCover = detailCover
    }

    var reduceMotion: Bool {
        get { transition.reduceMotion }
        set { transition.reduceMotion = newValue }
    }

    func channels() -> AlbumOpenTransition.Channels { transition.channels(at: now()) }

    /// 被點那張此刻由誰畫（側封／舞台／詳情層，恰一份）
    func owner(_ c: AlbumOpenTransition.Channels) -> AlbumOpenTransition.Owner { transition.owner(c) }

    /// 某一刻通道值下的轉場畫面值（飛行封面、其他盒）；沒有開啟中的專輯＝nil。每個 TimelineView 一幀只取一次 channels 往下傳
    func pose(_ c: AlbumOpenTransition.Channels) -> (album: AlbumSummary, pose: AlbumOpenPose)? {
        guard let album, let start, let metrics else { return nil }
        let pose = AlbumOpenPose.make(c, start: start, target: AlbumOpenPose.detailCoverFrame(metrics: metrics),
                                      metrics: metrics, reduceMotion: reduceMotion, hasReturnSlot: hasReturnSlot)
        return (album, pose)
    }

    func open(_ album: AlbumSummary, from pose: BoxPose, metrics: SpineCarouselMetrics, origin: CGPoint,
              outward: [String: CGFloat] = [:]) {
        // 先以曲目＋尾端總長估；曲目載入後由詳情層以實際項目數（含碟片標題）`updateRevealEnd`
        guard transition.open(album.id, revealEnd: DetailRevealSchedule(itemCount: album.trackCount + 1).end, at: now()) else { return }
        self.outward = outward
        generation += 1
        self.album = album
        start = pose
        self.metrics = metrics
        browseOrigin = origin
        hasReturnSlot = true
        cover = nil
        onOpen?(album)
        loadCover(album)
        runTicker()
    }

    /// 曲目載入後的實際結束時刻；文字段已走完而時刻延後＝要重新逐幀推進
    func updateRevealEnd(_ end: Double) {
        if transition.updateRevealEnd(end, at: now()) { runTicker() }
    }

    func close() {
        guard transition.close(at: now()) else { return }
        runTicker()
    }

    func reset() {
        let wasOpen = album != nil
        generation += 1
        ticker?.cancel()
        coverTask?.cancel()
        transition.reset()
        syncAnimating()
        clear()
        if wasOpen { onClosed?() }
    }

    func freeze() {
        transition.freeze(at: now())
        syncAnimating()
    }

    func resume() {
        transition.resume(at: now())
        runTicker()
    }

    func consumeFocusRequest() { focusRequest = nil }

    private func clear() {
        album = nil
        start = nil
        cover = nil
        outward = [:]
    }

    /// 同值不寫：@Observable 屬性每次賦值都會通知，連帶讓殼層與側封重算
    private func syncAnimating() {
        let value = transition.isAnimating(at: now())
        if value != isAnimating { isAnimating = value }
    }

    private func runTicker() {
        syncAnimating()
        ticker?.cancel()
        let mine = generation, sleep = sleep
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await sleep(Self.frame)
                guard let self, self.generation == mine, self.step() else { return }
            }
        }
    }

    /// 推進一格；回傳是否還要繼續
    private func step() -> Bool {
        // 只在轉相位時寫回：原地 mutating 一個 @Observable 屬性會無條件通知，每 16 ms 讓整個側封（含上萬槽位）重算
        var next = transition
        next.tick(at: now())
        if next != transition { transition = next }
        syncAnimating()
        guard transition.phase == .browsing else { return isAnimating }
        focusRequest = album?.id
        generation += 1
        coverTask?.cancel()
        clear()
        onClosed?()
        return false
    }

    private func loadCover(_ album: AlbumSummary) {
        coverTask?.cancel()
        let mine = generation, spineCover = spineCover, detailCover = detailCover
        coverTask = Task { [weak self] in
            // detail 與 spine 同時發出；spine 只在 detail 還沒到時先頂上
            async let detail = detailCover(album)
            let spine = await spineCover(album)
            guard let self, self.generation == mine else { return }
            if self.cover == nil { self.cover = spine }
            guard let detail = await detail, self.generation == mine else { return }
            self.cover = detail
        }
    }
}
