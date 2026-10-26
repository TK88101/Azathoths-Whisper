import SwiftUI
import Testing
import UIKit
@testable import YogSothothsEcho

// F10 T2b／T2e Render（附錄 E.8）：畫出來的像素與純函式／小樣一致
@MainActor
enum PixelProbe {
    static func image(_ view: some View, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.cgImage
    }

    /// 某點的 sRGB 0…1
    static func color(_ image: CGImage, at point: CGPoint) -> RGBColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -point.x, y: point.y - CGFloat(image.height) + 1, width: CGFloat(image.width), height: CGFloat(image.height)))
        return RGBColor(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
    }
}

@MainActor
struct BackgroundRenderTests {
    static let size = CGSize(width: 1376, height: 1032)

    /// 預設組在固定點與純函式差 ≤ 4/255（深淺兩版）
    @Test(arguments: [ColorScheme.dark, .light])
    func presetGradientMatchesTheModel(scheme: ColorScheme) throws {
        let image = try #require(PixelProbe.image(PresetGradientView(preset: .silverBlue, scheme: scheme, reduceTransparency: false), size: Self.size))
        for point in PresetSamples.points + [CGPoint(x: 400, y: 300), CGPoint(x: 1000, y: 800)] {
            let got = PixelProbe.color(image, at: point)
            let want = BackgroundModel.presetColor(preset: .silverBlue, scheme: scheme, at: point, in: Self.size)
            for (g, w) in zip([got.r, got.g, got.b], [want.r, want.g, want.b]) {
                #expect(abs(g - w) * 255 <= 4, "\(scheme) \(point)：\(got) vs \(want)")
            }
        }
    }

    /// 專輯主色背景（E.4）在固定點與純函式差 ≤ 4/255（字色取樣用的是純函式，兩者不能分歧）
    @Test(arguments: [ColorScheme.dark, .light])
    func albumColorBackgroundMatchesTheModel(scheme: ColorScheme) throws {
        let primary = RGBColor(hue: 210, saturation: 60, lightness: 45)
        let image = try #require(PixelProbe.image(AlbumColorBackgroundView(primary: primary, scheme: scheme), size: Self.size))
        for point in PresetSamples.points + [CGPoint(x: 1030, y: 120), CGPoint(x: 400, y: 800)] {
            let got = PixelProbe.color(image, at: point)
            let want = DetailBackgroundModel.albumColor(primary: primary, scheme: scheme, at: point, in: Self.size)
            for (g, w) in zip([got.r, got.g, got.b], [want.r, want.g, want.b]) {
                #expect(abs(g - w) * 255 <= 4, "\(scheme) \(point)：\(got) vs \(want)")
            }
        }
    }

    @Test func reduceTransparencyGradientIsTheSolidBaseColor() throws {
        let image = try #require(PixelProbe.image(PresetGradientView(preset: .silverBlue, scheme: .dark, reduceTransparency: true), size: Self.size))
        let base = BackgroundModel.baseColor(preset: .silverBlue, scheme: .dark)
        for point in PresetSamples.points {
            let got = PixelProbe.color(image, at: point)
            #expect(abs(got.r - base.r) * 255 <= 2 && abs(got.g - base.g) * 255 <= 2 && abs(got.b - base.b) * 255 <= 2)
        }
    }

    /// 壓暗畫在白底上：中心不變、邊中點與角落的 α 與純函式差 ≤ 0.02
    @Test func vignetteMatchesTheModel() throws {
        let image = try #require(PixelProbe.image(ZStack { Color.white; VignetteView() }, size: Self.size))
        for point in [CGPoint(x: 688, y: 495), CGPoint(x: 1, y: 495), CGPoint(x: 1, y: 1), CGPoint(x: 1375, y: 1031), CGPoint(x: 688, y: 1)] {
            let alpha = 1 - PixelProbe.color(image, at: point).g
            #expect(abs(alpha - BackgroundModel.vignetteAlpha(at: point, in: Self.size)) <= 0.02, "\(point) α \(alpha)")
        }
    }

    /// 倒影：單色底 B、原圖單色 C；由 P＝B(1−α)＋Cα 反解 α，與 α(q) 差 ≤ 0.02
    @Test func reflectionAlphaMatchesTheMaskFormula() throws {
        let height: CGFloat = 1000, floor: CGFloat = 1000   // 倒影點（y＝2000−1000q）全在原圖下方，不被原圖蓋住
        let scene = ZStack(alignment: .topLeading) {
            Color.black
            Color.white.frame(width: 400, height: height)   // 原圖：整塊白（盒正面）
                .floorReflection(floor: floor, size: CGSize(width: 400, height: height), enabled: true)
                .offset(x: 400)
        }
        let image = try #require(PixelProbe.image(scene, size: CGSize(width: 1200, height: 1400)))
        for q in [0.70, 0.80, 0.86, 0.95] {
            let y = 2 * floor - q * height          // 螢幕點
            let alpha = PixelProbe.color(image, at: CGPoint(x: 600, y: y)).r
            #expect(abs(alpha - BackgroundModel.reflectionAlpha(q: q)) <= 0.02, "q \(q) y \(y) α \(alpha)")
        }
    }

    @Test func reflectionIsAbsentWhenDisabled() throws {
        let scene = ZStack(alignment: .topLeading) {
            Color.black
            Color.white.frame(width: 400, height: 1000).floorReflection(floor: 900, size: CGSize(width: 400, height: 1000), enabled: false)
                .offset(x: 400)
        }
        let image = try #require(PixelProbe.image(scene, size: CGSize(width: 1200, height: 1300)))
        #expect(PixelProbe.color(image, at: CGPoint(x: 600, y: 1000)).r < 0.01)
    }

    /// 淡陰影帶：中心列最暗處 α 0.40±0.05
    @Test func shadowBandPeaksAtFortyPercent() throws {
        let width: CGFloat = 1000, floor: CGFloat = 400
        let image = try #require(PixelProbe.image(ZStack(alignment: .topLeading) { Color.white; ShadowBandView(floor: floor, width: width, unit: 1) },
                                                  size: CGSize(width: width, height: 700)))
        let darkest = (0..<700).map { 1 - PixelProbe.color(image, at: CGPoint(x: width / 2, y: CGFloat($0))).g }.max() ?? 0
        #expect(abs(darkest - 0.40) <= 0.05, "最暗 α \(darkest)")
    }
}
