import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import YogSothothsEcho

// F10 T2c／T2d（附錄 E.4）：詳情三模式、字色遲滯、封面投影、取樣
private func solid(_ color: UIColor, _ size: CGSize) -> UIImage {
    UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        .image { context in color.setFill(); context.fill(CGRect(origin: .zero, size: size)) }
}

struct DetailBackgroundModelTests {
    /// 主色 hsl(h, S, l)：飽和夾 18–48%；深色 c1＝亮度 22%、c2＝32%
    @Test func albumColorClampsSaturation() {
        let gray = RGBColor(r: 0.5, g: 0.5, b: 0.5)            // S＝0 → 夾到 18
        let vivid = RGBColor(r: 1, g: 0, b: 0)                 // S＝100 → 夾到 48
        #expect(abs(DetailBackgroundModel.clampedSaturation(of: gray) - 18) < 1e-9)
        #expect(abs(DetailBackgroundModel.clampedSaturation(of: vivid) - 48) < 1e-9)
        let mid = RGBColor(hue: 200, saturation: 30, lightness: 50)
        #expect(abs(DetailBackgroundModel.clampedSaturation(of: mid) - 30) < 0.5)
    }

    @Test func albumColorDarkStopsUseTheSpecLightness() {
        let stops = DetailBackgroundModel.albumColorStops(primary: RGBColor(r: 1, g: 0, b: 0), scheme: .dark)
        #expect(stops.c1 == RGBColor(hue: 0, saturation: 48, lightness: 22))
        #expect(stops.c2 == RGBColor(hue: 0, saturation: 48, lightness: 32))
        let light = DetailBackgroundModel.albumColorStops(primary: RGBColor(r: 1, g: 0, b: 0), scheme: .light)
        #expect(light.c1 == RGBColor(hue: 0, saturation: 40, lightness: 80))
        #expect(light.c2 == RGBColor(hue: 0, saturation: 50, lightness: 88))
    }

    /// 145° 線性：左上偏 c2、右下偏 c1（加柔光前）；兩端亮度差方向正確
    @Test func albumColorGradientRunsFromC2ToC1() {
        let size = CGSize(width: 1376, height: 940)
        let primary = RGBColor(hue: 210, saturation: 40, lightness: 50)
        let topLeft = DetailBackgroundModel.albumColor(primary: primary, scheme: .dark, at: CGPoint(x: 10, y: 10), in: size)
        let bottomRight = DetailBackgroundModel.albumColor(primary: primary, scheme: .dark, at: CGPoint(x: 1366, y: 930), in: size)
        #expect(topLeft.luminance > bottomRight.luminance)
    }

    /// 字色：≤0.174 白、≥0.214 深，帶內沿用；首判以 0.194
    @Test func inkHysteresis() {
        #expect(DetailBackgroundModel.ink(luminance: 0.174, previous: .dark) == .white)
        #expect(DetailBackgroundModel.ink(luminance: 0.214, previous: .white) == .dark)
        #expect(DetailBackgroundModel.ink(luminance: 0.20, previous: .white) == .white)
        #expect(DetailBackgroundModel.ink(luminance: 0.18, previous: .dark) == .dark)
        #expect(DetailBackgroundModel.ink(luminance: 0.19, previous: nil) == .white)
        #expect(DetailBackgroundModel.ink(luminance: 0.20, previous: nil) == .dark)
    }

    @Test func coverShadowFollowsBackgroundLuminance() {
        #expect(DetailBackgroundModel.coverShadowOpacity(luminance: 0.05) == 0.675)
        #expect(DetailBackgroundModel.coverShadowOpacity(luminance: 0.16) == 0.675)
        #expect(abs(DetailBackgroundModel.coverShadowOpacity(luminance: 0.23) - 0.4625) < 1e-9)
        #expect(DetailBackgroundModel.coverShadowOpacity(luminance: 0.30) == 0.25)
        #expect(DetailBackgroundModel.coverShadowOpacity(luminance: 0.8) == 0.25)
    }

    @Test func samplingRegionsFollowTheCover() {
        let cover = CGRect(x: 200, y: 100, width: 400, height: 400)
        #expect(DetailBackgroundModel.infoRegion(cover: cover) == CGRect(x: 200, y: 508, width: 400, height: 180))
        #expect(DetailBackgroundModel.underCoverRegion(cover: cover) == CGRect(x: 200, y: 500, width: 400, height: 60))
        let list = DetailBackgroundModel.listRegion(cover: cover, size: CGSize(width: 1376, height: 900))
        #expect(abs(list.minX - (600 + 0.096 * 1376)) < 1e-9 && list.maxX == 1376 - 40)
        #expect(list.minY == 70 && list.maxY == 900)
    }

    /// 12×12 格中心點的平均：單色＝該色亮度；左右兩色＝平均
    @Test func averageLuminanceUsesTwelveByTwelveCenters() {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 120)
        var count = 0
        let uniform = DetailBackgroundModel.averageLuminance(in: rect) { _ in count += 1; return RGBColor(r: 0.5, g: 0.5, b: 0.5) }
        #expect(count == 144)
        #expect(abs(uniform - RGBColor(r: 0.5, g: 0.5, b: 0.5).luminance) < 1e-12)
        let split = DetailBackgroundModel.averageLuminance(in: rect) { $0.x < 60 ? .black : .white }
        #expect(abs(split - 0.5) < 1e-12)
    }

    /// 模糊圖以 aspect-fill 鋪滿詳情：寬圖鋪到高、左右裁；取樣點對到圖中央；疊黑 0.2
    @Test func blurSamplerMapsAspectFillAndDims() throws {
        let left = solid(.black, CGSize(width: 50, height: 50)), right = solid(.white, CGSize(width: 50, height: 50))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in left.draw(at: .zero); right.draw(at: CGPoint(x: 50, y: 0)) }
        let sampler = try #require(BlurSampler(image: image))
        let size = CGSize(width: 400, height: 400)   // 寬圖鋪到高 400 → 寬 800，左右各裁 200
        let leftColor = sampler.color(at: CGPoint(x: 10, y: 200), in: size)
        let rightColor = sampler.color(at: CGPoint(x: 390, y: 200), in: size)
        #expect(leftColor.r < 0.02)
        #expect(abs(rightColor.r - 0.8) < 0.02)    // 白疊黑 0.2
    }
}

@MainActor
struct DetailBackgroundControllerTests {
    /// 可控的產生器：每次請求掛起，由測試決定何時、以什麼結果完成
    final class ManualProducer: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [(id: String, continuation: CheckedContinuation<DetailBackgroundProduct?, Never>)] = []
        private var names: [ObjectIdentifier: String] = [:]

        func image(_ id: String, side: CGFloat = 8) -> UIImage {
            let image = solid(.gray, CGSize(width: side, height: side))
            lock.withLock { names[ObjectIdentifier(image)] = id }
            return image
        }

        deinit { for entry in pending { entry.continuation.resume(returning: nil) } }

        var count: Int { lock.withLock { pending.count } }
        var requests: [String] { lock.withLock { pending.map(\.id) } }

        func produce(_ image: UIImage, _ mode: DetailBackgroundMode) async -> DetailBackgroundProduct? {
            let id = lock.withLock { names[ObjectIdentifier(image)] ?? "?" }
            return await withCheckedContinuation { c in lock.withLock { pending.append((id, c)) } }
        }

        func finish(_ id: String, with product: DetailBackgroundProduct?) {
            let entry: CheckedContinuation<DetailBackgroundProduct?, Never>? = lock.withLock {
                guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
                return pending.remove(at: index).continuation
            }
            entry?.resume(returning: product)
        }
    }

    private func color(_ v: Double) -> DetailBackgroundProduct { DetailBackgroundProduct(primary: RGBColor(r: v, g: v, b: v), blurred: nil) }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    private func request(_ c: DetailBackgroundController, _ album: String, token: String? = "t", image: UIImage?, mode: DetailBackgroundMode = .albumColor,
                         scheme: ColorScheme = .dark) {
        c.update(DetailBackgroundController.Request(albumID: album, artworkToken: token, image: image, mode: mode, scheme: scheme))
    }

    @Test func newAlbumStartsAsGradientUntilItsResultArrives() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: producer.image("A"))
        await settle()
        producer.finish("A", with: color(0.3))
        await settle()
        #expect(c.content == .albumColor(RGBColor(r: 0.3, g: 0.3, b: 0.3)))
        request(c, "B", image: producer.image("B"))
        #expect(c.content == .gradient, "換專輯立即清掉前一張")
    }

    @Test func lateResultForAPreviousAlbumDoesNotOverwrite() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: producer.image("A"))
        await settle()
        request(c, "B", image: producer.image("B"))
        await settle()
        producer.finish("B", with: color(0.6))
        await settle()
        producer.finish("A", with: color(0.1))
        await settle()
        #expect(c.content == .albumColor(RGBColor(r: 0.6, g: 0.6, b: 0.6)))
    }

    @Test func returningToACachedAlbumAppliesWithoutRecomputing() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: producer.image("A"))
        await settle()
        producer.finish("A", with: color(0.3))
        await settle()
        request(c, "B", image: producer.image("B"))
        await settle()
        producer.finish("B", with: color(0.6))
        await settle()
        request(c, "A", image: producer.image("A"))
        #expect(c.content == .albumColor(RGBColor(r: 0.3, g: 0.3, b: 0.3)))
        await settle()
        #expect(producer.count == 0)
    }

    @Test func newArtworkTokenRecomputes() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", token: "t1", image: producer.image("A1"))
        await settle()
        producer.finish("A1", with: color(0.3))
        await settle()
        request(c, "A", token: "t2", image: producer.image("A2"))
        await settle()
        #expect(producer.requests == ["A2"])
        producer.finish("A2", with: color(0.7))
        await settle()
        #expect(c.content == .albumColor(RGBColor(r: 0.7, g: 0.7, b: 0.7)))
    }

    /// 同一 token：spine 小圖先到、原檔後到——不能沿用小圖做的結果（codex simcodex R1）
    @Test func higherResolutionArtworkRecomputesUnderTheSameToken() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: producer.image("spine", side: 8))
        await settle()
        producer.finish("spine", with: color(0.3))
        await settle()
        request(c, "A", image: producer.image("detail", side: 64))
        await settle()
        #expect(producer.requests == ["detail"])
        #expect(c.content == .albumColor(RGBColor(r: 0.3, g: 0.3, b: 0.3)), "原檔結果到之前沿用 spine 的，不閃回漸層")
    }

    @Test func switchingModeOrSchemeRecomputes() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: producer.image("A"))
        await settle()
        producer.finish("A", with: color(0.3))
        await settle()
        request(c, "A", image: producer.image("A"), mode: .gradient)
        #expect(c.content == .gradient)
        request(c, "A", image: producer.image("A"), scheme: .light)
        await settle()
        #expect(producer.count == 1, "換主題＝新鍵，要重算")
    }

    @Test func noArtworkStaysGradientThenUpgradesWhenArtworkArrives() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: nil)
        await settle()
        #expect(c.content == .gradient && producer.count == 0)
        request(c, "A", image: producer.image("A"))
        await settle()
        producer.finish("A", with: color(0.4))
        await settle()
        #expect(c.content == .albumColor(RGBColor(r: 0.4, g: 0.4, b: 0.4)))
    }

    @Test func failedProductionStaysGradient() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: producer.image("A"))
        await settle()
        producer.finish("A", with: nil)
        await settle()
        #expect(c.content == .gradient)
    }

    @Test func memoryWarningEmptiesTheCache() async {
        let producer = ManualProducer()
        let c = DetailBackgroundController(produce: producer.produce)
        request(c, "A", image: producer.image("A"))
        await settle()
        producer.finish("A", with: color(0.3))
        await settle()
        c.purgeCache()
        request(c, "B", image: producer.image("B"))
        request(c, "A", image: producer.image("A"))
        await settle()
        #expect(producer.requests.contains("A"))
    }
}

/// 字色判定跟著詳情頁：兩區各自遲滯；換專輯重新首判
@MainActor
struct DetailInkStateTests {
    @Test func regionsDecideIndependentlyAndKeepHistoryWithinOnePage() {
        var state = DetailInkState()
        state.update(info: 0.05, list: 0.6, under: 0.1)
        #expect(state.info == .white && state.list == .dark)
        state.update(info: 0.20, list: 0.19, under: 0.1)
        #expect(state.info == .white && state.list == .dark, "帶內沿用")
        state.reset()
        state.update(info: 0.20, list: 0.19, under: 0.1)
        #expect(state.info == .dark && state.list == .white, "新頁以 0.194 首判")
    }

    @Test func coverShadowIsDerivedFromTheUnderCoverRegion() {
        var state = DetailInkState()
        state.update(info: 0.1, list: 0.1, under: 0.23)
        #expect(abs(state.coverShadowOpacity - 0.4625) < 1e-9)
    }

    @Test func increasedContrastMakesSecondaryTextOpaque() {
        #expect(DetailInk.white.secondaryOpacity(increasedContrast: true) == 1)
        let normal = DetailInk.white.secondaryOpacity(increasedContrast: false)
        #expect(normal >= 0.5 && normal <= 0.75)
    }
}
