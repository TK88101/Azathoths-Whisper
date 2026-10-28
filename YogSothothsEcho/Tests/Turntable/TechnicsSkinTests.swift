import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import YogSothothsEcho

// CR-034 增補 B T3（yse-1.0.1-skin-technics.md §4.4）：technics-sl1200g 採預設構圖（唱片不移），底座三層：
// 下層外盤（缺口）在唱片下、刻度環＋臂夾（base_middle）在唱片上唱臂下。素材取自 app bundle（Resources/Skins/technics-sl1200g）

private let landscapeSizes: [CGSize] = [
    CGSize(width: 1024, height: 768), CGSize(width: 1080, height: 810), CGSize(width: 1133, height: 744),
    CGSize(width: 1180, height: 820), CGSize(width: 1194, height: 834), CGSize(width: 1210, height: 834),
    CGSize(width: 1366, height: 1024), CGSize(width: 1376, height: 1032),
]

private func screen(_ size: CGSize) -> CGRect { CGRect(origin: .zero, size: size) }
private func safeArea(_ size: CGSize) -> CGRect { CGRect(x: 0, y: 24, width: size.width, height: size.height - 44) }

/// 下層外盤與可見唱片圓周至少要隔這麼遠（u；r6 實測 1.98 u）
private let underlayClearance: CGFloat = 1.5

struct TechnicsSkinTests {
    private func technics() throws -> ResolvedTurntableSkin { try SpriteSkinFixture.bundled(.technicsSL1200G) }

    @Test func registeredAsTheFourthSkinNamedTechnics() {
        #expect(TurntableSkinEntry.all.last?.id == "technics-sl1200g")
        #expect(TurntableSkinEntry.all.last?.title.key == "Technics")
    }

    /// 預設構圖：唱片圓心、支點螢幕位置與 classic 相同；起止角＝classic 的 14.1°／33.4°（針尖與支點契約相同）
    @Test(arguments: landscapeSizes)
    func recordStaysInTheClassicPosition(size: CGSize) throws {
        let skin = try technics()
        let t = TurntableLayout(container: screen(size), fullCover: false, skin: skin)
        let c = TurntableLayout(container: screen(size), fullCover: false, skin: .classic)
        #expect(skin.spec.placement == .classic)
        #expect(abs(t.record.midX - c.record.midX) < 1e-6 && abs(t.record.midY - c.record.midY) < 1e-6)
        #expect(abs(t.armPivot.x - c.armPivot.x) < 1e-6 && abs(t.armPivot.y - c.armPivot.y) < 1e-6)
        #expect(abs(skin.startDegrees - 14.1) <= 0.05 && abs(skin.endDegrees - 33.4) <= 0.05)
    }

    @Test func hasAMiddleLayerWithAHitMask() throws {
        let spec = try technics().spec
        let middle = try #require(spec.baseMiddle)
        let mask = try #require(spec.middleHitMask)
        #expect(mask.rows.count == Int((middle.size.height * 4).rounded()))
        #expect(mask.rows.contains { !$0.isEmpty })
    }

    @Test(arguments: landscapeSizes, [false, true])
    func everyLayerStaysInsideTheSafeArea(size: CGSize, fullCover: Bool) throws {
        let skin = try technics()
        let layout = TurntableLayout(container: screen(size), fullCover: fullCover, skin: skin)
        let safe = safeArea(size).insetBy(dx: -0.5, dy: -0.5)
        #expect(safe.contains(layout.record) && safe.contains(layout.armBase), "\(size)")
        if let overlay = layout.armBaseOverlay { #expect(safe.contains(overlay), "上層底座 \(size)") }
        let middle = try #require(layout.armBaseMiddle)
        #expect(safe.contains(middle), "中層底座 \(size)")
        for angle in stride(from: 0.0, through: skin.endDegrees, by: 0.5) {
            #expect(safe.contains(layout.armBoundingBox(angle: angle)), "唱臂 \(size) \(angle)°")
            if let shadow = layout.shadowBoundingBox(angle: angle) { #expect(safe.contains(shadow), "唱臂投影 \(size) \(angle)°") }
        }
    }

    /// 中層 zIndex 1.2 在常態封套（0.5）之上：兩者不能重疊，否則刻度環會蓋到封套
    @Test(arguments: landscapeSizes)
    func middleLayerNeverOverlapsTheRestingSleeve(size: CGSize) throws {
        let layout = TurntableLayout(container: screen(size), fullCover: false, skin: try technics())
        let middle = try #require(layout.armBaseMiddle)
        #expect(!middle.intersects(layout.coverBoundingBox), "\(size)")
    }

    /// 下層外盤（唱片下）任何 alpha>0 的像素都在可見唱片圓外 ≥ 1.5 u：唱片卡在缺口、留一道縫（使用者 2026-10-28 認可的版面）
    @Test func underlayClearsTheVisibleRecord() throws {
        let spec = try technics().spec
        let url = try #require(Bundle.main.url(forResource: "base_underlay", withExtension: "png", subdirectory: "Skins/technics-sl1200g"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        let origin = spec.baseOrigin, unit = CGFloat(width) / spec.base.size.width
        let center = TurntableMetrics.recordSize / 2, radius = TurntableMetrics.recordSize / 2 * TurntableMetrics.recordVisibleScale
        var nearest = CGFloat.infinity
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                let u = CGPoint(x: origin.x + (CGFloat(x) + 0.5) / unit, y: origin.y + (CGFloat(y) + 0.5) / unit)
                nearest = min(nearest, hypot(u.x - center, u.y - center) - radius)
            }
        }
        #expect(nearest >= underlayClearance, "離唱片圓周 \(nearest) u")
    }

    /// 記憶體閘門（≤ 200 MiB）：真素材、真解碼器，13 吋與 mini
    @MainActor
    @Test(arguments: [800.0, 576.6])
    func realAssetsDecodeWithinTheMemoryBudget(recordDiameter: Double) async throws {
        let cache = TonearmSpriteCache(onFailure: { _, _ in Issue.record("解碼失敗") })
        cache.load(try technics(), pixelScale: recordDiameter / TurntableMetrics.recordSize * 2)
        let deadline = ContinuousClock.now + .seconds(60)
        while !cache.isComplete, ContinuousClock.now < deadline { await Task.yield() }
        #expect(cache.isComplete && cache.pairs.count == SpriteSkinAssets.frameCount)
        let mib = Double(cache.residentBytes) / 1_048_576
        #expect(mib <= 200, "常駐 \(mib) MiB")
        print("CR-034 technics memory: R=\(recordDiameter) → \(String(format: "%.1f", mib)) MiB")
    }
}
