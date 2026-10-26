import CoreGraphics
import SwiftUI
import Testing
@testable import YogSothothsEcho

// F10 T2b（附錄 E.3）：側封漸層、四周壓暗、倒影遮罩的純函式
struct BackgroundModelTests {
    private static func hex(_ value: UInt32) -> RGBColor { RGBColor(hex: value) }

    /// 小樣 PRESETS（保留 1、2、4、6、7、9、10）：位置 %、淺色、深色
    static let expectedPoints: [BackgroundPreset: [(x: Double, y: Double, light: UInt32, dark: UInt32)]] = [
        .moss: [(84, 10, 0xD7CE45, 0x7D7927), (18, 45, 0x8B9B75, 0x26382D), (53, 97, 0xED9A67, 0x9E4D34)],
        .aurora: [(93, 8, 0x55C97B, 0x278653), (62, 87, 0x22AFC2, 0x087693), (4, 36, 0x2D396D, 0x171D3E)],
        .indigo: [(7, 17, 0x405AAA, 0x1C285D), (78, 62, 0x48B8BB, 0x176C73), (48, 100, 0x70B9DC, 0x29627F)],
        .forest: [(7, 20, 0x416B63, 0x1C3935), (89, 19, 0x8DBF8E, 0x476D4B), (58, 96, 0x6B93BD, 0x31536F)],
        .roseGraphite: [(10, 18, 0x4E485B, 0x292633), (88, 28, 0xC9828D, 0x794650), (61, 93, 0xB9A1A2, 0x645359)],
        .terracotta: [(12, 8, 0x573A4A, 0x30212B), (88, 38, 0xC77555, 0x7F3F32), (43, 98, 0x9F745F, 0x5D463B)],
        .silverBlue: [(10, 12, 0x78879F, 0x354052), (88, 20, 0xC3CCD0, 0x68737C), (55, 96, 0x7BA9B8, 0x3C697A)],
    ]

    @Test(arguments: BackgroundPreset.allCases, [ColorScheme.dark, .light])
    func colorPointsMatchThePreview(preset: BackgroundPreset, scheme: ColorScheme) throws {
        let expected = try #require(Self.expectedPoints[preset])
        let points = BackgroundModel.points(preset)
        #expect(points.count == expected.count)
        for (point, want) in zip(points, expected) {
            #expect(abs(point.x - want.x / 100) < 1e-9 && abs(point.y - want.y / 100) < 1e-9)
            #expect(point.color(scheme) == Self.hex(scheme == .dark ? want.dark : want.light))
        }
    }

    /// 與小樣在 Chrome 截圖的取樣比（獨立於公式）：各通道差 ≤ 3/255
    @Test(arguments: BackgroundPreset.allCases, [ColorScheme.dark, .light])
    func presetColorMatchesChromeSamples(preset: BackgroundPreset, scheme: ColorScheme) throws {
        let samples = try #require(PresetSamples.values["\(preset.rawValue).\(scheme == .dark ? "dark" : "light")"])
        for (point, want) in zip(PresetSamples.points, samples) {
            let got = BackgroundModel.presetColor(preset: preset, scheme: scheme, at: point, in: PresetSamples.canvas)
            let channels = [got.r, got.g, got.b].map { Int(($0 * 255).rounded()) }
            for (g, w) in zip(channels, want) {
                #expect(abs(g - w) <= 3, "\(preset) \(scheme) \(point)：\(channels) vs \(want)")
            }
        }
    }

    @Test func baseColorIsTheDarkestPoint() {
        #expect(BackgroundModel.baseColor(preset: .silverBlue, scheme: .dark) == Self.hex(0x354052))
        #expect(BackgroundModel.baseColor(preset: .aurora, scheme: .light) == Self.hex(0x2D396D))
    }

    @Test func vignetteFollowsThePreviewCSS() {
        let size = CGSize(width: 1376, height: 1032)
        #expect(BackgroundModel.vignetteAlpha(at: CGPoint(x: 688, y: 0.48 * 1032), in: size) == 0)
        #expect(abs(BackgroundModel.vignetteAlpha(at: CGPoint(x: 0, y: 0.48 * 1032), in: size) - 0.347) < 0.01)
        #expect(abs(BackgroundModel.vignetteAlpha(at: .zero, in: size) - 0.6) < 0.01)
        #expect(abs(BackgroundModel.vignetteAlpha(at: CGPoint(x: 1376, y: 1032), in: size) - 0.6) < 0.01)
    }

    @Test func reflectionMaskFollowsBoxReflectStops() {
        #expect(BackgroundModel.reflectionAlpha(q: 0.5) == 0)
        #expect(BackgroundModel.reflectionAlpha(q: 0.62) == 0)
        #expect(abs(BackgroundModel.reflectionAlpha(q: 0.73) - 0.11) < 1e-9)
        #expect(abs(BackgroundModel.reflectionAlpha(q: 0.84) - 0.22) < 1e-9)
        #expect(abs(BackgroundModel.reflectionAlpha(q: 0.92) - 0.11) < 1e-9)
        #expect(BackgroundModel.reflectionAlpha(q: 1) == 0)
        #expect(BackgroundModel.reflectionAlpha(q: 1.3) == 0)
    }

    /// 螢幕點 y 的倒影來自原圖 2y₀−y：q＝(2y₀−y)/H
    @Test func reflectionSourceFractionMirrorsAboutTheFloorLine() {
        #expect(abs(BackgroundModel.reflectionSourceFraction(y: 900, floor: 800, height: 1000) - 0.7) < 1e-9)
        #expect(abs(BackgroundModel.reflectionSourceFraction(y: 800, floor: 800, height: 1000) - 0.8) < 1e-9)
    }
}
