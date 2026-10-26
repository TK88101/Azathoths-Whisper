import CoreGraphics
import Testing
import UIKit

@testable import YogSothothsEcho

// S5 v2.0 轉動參照（sprint-5-detail.md §4.2b v2.0；使用者 2026-10-21 看小樣 s5-rotation-cue-preview.html 選定）：
// CLASSIC＝B1 寬光暈；TRANSPARENT 磨砂＝小樣的點（較大較少）＋B3 放射紋；降低透明度＝只有放射紋

struct RotationCueTests {
    /// 樣式 × 質感的對應窮舉：SPLASH、MARBLE 原本就有明顯旋轉圖案，不加；TRANSPARENT 一律磨砂（v2.1 T9 去掉黑色分支）
    @Test func cueForEveryStyleAndFinish() {
        #expect(RotationCue.cue(style: .classic, finish: nil) == .sheen)
        #expect(RotationCue.cue(style: .random, finish: nil) == .sheen)
        #expect(RotationCue.cue(style: .transparent, finish: .frosted) == .radialWithSpecks)
        #expect(RotationCue.cue(style: .transparent, finish: .opaque) == .radial)
        #expect(RotationCue.cue(style: .transparent, finish: nil) == nil)
        #expect(RotationCue.cue(style: .splash, finish: nil) == nil)
        #expect(RotationCue.cue(style: .marble, finish: nil) == nil)
    }

    /// B1 光暈：兩片寬扇形，位置遞增、頭尾透明（繞回不接縫）、最亮 0.10
    @Test func sheenStopsAreTwoSoftLobesWithoutSeam() {
        let stops = RotationSheen.stops
        #expect(stops.map(\.location) == [0, 0.12, 0.24, 0.55, 0.66, 0.78, 1])
        #expect(stops.map(\.opacity) == [0, 0.10, 0, 0, 0.07, 0, 0])
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location < $1.location })
    }

    /// 放射紋顏色（v2.1 T5）：不透明盤用標籤字色（淺色盤＝黑線、深色盤＝白線；白主色白線看不見），磨砂盤維持白
    @Test func rayColorContrastsWithOpaqueDisc() {
        let white = AlbumColors(primary: .white, text: .black, secondary: .white)
        let navy = AlbumColors(primary: RGBColor(hex: 0x1B2A4A), text: .white, secondary: .white)
        #expect(RotationCue.rayColor(finish: .opaque, colors: white) == .black)
        #expect(RotationCue.rayColor(finish: .opaque, colors: navy) == .white)
        #expect(RotationCue.rayColor(finish: .frosted, colors: white) == .white)
        #expect(RotationCue.rayColor(finish: nil, colors: white) == .white)
    }
}

struct RadialFieldTests {
    @Test func parkMillerMatchesMinimalStandard() {
        var rng = ParkMiller(seed: 1)
        // Park & Miller (1988) 最小標準：seed 1 → 16807 → 282475249 → 1622650073
        #expect(rng.nextRaw() == 16807)
        #expect(rng.nextRaw() == 282_475_249)
        #expect(rng.nextRaw() == 1_622_650_073)
    }

    @Test func sameSeedSameField() {
        #expect(RadialField.generate(seed: 7) == RadialField.generate(seed: 7))
        #expect(RadialField.generate(seed: 7) != RadialField.generate(seed: 8))
        #expect(RadialField.standard == RadialField.generate(seed: 7))
    }

    /// 釘住第一個點的核心欄位，防演算法或取樣順序漂移（期望值由 Python 獨立算出：seed 7 依序取角度、半徑、點徑 u、長寬比分桶、長寬比）
    @Test func goldenFirstValues() throws {
        let first = try #require(RadialField.standard.specks.first)
        #expect(abs(first.angle - 0.00034422169837569486) < 1e-12)
        #expect(abs(first.radius - 0.9469122263914498) < 1e-12)
        #expect(abs(first.size - 0.003171214658476979) < 1e-12)
        #expect(abs(first.aspect - 1.2552797316598148) < 1e-12)
    }

    /// 數量與範圍：點照小樣 A（v2.1 T1：輕度不規則）——900 點、r＝0.33＋u·0.67、點徑偏態 0.002＋u²·0.014、長寬比 1–4、
    /// 長軸偏離放射角 ≤45°、起伏 2θ 幅度 0.06–0.12／3θ 0–0.06、衛星 0–2 顆（距離 1.1–1.9 倍、半徑 0.2–0.45 倍）；
    /// 放射線照 v2.0：260 條、0.35→0.99、線寬 0.002–0.008、白 0.015–0.075；角度 [0, 2π)
    @Test func countsAndRangesFollowPrototype() {
        let field = RadialField.standard
        #expect(field.specks.count == 900)
        #expect(field.rays.count == 260)
        for speck in field.specks {
            #expect((0..<(2 * .pi)).contains(speck.angle))
            #expect(speck.radius >= 0.33 && speck.radius <= 1)
            #expect(speck.size >= 0.002 && speck.size <= 0.016)
            #expect(speck.aspect >= 1 && speck.aspect <= 4)
            #expect(abs(speck.orientation - speck.angle) <= .pi / 4 + 1e-12)
            #expect(speck.wobble2 >= 0.06 && speck.wobble2 <= 0.12 && speck.wobble3 >= 0 && speck.wobble3 <= 0.06)
            #expect(speck.satellites.count <= 2)
            for satellite in speck.satellites {
                #expect(satellite.distance >= 1.1 * speck.size && satellite.distance <= 1.9 * speck.size)
                #expect(satellite.radius >= 0.2 * speck.size && satellite.radius <= 0.45 * speck.size)
            }
        }
        for ray in field.rays {
            #expect((0..<(2 * .pi)).contains(ray.angle))
            #expect(ray.width >= 0.002 && ray.width <= 0.008)
            #expect(ray.opacity >= 0.015 && ray.opacity <= 0.075)
        }
        #expect(RadialField.rayStart == 0.35 && RadialField.rayEnd == 0.99 && RadialField.innerRadius == 0.33)
    }

    /// 基準橢圓面積守恆：長軸 ×√k、短軸 ÷√k（起伏不另補償，同小樣）
    @Test func baseEllipseKeepsTheCircleArea() {
        for speck in RadialField.standard.specks {
            #expect(abs(speck.semiMajor * speck.semiMinor - speck.size * speck.size) < 1e-12)
            #expect(speck.semiMajor >= speck.semiMinor)
        }
    }

    /// 形狀比例（多種子，防退化回圓點）：長寬比 70／27／3 分桶 ±5 個百分點、衛星 15% ±5 個百分點、起伏一律 >0
    @Test(arguments: [UInt64(7), 11, 13])
    func shapeSharesFollowPrototypeA(seed: UInt64) {
        let specks = RadialField.generate(seed: seed).specks
        let n = Double(specks.count)
        let round = Double(specks.filter { $0.aspect < 1.35 }.count) / n
        let oval = Double(specks.filter { $0.aspect >= 1.35 && $0.aspect < 2.5 }.count) / n
        let streak = Double(specks.filter { $0.aspect >= 2.5 }.count) / n
        let withSatellites = Double(specks.filter { !$0.satellites.isEmpty }.count) / n
        #expect(abs(round - 0.70) <= 0.05, "\(round)")
        #expect(abs(oval - 0.27) <= 0.05, "\(oval)")
        #expect(streak > 0 && streak <= 0.08, "\(streak)")
        #expect(abs(withSatellites - 0.15) <= 0.05, "\(withSatellites)")
        #expect(specks.allSatisfy { $0.wobble2 > 0 })
    }
}

@MainActor
struct RotationCueMaskTests {
    private static let side = 2000

    /// 點遮罩（照小樣靠圓形 clip）：0.28 以內與盤緣外沒有像素；環帶覆蓋率≈解析估計 6.3%（900·E[s²]／(1−0.33²)），
    /// 起伏與衛星另加，±35% 僅作 smoke test
    @Test func speckMaskCoverage() throws {
        let image = RotationCueMasks.specks(pixelSide: Self.side)
        let stats = try PixelStats(image: image)
        #expect(stats.count(radiusBelow: 0.28) == 0)
        #expect(stats.count(radiusAbove: 1.0 + 2.0 / Double(Self.side)) == 0)
        let ratio = stats.ringCoverage(inner: 0.33)
        #expect(ratio > 0.063 * 0.65 && ratio < 0.063 * 1.35, "\(ratio)")
    }

    /// 放射線遮罩：0.35 以內與 0.99 外沒有像素；幾何覆蓋率≈30% ±30%
    @Test func rayMaskCoverage() throws {
        let image = RotationCueMasks.rays(pixelSide: Self.side)
        let stats = try PixelStats(image: image)
        #expect(stats.count(radiusBelow: 0.35 - 0.006) == 0)
        #expect(stats.count(radiusAbove: 0.99 + 0.006) == 0)
        let ratio = stats.ringCoverage(inner: 0.33)
        #expect(ratio > 0.30 * 0.7 && ratio < 0.30 * 1.3, "\(ratio)")
    }

    /// 快取：同尺寸回同一張；最多保留 2 組尺寸
    @Test func masksAreCachedForTwoSizes() {
        RotationCueMasks.resetCache()
        let a = RotationCueMasks.specks(pixelSide: 400)
        #expect(RotationCueMasks.specks(pixelSide: 400) === a)
        _ = RotationCueMasks.specks(pixelSide: 500)
        #expect(RotationCueMasks.specks(pixelSide: 400) === a)
        _ = RotationCueMasks.specks(pixelSide: 600)          // 擠掉最久沒用的 500
        #expect(RotationCueMasks.cachedSides == [400, 600])
    }
}

/// 讀遮罩 alpha：以圓心為原點、半徑 1＝邊長的一半
private struct PixelStats {
    let side: Int
    let alpha: [UInt8]

    init(image: UIImage) throws {
        let cg = try #require(image.cgImage)
        side = cg.width
        var buffer = [UInt8](repeating: 0, count: side * side)
        let context = try #require(CGContext(data: &buffer, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        alpha = buffer
    }

    private func radius(_ index: Int) -> Double {
        let half = Double(side) / 2
        let x = Double(index % side) + 0.5 - half, y = Double(index / side) + 0.5 - half
        return (x * x + y * y).squareRoot() / half
    }

    func count(radiusBelow limit: Double) -> Int { alpha.indices.filter { alpha[$0] > 0 && radius($0) < limit }.count }
    func count(radiusAbove limit: Double) -> Int { alpha.indices.filter { alpha[$0] > 0 && radius($0) > limit }.count }

    func ringCoverage(inner: Double) -> Double {
        var inRing = 0, covered = 0
        for index in alpha.indices {
            let r = radius(index)
            guard r >= inner && r <= 1 else { continue }
            inRing += 1
            if alpha[index] > 0 { covered += 1 }
        }
        return Double(covered) / Double(inRing)
    }
}
