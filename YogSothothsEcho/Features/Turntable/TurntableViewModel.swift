import CoreGraphics
import Foundation
import Observation
#if DEBUG
import OSLog
#endif
import RemoteProtocol
import UIKit

/// 唱機畫面（sprint-5-detail.md §4.1）：組合目前曲狀態與手勢意圖。控制一律經 NowPlayingViewModel（S4 的確認式節奏與提示）；
/// 會判斷的部分在 SwipeTransition／TonearmGeometry／RecordStyle 等純值裡。甩動轉場（§4.4 v1.3）的計時由這裡執行
@MainActor
@Observable
final class TurntableViewModel {
    static let recordStyleKey = "turntable.recordStyle"
    static let placeholderText = "…"

    struct Label: Equatable {
        let title: String
        let artist: String
    }

    let nowPlaying: NowPlayingViewModel
    /// 唱臂皮膚（S7 F-V-07；組裝根注入）
    let skin: ResolvedTurntableSkin
    let overlay: TurntableOverlayState
    private(set) var swipe: SwipeTransition
    /// 唱機層（S6 §4.8）：存在與否由它決定；殼層只讀
    private(set) var layer: TurntableLayerState = .hidden
    /// 這一次進出唱機用的 Reduce Motion（含 DEBUG 強制）：狀態機與 TurntableView 的進場動畫讀同一份
    private(set) var layerReduceMotion = false
    @ObservationIgnored private var layerGeneration = 0
    @ObservationIgnored private var layerTask: Task<Void, Never>?
    private(set) var sleeve = CoverSleeveState()
    /// 已載入的封面（nil＝封面套畫佔位）與它所屬的專輯
    private(set) var cover: UIImage?
    @ObservationIgnored private var coverAlbum: String?
    /// 模糊背景的來源：新專輯沒有封面時保留上一張（spec「BLUR」）；轉場中跟著展示中的組
    private(set) var backgroundSource: UIImage?
    private(set) var colors = AlbumColors.fallback
    /// 甩動轉場的展示快照：放手時凍結的舊組、決定時凍結的新組
    private(set) var outgoingDeck: TurntableDeck?
    private(set) var incomingDeck: TurntableDeck?
    var recordStyle: RecordStyle {
        didSet {
            store.set(recordStyle.rawValue, forKey: Self.recordStyleKey)
            overlay.poke()
        }
    }

    @ObservationIgnored private let store: SettingsStore
    /// 先到的小圖（spine）與之後換上的原圖（detail，CR-018）
    @ObservationIgnored private let artwork: (String) async -> UIImage?
    @ObservationIgnored private let detailArtwork: (String) async -> UIImage?
    @ObservationIgnored private let palette: @Sendable (UIImage) async -> AlbumColors
    @ObservationIgnored private let transitionSleep: @Sendable (Duration) async -> Void
    /// 每次載入一個序號：同一張專輯換 token 重新載入時，前一次晚到的結果也不得覆蓋（只比 albumID 擋不住）
    @ObservationIgnored private var artworkLoad = 0
    /// 每幀讀寫，不進觀察（D11）
    @ObservationIgnored private var spin = RecordSpin()
    /// 轉場計時：持有以便取消；序號為第二層保護（被取消的計時到期也不推進）
    @ObservationIgnored private var phaseTimer: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var timerSerial = 0
    @ObservationIgnored private var transitionSerial = 0

    init(nowPlaying: NowPlayingViewModel, skin: ResolvedTurntableSkin, store: SettingsStore, displayScale: CGFloat,
         artwork: @escaping (String) async -> UIImage?, detailArtwork: @escaping (String) async -> UIImage? = { _ in nil },
         palette: @escaping @Sendable (UIImage) async -> AlbumColors,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         transitionSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.nowPlaying = nowPlaying
        self.skin = skin
        self.store = store
        self.artwork = artwork
        self.detailArtwork = detailArtwork
        self.palette = palette
        self.transitionSleep = transitionSleep
        overlay = TurntableOverlayState(sleep: sleep)
        swipe = SwipeTransition(displayScale: displayScale)
        recordStyle = RecordStyle.restore(store.string(forKey: Self.recordStyleKey))
    }

    // MARK: 顯示

    var resolvedStyle: RecordStyle { recordStyle.resolved(trackID: nowPlaying.currentTrackID) }
    var splashStyle: SplashStyle { SplashStyle.forTrack(nowPlaying.currentTrackID) }

    /// 沒有目前曲＝空白標籤；曲名與歌手未取得前顯示「…」（D9）
    var label: Label {
        guard nowPlaying.currentTrackID != nil else { return Label(title: "", artist: "") }
        return Label(title: nowPlaying.trackTitle ?? Self.placeholderText, artist: nowPlaying.trackArtist ?? Self.placeholderText)
    }

    /// 目前已採用狀態的展示資料；已載入的封面不屬於目前專輯＝佔位封面＋預設取色（不借用別張的）
    var liveDeck: TurntableDeck {
        let albumID = nowPlaying.clock?.event.albumID
        let ownArtwork = albumID != nil && coverAlbum == albumID
        return TurntableDeck(trackID: nowPlaying.currentTrackID, albumID: albumID, label: label, style: resolvedStyle, splash: splashStyle,
                             cover: ownArtwork ? cover : nil, colors: ownArtwork ? colors : .fallback)
    }

    /// 主組（封面套＋唱片）畫的資料：換標籤與淡化時是新曲，其他轉場階段是凍結的舊組，平時跟已採用狀態
    var groupDeck: TurntableDeck {
        switch swipe.phase {
        case .relabeling, .crossfading: incomingDeck ?? liveDeck
        default: outgoingDeck ?? liveDeck
        }
    }

    /// 唱臂角：轉場抬臂中＝0°；否則跟播放進度（暫停、停止＝0°）
    func armAngle() -> Double {
        if case .entering = layer { return skin.restDegrees }   // 放上唱片後才落臂（§4.8）
        guard !swipe.armLifted, let event = nowPlaying.clock?.event else { return skin.restDegrees }
        return skin.playbackAngle(state: event.state, position: nowPlaying.position() ?? 0, duration: event.duration)
    }

    /// 唱片角：轉場抬臂中煞停（與抬臂同時）；否則播放中才轉（TimelineView 每幀呼叫）
    func recordAngle(at now: Double) -> Double {
        let motion: RecordSpin.Motion = swipe.armLifted ? .braking : nowPlaying.clock?.event.state == .playing ? .spinning : .still
        spin.update(motion, at: now)
        return spin.angle(at: now)
    }

    // MARK: 封面與取色

    /// 換專輯時由視圖呼叫：先顯示 spine，原圖到了換上（取不到＝留在 spine）；晚到的舊專輯結果不覆蓋新的
    func loadArtwork(albumID: String?) async {
        artworkLoad += 1
        let load = artworkLoad
        guard let albumID else {
            apply(cover: nil, colors: .fallback, albumID: nil)
            return
        }
        let spine = await artwork(albumID)
        guard await show(spine, for: albumID, load: load, evenIfNil: true) else { return }
        _ = await show(await detailArtwork(albumID), for: albumID, load: load, evenIfNil: false)
    }

    /// 仍是最新一次載入才套用；回傳是否仍是最新一次
    private func show(_ image: UIImage?, for albumID: String, load: Int, evenIfNil: Bool) async -> Bool {
        guard artworkLoad == load else { return false }
        guard image != nil || evenIfNil else { return true }
        let extracted = if let image { await palette(image) } else { AlbumColors.fallback }
        #if DEBUG
        Self.logPalette(albumID: albumID, source: evenIfNil ? "spine" : "detail", image: image, primary: extracted.primary)
        #endif
        guard artworkLoad == load else { return false }
        apply(cover: image, colors: extracted, albumID: albumID)
        return true
    }

    #if DEBUG
    /// v2.1 T4：棕黃封面被判成黑主色的實機調查。只記 albumID、來源、像素尺寸、主色亮度與彩度（不記曲名）
    private static let paletteLog = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "palette")

    private static func logPalette(albumID: String, source: String, image: UIImage?, primary: RGBColor) {
        let pixels = image?.cgImage.map { "\($0.width)x\($0.height)" } ?? "none"
        let chroma = primary.chroma
        paletteLog.notice(
            "palette album=\(albumID, privacy: .public) source=\(source, privacy: .public) px=\(pixels, privacy: .public) lum=\(primary.luminance, format: .fixed(precision: 4)) chroma=\(chroma, format: .fixed(precision: 4))")
    }
    #endif

    private func apply(cover image: UIImage?, colors extracted: AlbumColors, albumID: String?) {
        cover = image
        coverAlbum = albumID
        colors = extracted
        // 轉場中新組只收同一張專輯的封面（spine→原圖）
        if let incoming = incomingDeck, incoming.albumID != nil, incoming.albumID == albumID {
            incomingDeck = incoming.withArtwork(image, colors: extracted)
        }
        refreshBackground()
    }

    /// 背景跟著展示中的組：轉場中是凍結的舊組，新封套開始進場才換新組；沒有封面＝保留上一張
    private func refreshBackground() {
        let source: UIImage?
        if swipe.isTransitioning {
            source = swipe.presentation.backgroundFromIncoming ? incomingDeck?.cover : groupDeck.cover
        } else {
            source = cover
        }
        if let source { backgroundSource = source }
    }

    // MARK: 唱機層（S6 §4.8）：唯一 owner；每次 open／close／斷線遞增世代，計時醒來不符即丟棄

    /// 唱片位置與上下層：進場讀 `TurntableEntrance`、離場讀關閉當下的快照、其餘讀 G7（`swipe.presentation`）
    var scenePresentation: SwipeTransition.Presentation {
        switch layer {
        case .entering(let phase): TurntableEntrance.presentation(phase, reduceMotion: layerReduceMotion)
        case .leaving(let record): record
        case .hidden, .shown: swipe.presentation
        }
    }

    /// 播放列唱機鈕：hidden 時才接受（leaving 滑完才能再進）
    func open(reduceMotion: Bool) {
        guard layer == .hidden else { return }
        layerReduceMotion = reduceMotion
        enter(.sliding)
    }

    /// 關閉鈕：進場中或已顯示時接受；當下就收斂 G7（唱機層在 leaving 期間仍在樹上，不能等 onDisappear）
    func close(reduceMotion: Bool) {
        switch layer {
        case .entering, .shown: break
        case .hidden, .leaving: return
        }
        let snapshot = scenePresentation
        cancelTransition()
        layerReduceMotion = reduceMotion
        layer = .leaving(record: snapshot)
        let generation = nextLayerGeneration()
        afterLayerDelay(TurntableEntrance.duration(of: .sliding, reduceMotion: reduceMotion), generation) { model in
            model.layer = .hidden
        }
    }

    /// 斷線而殼層換成連線畫面：直接移出
    func hideImmediately() {
        _ = nextLayerGeneration()
        cancelTransition()
        layer = .hidden
    }

    private func enter(_ phase: TurntableEntrance.Phase) {
        layer = .entering(phase)
        let generation = nextLayerGeneration()
        afterLayerDelay(TurntableEntrance.duration(of: phase, reduceMotion: layerReduceMotion), generation) { model in
            if let next = TurntableEntrance.next(after: phase, reduceMotion: model.layerReduceMotion) {
                model.enter(next)
            } else {
                model.layer = .shown
            }
        }
    }

    private func nextLayerGeneration() -> Int {
        layerTask?.cancel()
        layerGeneration += 1
        return layerGeneration
    }

    private func afterLayerDelay(_ duration: Duration, _ generation: Int, then action: @escaping @MainActor (TurntableViewModel) -> Void) {
        let sleep = transitionSleep
        layerTask = Task { [weak self] in
            await sleep(duration)
            guard !Task.isCancelled, let self, generation == self.layerGeneration else { return }
            action(self)
        }
    }


    // MARK: 手勢

    func tapRecord() async {
        guard !layer.blocksInput, !swipe.isBusy else { return }
        await nowPlaying.toggle()
    }

    func swipeChanged(_ translation: CGSize) {
        guard !layer.blocksInput else { return }
        swipe.dragChanged(translation)
    }

    /// 放手：過閾值且能送＝送指令並開始轉場；轉場中再甩＝只加速；否則封面回原位
    func swipeEnded(_ translation: CGSize, reduceMotion: Bool) {
        guard !layer.blocksInput else { return }
        switch swipe.dragEnded(translation, canSend: nowPlaying.canSendControls, reduceMotion: reduceMotion) {
        case .send(let direction): begin(direction)
        case .returnToRest: schedulePhaseTimer()
        case .accelerate, .decide, nil: break
        }
    }

    /// 視圖出現時以畫面的 displayScale 重設甩動閾值（D4）；甩動進行中不換
    func setDisplayScale(_ scale: CGFloat) {
        guard swipe.phase == .idle else { return }
        swipe = SwipeTransition(displayScale: scale)
    }

    /// 斷線：結束轉場，畫面回到最後一次採用的資料
    func connectionLost() { cancelTransition() }

    /// 關閉唱機或斷線：取消計時、解除凍結
    func cancelTransition() {
        swipe.cancel()
        transitionSerial += 1
        settle()
    }

    /// 點封面套：接受後 400 ms 由視圖呼叫 `sleeveMidwayFinished`；甩動中忽略
    func tapSleeve() -> Bool {
        guard !layer.blocksInput, !swipe.isBusy else { return false }
        return sleeve.tap()
    }

    func sleeveMidwayFinished() { sleeve.midwayFinished() }

    // MARK: 轉場

    private func begin(_ direction: SwipeTransition.Direction) {
        transitionSerial += 1
        let serial = transitionSerial
        outgoingDeck = liveDeck
        incomingDeck = nil
        schedulePhaseTimer()
        deadline?.cancel()
        let sleep = transitionSleep
        deadline = Task { [weak self] in
            await sleep(SwipeTransition.confirmDeadline)
            guard !Task.isCancelled, let self, serial == self.transitionSerial else { return }
            self.signalReady()
        }
        // 指令不取消：已送出就讓 S4 照常採用回覆；回覆只當「可以決定了」的訊號，錯誤不算（等期限）
        Task { [weak self] in
            guard let self else { return }
            let reply = direction == .next ? await self.nowPlaying.next() : await self.nowPlaying.previous()
            guard reply != nil, serial == self.transitionSerial else { return }
            self.signalReady()
        }
    }

    private func signalReady() {
        if swipe.ready() == .decide { decide() }
    }

    private func schedulePhaseTimer() {
        phaseTimer?.cancel()
        timerSerial += 1
        guard let duration = swipe.timedDuration else { return }
        let serial = timerSerial, sleep = transitionSleep
        phaseTimer = Task { [weak self] in
            await sleep(duration)
            guard !Task.isCancelled, let self, serial == self.timerSerial else { return }
            self.phaseTimerFired()
        }
    }

    private func phaseTimerFired() {
        if swipe.timerFinished() == .decide {
            decide()
        } else {
            phaseChanged()
        }
    }

    /// 讀已採用狀態分路（不看回覆內容）；凍結新組
    private func decide() {
        deadline?.cancel()
        let branch = SwipeTransition.branch(outgoingTrack: outgoingDeck?.trackID, outgoingAlbum: outgoingDeck?.albumID,
                                            currentTrack: nowPlaying.currentTrackID, currentAlbum: nowPlaying.clock?.event.albumID)
        incomingDeck = liveDeck
        swipe.decide(branch)
        phaseChanged()
    }

    private func phaseChanged() {
        guard swipe.phase != .idle else { return settle() }
        refreshBackground()
        schedulePhaseTimer()
    }

    /// 回 idle：解除凍結
    private func settle() {
        phaseTimer?.cancel()
        deadline?.cancel()
        timerSerial += 1
        outgoingDeck = nil
        incomingDeck = nil
        refreshBackground()
    }
}
