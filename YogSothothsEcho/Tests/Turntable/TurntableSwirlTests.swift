import Foundation
import RemoteProtocol
import RemoteTransport
import Testing
import UIKit

@testable import YogSothothsEcho

// CR-037 T6（yse-swirl-style.md §4.1b、§4.4 資料流、§4.5b）：煙渦變化設定存取、deck 帶配方（RANDOM 抽到煙渦也跟設定，Q6）、
// 浮層煙渦第二排的開合（以 hold 為唯一狀態）、強調色退回註記讀畫面上的主唱片
@MainActor
struct TurntableSwirlTests {
    let client = FakePlaybackClient()
    let nowPlaying = NowPlayingViewModel(now: ManualNow().now, sleep: { _ in })
    let store = InMemorySettingsStore()

    /// 青綠主色、沒有鮮色也沒有 MUTED：手選強調色時一定退回
    private static let tealOnly = AlbumColors(primary: RGBColor(hex: 0x1E8C8C), text: .white, secondary: RGBColor(hex: 0x46403C),
                                              hasMuted: false, vivid: nil)

    private func makeModel(colors: AlbumColors = .fallback) -> TurntableViewModel {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
        return TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { _ in image },
                                  palette: { _ in colors }, sleep: { _ in })
    }

    private func start(track: String) async {
        nowPlaying.attach(client)
        await settle()
        client.push(PlaybackSamples.event(track, .playing, at: 1))
        await settle()
    }

    @Test func smokeVariantPersists() {
        let model = makeModel()
        #expect(model.smokeVariant == .auto)
        model.smokeVariant = .lightInk
        #expect(store.string(forKey: TurntableViewModel.smokeVariantKey) == "lightInk")
        #expect(makeModel().smokeVariant == .lightInk)
    }

    @Test func deckCarriesRecipeFollowingTheSmokeSetting() async {
        let model = makeModel()
        await start(track: "000000000000004a") // RANDOM 分桶 91＝SMOKE
        model.recordStyle = .random
        model.smokeVariant = .darkInk
        #expect(model.resolvedStyle == .smoke)
        #expect(model.liveDeck.swirl?.subtype == .smoke && model.liveDeck.swirl?.ink == .dark)
        model.smokeVariant = .water
        #expect(model.liveDeck.swirl?.subtype == .smokeWater)
        model.recordStyle = .streak
        #expect(model.liveDeck.swirl?.subtype == .pull)
        model.recordStyle = .marble
        #expect(model.liveDeck.swirl == nil)
    }

    @Test func smokeRowOpensClosesAndDiesWithTheOverlay() {
        let model = makeModel()
        model.overlay.toggle()
        model.tapStyle(.smoke)
        #expect(model.recordStyle == .smoke && model.isSmokeRowOpen)
        model.tapStyle(.smoke)
        #expect(model.recordStyle == .smoke && !model.isSmokeRowOpen)
        model.tapStyle(.smoke)
        #expect(model.isSmokeRowOpen)
        model.tapStyle(.flake)
        #expect(model.recordStyle == .flake && !model.isSmokeRowOpen)
        model.tapStyle(.smoke)
        model.overlay.toggle()   // 浮層收起
        #expect(!model.isSmokeRowOpen)
        model.overlay.toggle()
        #expect(!model.isSmokeRowOpen)
    }

    /// 選變化不收合、展開期間浮層不自動隱藏（hold）
    @Test func choosingAVariantKeepsTheRowOpen() {
        let model = makeModel()
        model.overlay.toggle()
        model.tapStyle(.smoke)
        model.smokeVariant = .accent
        #expect(model.isSmokeRowOpen && model.overlay.holds.contains(.smokeVariants))
    }

    /// 第二排位置：對齊 SMOKE、靠邊時往內推、左右留 16 pt；容器比第二排還窄＝置中
    @Test func smokeRowStaysInsideTheContainer() {
        #expect(SmokeRowLayout.centerX(anchorX: 600, rowWidth: 400, containerWidth: 1200) == 600)
        #expect(SmokeRowLayout.centerX(anchorX: 100, rowWidth: 400, containerWidth: 1200) == 216)
        #expect(SmokeRowLayout.centerX(anchorX: 1150, rowWidth: 400, containerWidth: 1200) == 984)
        #expect(SmokeRowLayout.centerX(anchorX: 100, rowWidth: 400, containerWidth: 300) == 150)
    }

    /// 新 4 個圖示在公開 asset catalog（沒有本機 MD Vinyl 素材也有）
    @Test func swirlIconsAreBundled() {
        for style in RecordStyle.allCases where style.isSwirl {
            #expect(TurntableOverlay.iconImage(style.icon) != nil, "\(style)")
        }
    }

    @Test func accentFallbackReadsTheShownRecord() async {
        let model = makeModel(colors: Self.tealOnly)
        await start(track: "000000000000004a")
        await model.loadArtwork(albumID: PlaybackSamples.album)
        model.recordStyle = .smoke
        model.smokeVariant = .accent
        #expect(model.smokeAccentFallback != nil)
        model.smokeVariant = .darkInk
        #expect(model.smokeAccentFallback == nil)
    }
}
