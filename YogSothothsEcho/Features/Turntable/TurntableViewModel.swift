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
    static let smokeVariantKey = "turntable.smokeVariant"
    /// 皮膚選擇（CR-034）：存皮膚 id；未知或不可用＝classic，存值不改寫
    static let skinKey = "turntable.skin"
    static let placeholderText = "…"

    struct Label: Equatable {
        let title: String
        let artist: String
    }

    let nowPlaying: NowPlayingViewModel
    /// 目前的唱機皮膚（S7 F-V-07；CR-034 起可切換）
    private(set) var skin: ResolvedTurntableSkin
    /// 本 session 可用的皮膚（classic 在首）；序列圖解碼失敗的皮膚由 `disableSkin` 移出（R2-2：唯一 owner）
    private(set) var availableSkins: [ResolvedTurntableSkin]
    /// 序列圖皮膚的解碼快取（由本 VM 持有；View 只讀）
    let sprites: TonearmSpriteCache
    /// 選擇器預覽（設定頁與浮層共用這一個，r3-1）
    let previews: SkinPreviewRenderer
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
    /// 煙渦的變化（CR-037 §4.1b）：手選或 RANDOM 抽到煙渦都讀這一個設定（Q6）
    var smokeVariant: SmokeVariantChoice {
        didSet {
            store.set(smokeVariant.rawValue, forKey: Self.smokeVariantKey)
            overlay.poke()
        }
    }
    #if DEBUG
    /// DEBUG「換種子」（§4.7）：只存記憶體，接在 trackID 後面改變花紋種子
    var swirlDebugSalt = 0
    #endif

    @ObservationIgnored private let store: SettingsStore
    /// 序列圖解碼尺寸用（畫面像素 / pt）；視圖出現時更新
    @ObservationIgnored private var displayScale: CGFloat
    /// A′：關唱機時保留已解好的幀（附錄 F；DEBUG 可關以對照）
    @ObservationIgnored private let keepSpritesOnClose: () -> Bool
    @ObservationIgnored private var memoryWarning: NSObjectProtocol?
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
         transitionSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         catalog: TurntableSkinCatalog? = nil, spriteDecode: @escaping TonearmSpriteCache.Decode = { SpriteDecoder.decode($0) },
         keepSpritesOnClose: @escaping () -> Bool = { SpriteStrategy.keepOnClose },
         previewSource: any SkinPreviewImageSource = BundleSkinPreviewSource()) {
        self.nowPlaying = nowPlaying
        // 沒給目錄＝只有注入的那一款（1.0 的組裝）；還原存值，未知或不可用落回目錄第一款（classic）
        let catalog = catalog ?? TurntableSkinCatalog(skins: [skin])
        availableSkins = catalog.skins
        self.skin = catalog.skin(id: store.string(forKey: Self.skinKey)) ?? catalog.skins[0]
        sprites = TonearmSpriteCache(decode: spriteDecode, onFailure: { _, _ in })
        previews = SkinPreviewRenderer(source: previewSource)
        self.displayScale = displayScale
        self.keepSpritesOnClose = keepSpritesOnClose
        self.store = store
        self.artwork = artwork
        self.detailArtwork = detailArtwork
        self.palette = palette
        self.transitionSleep = transitionSleep
        overlay = TurntableOverlayState(sleep: sleep)
        swipe = SwipeTransition(displayScale: displayScale)
        recordStyle = RecordStyle.restore(store.string(forKey: Self.recordStyleKey))
        smokeVariant = SmokeVariantChoice.restore(store.string(forKey: Self.smokeVariantKey))
        sprites.onFailure = { [weak self] id, generation in self?.disableSkin(id, generation: generation) }
        sprites.focusTarget = { [weak self] in self?.spriteFocusFrame }
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseSpritesIfHidden() }
        }
    }

    isolated deinit {
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
    }

    // MARK: 皮膚（CR-034）

    /// 為什麼現在不能套用皮膚（CR-034 增補 A §4.2）
    enum SkinApplyBlock: Equatable {
        /// 唱機進場／離場、甩動轉場或封套動作中：換錨點會讓唱片跳位
        case turntableTransition
    }

    /// 選擇器入口（設定頁區段、浮層按鈕）是否存在：只看有沒有兩款以上，與唱機狀態無關
    var canBrowseSkins: Bool { availableSkins.count >= 2 }

    /// 唱機未開＝可套用（只存值與換皮膚，下次開唱機才解碼）；唱機在畫面上則要停穩
    var skinApplyBlock: SkinApplyBlock? {
        switch layer {
        case .hidden: nil
        case .shown: swipe.isBusy || sleeve.isMidway ? .turntableTransition : nil
        case .entering, .leaving: .turntableTransition
        }
    }

    /// 格子可點與 `selectSkin` 生效共用這一個判斷
    var canSelectSkin: Bool { canBrowseSkins && skinApplyBlock == nil }

    /// 立即換（不做交叉淡化，r1-4）；轉場中忽略（格子此時也停用）
    func selectSkin(_ id: String) {
        guard canSelectSkin, let next = availableSkins.first(where: { $0.spec.id == id }), next != skin else { return }
        skin = next
        store.set(id, forKey: Self.skinKey)
        sprites.release()
        overlay.poke()
    }

    /// 視圖拿到版面縮放後呼叫：序列圖皮膚依畫面像素解碼（同皮膚同縮放不重解），classic 釋放
    func prepareSprites(layoutScale: CGFloat) {
        sprites.load(skin, pixelScale: layoutScale * displayScale)
    }

    /// 記憶體警告、App 進背景（附錄 F）：唱機未顯示才釋放序列圖（顯示中釋放會讓唱臂空白又立刻重解）
    func releaseSpritesIfHidden() {
        guard layer == .hidden else { return }
        sprites.release()
    }

    /// 解碼焦點：目前進度在這款皮膚上對應的幀（落臂落到那裡、抬臂從那裡起；附錄 F 的 E）。沒有播放資訊＝nil
    var spriteFocusFrame: Int? {
        guard let event = nowPlaying.clock?.event, let duration = event.duration, duration > 0 else { return nil }
        let progress = (nowPlaying.position() ?? event.position) / duration
        return TonearmSpriteCache.frameIndex(angle: skin.angle(progress: progress), rest: skin.restDegrees, count: SpriteSkinAssets.frameCount)
    }

    /// 執行期解碼失敗（R2-2 ①–⑥）：晚到的回報忽略；否則取消並釋放快取、從本 session 移出、目前是它就回 classic、記一次
    func disableSkin(_ id: String, generation: Int) {
        guard generation == sprites.generation, id != TurntableSkin.classic.id else { return }
        sprites.release()
        availableSkins.removeAll { $0.spec.id == id }
        if skin.spec.id == id { skin = availableSkins.first ?? .classic }
        TurntableSkinCatalog.logUnavailable(id, .decodeFailed)
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
                             cover: ownArtwork ? cover : nil, colors: ownArtwork ? colors : .fallback,
                             swirl: SwirlRecipe.make(style: resolvedStyle, trackID: swirlSeedID, smoke: smokeVariant))
    }

    private var swirlSeedID: String? {
        #if DEBUG
        guard swirlDebugSalt != 0 else { return nowPlaying.currentTrackID }
        return (nowPlaying.currentTrackID ?? "") + "#\(swirlDebugSalt)"
        #else
        nowPlaying.currentTrackID
        #endif
    }

    // MARK: 煙渦第二排（CR-037 §4.5b）

    /// 第二排展開＝浮層持有 `.smokeVariants`（唯一狀態：浮層收起、關唱機時 endAllHolds 一併收合）
    var isSmokeRowOpen: Bool { overlay.holds.contains(.smokeVariants) }

    /// 樣式鈕：點煙渦＝選中並展開，已展開再點＝收合；點其他樣式＝選中並收合
    func tapStyle(_ style: RecordStyle) {
        if style == .smoke, recordStyle == .smoke, isSmokeRowOpen {
            overlay.endHold(.smokeVariants)
            return
        }
        recordStyle = style
        if style == .smoke {
            overlay.beginHold(.smokeVariants)
        } else {
            overlay.endHold(.smokeVariants)
        }
    }

    /// 手選強調色但這首的封面沒有合適強調色時實際用的墨色；讀畫面上的主唱片（轉場決定後＝新曲）
    var smokeAccentFallback: SmokeInk? {
        let deck = incomingDeck ?? groupDeck
        guard let recipe = deck.swirl, recipe.ink == .accent else { return nil }
        return SwirlPalette.resolve(recipe, colors: deck.colors, reduceTransparency: false).accentFallback
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
        overlay.endAllHolds()
        if !keepSpritesOnClose() { sprites.release() }
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
        overlay.endAllHolds()
        sprites.release()
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

    /// 點擊分派（增補 B，Codex r2-5）：命中判定的結果 → 動作。放在這裡讓「浮層命中不切播放」可以測；
    /// 視圖只負責動畫（`animate` 包住浮層切換）。回傳封套是否接受（接受後由視圖排 400 ms 半程）
    @discardableResult
    func handleTap(_ target: TurntableHitTest.Target, animate: (() -> Void) -> Void = { $0() }) -> Bool {
        switch target {
        case .record:
            Task { await tapRecord() }
            return false
        case .cover:
            return tapSleeve()
        case .overlayToggle:
            animate { overlay.toggle() }
            return false
        }
    }

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
        displayScale = scale
        guard swipe.phase == .idle else { return }
        swipe = SwipeTransition(displayScale: scale)
    }

    /// 斷線：結束轉場，畫面回到最後一次採用的資料
    /// 序列圖是 bundle 內的本機素材、與連線無關，斷線不釋放（釋放了也沒有重新載入的觸發）
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
