import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-037 T4（yse-swirl-style.md §4.4，S0 選定 Metal compute＋M1 成品圖）：GPU 輸出只做容差式不變量——
// 盤外透明、中心不透明度＝配方、有花紋（非平塗）、同配方重烘一致、解析度改變外觀平均不變、裝置不可用回錯誤
struct SwirlBakerTests {
    private static let colors = AlbumColors(primary: RGBColor(hex: 0x960E1C), text: .white, secondary: RGBColor(hex: 0x786A60),
                                            vivid: RGBColor(hex: 0x3C46BE))

    private static func recipe(_ subtype: SwirlSubtype) -> SwirlRecipe {
        let opacity = subtype == .pull || subtype == .flake ? 1.0 : 0.95
        return SwirlRecipe(subtype: subtype, ink: subtype == .smoke ? .light : nil, noiseSeed: 7.37, body: 0.3, opacity: opacity)
    }

    /// premultiplied RGBA8
    private static func pixels(_ image: CGImage) -> (width: Int, data: [UInt8]) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, data)
    }

    private static func meanRGB(_ p: (width: Int, data: [UInt8])) -> (Double, Double, Double) {
        var sum = (0.0, 0.0, 0.0), n = 0.0
        let c = Double(p.width) / 2
        for y in 0..<p.width {
            for x in 0..<p.width where hypot(Double(x) + 0.5 - c, Double(y) + 0.5 - c) < c * 0.9 {
                let i = (y * p.width + x) * 4
                sum = (sum.0 + Double(p.data[i]), sum.1 + Double(p.data[i + 1]), sum.2 + Double(p.data[i + 2]))
                n += 1
            }
        }
        return (sum.0 / n / 255, sum.1 / n / 255, sum.2 / n / 255)
    }

    @Test(arguments: [SwirlSubtype.smokeWater, .smoke, .pull, .flake, .chunk])
    func bakesDiscWithPatternAndOpacity(_ subtype: SwirlSubtype) async throws {
        let baker = try SwirlBaker()
        let recipe = Self.recipe(subtype)
        let palette = SwirlPalette.resolve(recipe, colors: Self.colors, reduceTransparency: false)
        let image = try await baker.bake(recipe, colors: palette, side: 256).image
        #expect(image.width == 256 && image.height == 256)
        let p = Self.pixels(image)
        #expect(p.data[3] == 0, "盤外（左上角）透明")
        let center = (128 * 256 + 140) * 4
        #expect(abs(Double(p.data[center + 3]) / 255 - recipe.opacity) <= 1.5 / 255, "盤內不透明度＝配方")
        // 有花紋：盤內像素不是同一個顏色
        var distinct = Set<UInt32>()
        for y in stride(from: 40, to: 216, by: 4) {
            for x in stride(from: 40, to: 216, by: 4) {
                let i = (y * 256 + x) * 4
                distinct.insert(UInt32(p.data[i]) << 16 | UInt32(p.data[i + 1]) << 8 | UInt32(p.data[i + 2]))
            }
        }
        #expect(distinct.count > 20, "\(subtype) 只有 \(distinct.count) 種顏色")
    }

    @Test func sameRecipeBakesTheSame() async throws {
        let baker = try SwirlBaker()
        let recipe = Self.recipe(.smoke)
        let palette = SwirlPalette.resolve(recipe, colors: Self.colors, reduceTransparency: false)
        let a = Self.pixels(try await baker.bake(recipe, colors: palette, side: 128).image).data
        let b = Self.pixels(try await baker.bake(recipe, colors: palette, side: 128).image).data
        #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
    }

    /// 花紋座標以盤半徑為單位：改解析度不改外觀（盤內平均色差 ≤ 0.02）
    @Test func resolutionDoesNotChangeTheLook() async throws {
        let baker = try SwirlBaker()
        let recipe = Self.recipe(.chunk)
        let palette = SwirlPalette.resolve(recipe, colors: Self.colors, reduceTransparency: false)
        let small = Self.meanRGB(Self.pixels(try await baker.bake(recipe, colors: palette, side: 256).image))
        let large = Self.meanRGB(Self.pixels(try await baker.bake(recipe, colors: palette, side: 512).image))
        #expect(abs(small.0 - large.0) <= 0.02 && abs(small.1 - large.1) <= 0.02 && abs(small.2 - large.2) <= 0.02)
    }

    /// 沒有 Metal 裝置＝建構失敗（呼叫端只畫底色）
    @Test func unavailableDeviceThrows() {
        #expect(throws: SwirlBaker.Failure.unavailable) { try SwirlBaker(device: nil) }
    }

    /// 邊長以位元組預算計：RGBA8＝4 B/px
    @Test func reportsByteCost() async throws {
        let baker = try SwirlBaker()
        let recipe = Self.recipe(.pull)
        let face = try await baker.bake(recipe, colors: SwirlPalette.resolve(recipe, colors: Self.colors, reduceTransparency: false), side: 64)
        #expect(face.byteCount == 64 * 64 * 4)
    }
}
