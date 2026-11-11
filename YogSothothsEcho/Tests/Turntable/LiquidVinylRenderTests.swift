#if LIQUID_SAMPLE
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import YogSothothsEcho

// CR-038 L-T2（yse-liquid-vinyl-sample.md v0.4 §4.1／§4.3）：著色器畫出來的像素——環帶外透明、可重現、外圈落後大於內圈

@MainActor
enum LiquidPixels {
    static let side = 400

    /// 只有液體層（不含盤體色）的 RGBA8 premultiplied 像素
    static func render(_ frame: LiquidFrame, side: Int = side) throws -> [UInt8] {
        let view = LiquidVinylLayer.liquid(frame, side: CGFloat(side))
        let renderer = ImageRenderer(content: view.frame(width: CGFloat(side), height: CGFloat(side)))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let context = try #require(CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }

    /// 以盤半徑＝1 的極座標取 alpha（y 向下、順時針為正）
    static func alpha(_ pixels: [UInt8], r: Double, degrees: Double, side: Int = side) -> Double {
        let half = Double(side) / 2
        let x = Int((half + r * half * cos(degrees * .pi / 180)).rounded(.down))
        let y = Int((half + r * half * sin(degrees * .pi / 180)).rounded(.down))
        guard (0..<side).contains(x), (0..<side).contains(y) else { return 0 }
        return Double(pixels[(y * side + x) * 4 + 3]) / 255
    }

    /// 某半徑一圈的 alpha 剖面（每 0.5° 一點）
    static func profile(_ pixels: [UInt8], r: Double) -> [Double] {
        (0..<720).map { alpha(pixels, r: r, degrees: Double($0) / 2) }
    }

    /// 兩個剖面的循環位移（度）：b 相對 a 轉了多少（正＝順時針）。最小平方差（內積相關在小位移時峰頂太平，會偏向 0）
    static func shift(from a: [Double], to b: [Double]) -> Double {
        let n = a.count
        var best = 0, bestScore = Double.infinity
        for k in 0..<n {
            var score = 0.0
            for i in 0..<n { let d = a[i] - b[(i + k) % n]; score += d * d }
            if score < bestScore { bestScore = score; best = k }
        }
        let degrees = Double(best) / 2
        return degrees > 180 ? degrees - 360 : degrees
    }
}

@MainActor
struct LiquidVinylRenderTests {
    private static let still = LiquidFrame(discAngle: 0, lag: 0, fling: 0, flingGain: 1)

    @Test func ringOutsideIsTransparentAndInsideHasLiquid() throws {
        let pixels = try LiquidPixels.render(Self.still)
        for degrees in stride(from: 0.0, to: 360, by: 7.5) {
            #expect(LiquidPixels.alpha(pixels, r: 0.40, degrees: degrees) == 0)
            #expect(LiquidPixels.alpha(pixels, r: 0.44, degrees: degrees) == 0)
            #expect(LiquidPixels.alpha(pixels, r: 0.985, degrees: degrees) == 0)
        }
        let inside = (0..<72).map { LiquidPixels.alpha(pixels, r: 0.65, degrees: Double($0) * 5) }
        #expect(inside.max() ?? 0 > 0.3)
    }

    @Test func sameUniformsRenderIdentically() throws {
        let frame = LiquidFrame(discAngle: 37, lag: 4, fling: 0.8, flingGain: 1.6)
        #expect(try LiquidPixels.render(frame) == LiquidPixels.render(frame))
    }

    /// s > 0：外圈圖樣往逆時針（落後）位移得比內圈多；位移量≈ −s·w(u)
    @Test func lagShiftsOuterRingMoreThanInner() throws {
        let lag = 30.0
        let base = try LiquidPixels.render(Self.still)
        let lagged = try LiquidPixels.render(LiquidFrame(discAngle: 0, lag: lag, fling: 0, flingGain: 1))
        func expected(_ r: Double) -> Double { let u = (r - 0.452) / (0.97 - 0.452); return -lag * u * u }
        let inner = LiquidPixels.shift(from: LiquidPixels.profile(base, r: 0.56), to: LiquidPixels.profile(lagged, r: 0.56))
        let outer = LiquidPixels.shift(from: LiquidPixels.profile(base, r: 0.92), to: LiquidPixels.profile(lagged, r: 0.92))
        #expect(abs(outer) > abs(inner) + 10, "inner \(inner) outer \(outer)")
        #expect(abs(inner - expected(0.56)) <= 1.5, "inner \(inner) vs \(expected(0.56))")
        #expect(abs(outer - expected(0.92)) <= 1.5, "outer \(outer) vs \(expected(0.92))")
    }

    /// 盤角：整個圖樣跟著順時針轉
    @Test func discAngleRotatesWholePattern() throws {
        let base = try LiquidPixels.render(Self.still)
        let turned = try LiquidPixels.render(LiquidFrame(discAngle: 40, lag: 0, fling: 0, flingGain: 1))
        for r in [0.56, 0.75, 0.92] {
            let moved = LiquidPixels.shift(from: LiquidPixels.profile(base, r: r), to: LiquidPixels.profile(turned, r: r))
            #expect(abs(moved - 40) <= 1, "r \(r) moved \(moved)")
        }
    }

    /// 外甩：濃度往外移（外圈 alpha 平均上升、內圈下降）
    @Test func flingMovesDyeOutward() throws {
        let base = try LiquidPixels.render(Self.still)
        let flung = try LiquidPixels.render(LiquidFrame(discAngle: 0, lag: 0, fling: 1.5, flingGain: 1.6))
        func mean(_ p: [UInt8], _ r: Double) -> Double { LiquidPixels.profile(p, r: r).reduce(0, +) / 720 }
        #expect(mean(flung, 0.88) > mean(base, 0.88) + 0.05)
        #expect(mean(flung, 0.60) < mean(base, 0.60) - 0.05)
    }

    /// 整合：液態覆蓋層在 VinylRecordView 的 drawingGroup 內也畫得出來（標籤蓋在上面、環帶有液體色）
    @Test func liquidOverlayRendersInsideRecordView() throws {
        let side: CGFloat = 400
        let view = VinylRecordView(side: side, style: .classic, splash: .style1, colors: .fallback,
                                   label: .init(title: "Title", artist: "Artist"), angle: 0, liquid: Self.still)
        let image = try #require(PixelProbe.image(view, size: CGSize(width: side, height: side)))
        let ring = PixelProbe.color(image, at: CGPoint(x: 200 + 0.70 * 200, y: 200))
        // 盤體半透明藍紫：藍 > 紅、藍 > 綠
        #expect(ring.b > ring.r && ring.b > ring.g, "\(ring)")
    }
}
#endif
