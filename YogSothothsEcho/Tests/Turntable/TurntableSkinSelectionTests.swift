import CoreGraphics
import Foundation
import RemoteProtocol
import RemoteTransport
import Testing
import UIKit

@testable import YogSothothsEcho

// CR-034 T6b／T8（yse-1.0.1-skins.md §4.3、§4.6）：TurntableViewModel 持有本 session 可用的皮膚、目前皮膚與序列圖快取。
// 選擇存 `turntable.skin`、重建後還原；未知 id → classic；`canSelectSkin` 一個判斷同時決定切換器顯示與 selectSkin 生效；
// 解碼失敗 → disableSkin 依序：擋晚到 → 取消並遞增世代 → 釋放 → 移出可用清單 → 目前是它就回 classic（R2-2）

@MainActor
struct TurntableSkinSelectionTests {
    let client = FakePlaybackClient()
    let nowPlaying = NowPlayingViewModel(now: ManualNow().now, sleep: { _ in })
    let store = InMemorySettingsStore()
    let timers = KeyedSleeper()
    let catalog: TurntableSkinCatalog

    init() throws {
        catalog = TurntableSkinCatalog(skins: [.classic, try SpriteSkinFixture.bundled()])
    }

    /// 解碼一律成功、立即回 1×1（快取行為另有測試）
    private func makeModel(catalog: TurntableSkinCatalog? = nil, transitionSleep: @escaping @Sendable (Duration) async -> Void = { _ in })
        -> TurntableViewModel {
        TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { _ in nil },
                           palette: { _ in .fallback }, sleep: { _ in }, transitionSleep: transitionSleep,
                           catalog: catalog ?? self.catalog, spriteDecode: { _ in Self.pixel })
    }

    private nonisolated static let pixel: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    private func shown(_ model: TurntableViewModel) async {
        model.open(reduceMotion: true)
        for _ in 0..<1000 where model.layer != .shown { await Task.yield() }
        #expect(model.layer == .shown)
    }

    @Test func defaultsToClassicWithEveryCatalogSkinAvailable() {
        let model = makeModel()
        #expect(model.skin == .classic)
        #expect(model.availableSkins.map(\.spec.id) == ["classic", "s-arm-1200"])
    }

    /// 沒給目錄＝只有注入的那一款（1.0 的組裝方式；既有測試不受影響）
    @Test func withoutACatalogOnlyTheInjectedSkinExists() {
        let model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { _ in nil },
                                       palette: { _ in .fallback }, sleep: { _ in })
        #expect(model.availableSkins == [.classic] && !model.canSelectSkin)
    }

    @Test func selectionPersistsAndIsRestored() async {
        let model = makeModel()
        await shown(model)
        model.selectSkin("s-arm-1200")
        #expect(model.skin.spec.id == "s-arm-1200")
        #expect(store.string(forKey: TurntableViewModel.skinKey) == "s-arm-1200")
        #expect(makeModel().skin.spec.id == "s-arm-1200")
    }

    @Test func unknownOrUnavailableStoredSkinFallsBackToClassicWithoutOverwriting() {
        store.set("someday-skin", forKey: TurntableViewModel.skinKey)
        #expect(makeModel().skin == .classic)
        store.set("s-arm-1200", forKey: TurntableViewModel.skinKey)
        #expect(makeModel(catalog: .classicOnly).skin == .classic)
        #expect(store.string(forKey: TurntableViewModel.skinKey) == "s-arm-1200", "降版再升版不丟選擇")
    }

    @Test func selectingAnUnknownSkinIsIgnored() async {
        let model = makeModel()
        await shown(model)
        model.selectSkin("nope")
        #expect(model.skin == .classic && store.string(forKey: TurntableViewModel.skinKey) == nil)
    }

    /// 進出唱機中、封套動作中、甩動轉場中：不能選（格子停用、selectSkin 也忽略）。唱機未開＝可選，見 selectingWhileHidden…（增補 A）
    @Test func cannotSelectWhileEntering() {
        let model = makeModel(transitionSleep: { _ in await withCheckedContinuation { _ in } })
        model.open(reduceMotion: false)
        #expect(!model.canSelectSkin, "entering")
        model.selectSkin("s-arm-1200")
        #expect(model.skin == .classic)
    }

    @Test func cannotSelectWhileTheSleeveIsMoving() async {
        let model = makeModel()
        await shown(model)
        #expect(model.canSelectSkin)
        #expect(model.tapSleeve())
        #expect(!model.canSelectSkin)
        model.selectSkin("s-arm-1200")
        #expect(model.skin == .classic)
        model.sleeveMidwayFinished()
        #expect(model.canSelectSkin)
    }

    @Test func cannotSelectDuringASwipeTransition() async {
        let timers = timers
        let model = makeModel(transitionSleep: { duration in
            if duration == TurntableEntrance.duration(of: .sliding, reduceMotion: true) { return }
            await timers.sleep(duration)
        })
        model.open(reduceMotion: true)
        for _ in 0..<1000 where model.layer != .shown { await Task.yield() }
        nowPlaying.attach(client)
        await settle()
        client.push(PlaybackSamples.event(PlaybackSamples.t1, .playing, at: 1))
        await settle()
        model.swipeChanged(CGSize(width: -5, height: 0))
        model.swipeEnded(CGSize(width: -80, height: 0), reduceMotion: false)
        await settle()
        #expect(model.swipe.isBusy)
        #expect(!model.canSelectSkin)
        model.selectSkin("s-arm-1200")
        #expect(model.skin == .classic)
    }

    /// 切回 classic 即釋放；關唱機保留已解好的幀（A′，附錄 F）
    @Test func spritesFollowTheSkinAndAreKeptOnClose() async {
        let model = makeModel()
        await shown(model)
        model.selectSkin("s-arm-1200")
        model.prepareSprites(layoutScale: 1.7)
        for _ in 0..<5000 where !model.sprites.isComplete { await Task.yield() }
        #expect(model.sprites.isComplete && model.sprites.base != nil)
        model.selectSkin("classic")
        #expect(model.sprites.base == nil && !model.sprites.isComplete)
        model.selectSkin("s-arm-1200")
        model.prepareSprites(layoutScale: 1.7)
        for _ in 0..<5000 where !model.sprites.isComplete { await Task.yield() }
        let generation = model.sprites.generation
        model.close(reduceMotion: true)
        #expect(model.sprites.base != nil && model.sprites.generation == generation)
    }

    /// 序列圖是本機素材、與連線無關：斷線不釋放（唱機畫面還在時，重連後不會少了唱臂）
    @Test func connectionLossKeepsSprites() async {
        let model = makeModel()
        await shown(model)
        model.selectSkin("s-arm-1200")
        model.prepareSprites(layoutScale: 1.7)
        let generation = model.sprites.generation
        model.connectionLost()
        #expect(model.sprites.generation == generation)
    }

    /// R2-2 ①–⑥：世代不符＝晚到，忽略；符合＝釋放、移出清單、回 classic
    @Test func decodeFailureDisablesTheSkinForThisSession() async {
        let model = makeModel()
        await shown(model)
        model.selectSkin("s-arm-1200")
        model.prepareSprites(layoutScale: 1.7)
        let generation = model.sprites.generation
        model.disableSkin("s-arm-1200", generation: generation - 1)
        #expect(model.skin.spec.id == "s-arm-1200" && model.availableSkins.count == 2, "晚到的回報不動作")
        model.disableSkin("s-arm-1200", generation: generation)
        #expect(model.sprites.generation > generation && model.sprites.base == nil)
        #expect(model.availableSkins.map(\.spec.id) == ["classic"])
        #expect(model.skin == .classic)
        #expect(!model.canSelectSkin, "只剩一款＝不顯示切換器")
        #expect(store.string(forKey: TurntableViewModel.skinKey) == "s-arm-1200", "存值不改寫")
        model.selectSkin("s-arm-1200")
        #expect(model.skin == .classic, "本 session 不再可選")
    }

    /// 目前不是該皮膚（例如回報抵達前已切回 classic）：只移出清單，不改目前皮膚
    @Test func disablingAnotherSkinKeepsTheCurrentOne() async {
        let model = makeModel()
        await shown(model)
        model.disableSkin("s-arm-1200", generation: model.sprites.generation)
        #expect(model.skin == .classic && model.availableSkins.map(\.spec.id) == ["classic"])
    }

    /// 快取的失敗回報接到 disableSkin（組裝在 VM 內，不靠外部接線）
    @Test func cacheFailureIsWiredToDisableSkin() async {
        let model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { _ in nil },
                                       palette: { _ in .fallback }, sleep: { _ in }, transitionSleep: { _ in },
                                       catalog: catalog, spriteDecode: { _ in nil })
        await shown(model)
        model.selectSkin("s-arm-1200")
        model.prepareSprites(layoutScale: 1.7)
        for _ in 0..<5000 where model.skin != .classic { await Task.yield() }
        #expect(model.skin == .classic && model.availableSkins.count == 1)
    }

    // MARK: 增補 A（yse-1.0.1-skin-picker.md §4.2）：「可瀏覽」與「可套用」拆開

    /// 入口（設定頁區段、浮層按鈕）只看有沒有兩款以上，與唱機狀態無關
    @Test func browsingDependsOnlyOnHowManySkinsAreAvailable() async {
        let model = makeModel()
        #expect(model.canBrowseSkins, "唱機未開也可瀏覽")
        await shown(model)
        #expect(model.canBrowseSkins)
        model.disableSkin("s-arm-1200", generation: model.sprites.generation)
        #expect(!model.canBrowseSkins, "只剩一款＝沒有入口")
    }

    /// 唱機未開：可套用——存值、換皮膚、釋放關唱機時保留的幀（下次開唱機再解）
    @Test func selectingWhileHiddenStoresAndReleasesKeptSprites() async {
        let model = makeModel()
        await shown(model)
        model.selectSkin("s-arm-1200")
        model.prepareSprites(layoutScale: 1.7)
        for _ in 0..<5000 where !model.sprites.isComplete { await Task.yield() }
        model.close(reduceMotion: true)
        for _ in 0..<1000 where model.layer != .hidden { await Task.yield() }
        #expect(model.layer == .hidden && model.sprites.base != nil, "A′：關唱機保留")
        #expect(model.skinApplyBlock == nil && model.canSelectSkin)
        model.selectSkin("classic")
        #expect(model.skin == .classic && store.string(forKey: TurntableViewModel.skinKey) == "classic")
        #expect(model.sprites.base == nil, "換皮膚＝釋放")
    }

    /// 擋下的原因只有一種：唱機在轉場（進場、離場、甩動、封套動作）
    @Test func applyIsBlockedOnlyDuringTurntableTransitions() async {
        let hanging = makeModel(transitionSleep: { _ in await withCheckedContinuation { _ in } })
        #expect(hanging.skinApplyBlock == nil, "hidden")
        hanging.open(reduceMotion: false)
        #expect(hanging.skinApplyBlock == TurntableViewModel.SkinApplyBlock.turntableTransition, "entering")

        let model = makeModel()
        await shown(model)
        #expect(model.skinApplyBlock == nil, "shown")
        #expect(model.tapSleeve())
        #expect(model.skinApplyBlock == TurntableViewModel.SkinApplyBlock.turntableTransition, "封套動作中")
        model.sleeveMidwayFinished()
        #expect(model.skinApplyBlock == nil)
    }

    @Test func applyIsBlockedWhileLeaving() async {
        // 進場用 Reduce Motion（立即 shown）；離場不用 Reduce Motion 的滑動時長＝卡住，停在 leaving
        let slide = TurntableEntrance.duration(of: .sliding, reduceMotion: false)
        let model = makeModel(transitionSleep: { duration in
            if duration == slide { let _: Void = await withCheckedContinuation { _ in } }
        })
        await shown(model)
        model.close(reduceMotion: false)
        #expect(model.skinApplyBlock == TurntableViewModel.SkinApplyBlock.turntableTransition, "leaving")
        model.selectSkin("s-arm-1200")
        #expect(model.skin == .classic)
    }

    // MARK: 增補 A §4.3／§4.4：預覽 owner、離開唱機清 hold

    /// 選擇器開著時斷線或關唱機：hold 清空，浮層恢復自動隱藏（不依賴視圖卸載時的回呼，r2-1）
    @Test func leavingTheTurntableEndsThePickerHold() async {
        for leave in [{ (m: TurntableViewModel) in m.hideImmediately() }, { (m: TurntableViewModel) in m.close(reduceMotion: true) }] {
            let model = makeModel()
            await shown(model)
            model.overlay.toggle()
            model.overlay.beginHold(.skinPicker)
            leave(model)
            #expect(model.overlay.holds.isEmpty)
            for _ in 0..<1000 where model.overlay.isVisible { await Task.yield() }
            #expect(!model.overlay.isVisible, "計時恢復（測試的 sleep 立即返回）")
        }
    }

    /// 預覽失敗只影響格子：可用清單與可選狀態不變（r1-3）；預覽 renderer 由 VM 持有、兩個入口共用（r3-1）
    @Test func previewFailureDoesNotDisableTheSkin() async throws {
        struct FailingSource: SkinPreviewImageSource {
            func image(_ kind: SkinPreviewLayer.Kind, skin: ResolvedTurntableSkin, maxPixelSize: Int) async -> CGImage? { nil }
        }
        let model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { _ in nil },
                                       palette: { _ in .fallback }, sleep: { _ in }, transitionSleep: { _ in },
                                       catalog: catalog, spriteDecode: { _ in Self.pixel }, previewSource: FailingSource())
        let sArm = try #require(model.availableSkins.last)
        await model.previews.load(sArm, crop: .wholeArm, pixelSize: CGSize(width: 60, height: 200))
        #expect(model.previews.isUnavailable(sArm.spec.id))
        #expect(model.availableSkins.map(\.spec.id) == ["classic", "s-arm-1200"] && model.canSelectSkin)
    }
}
