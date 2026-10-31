import Foundation
import Testing

@testable import YogSothothsEcho

private final class SwirlPaletteBundleToken {}

// CR-037 T3（yse-swirl-style.md §4.3）：配色決策表。golden＝小樣 swirl-color-preview.html 以同一規則（JS）算出的
// 13 組代表色 × 7 欄（Tests/Fixtures/swirl-palette-fixtures-v2.json；v0.8 深／淺墨改調底色，含 FOB《Folie à Deux》實測色）；
// Swift 與 JS 逐分量差 ≤ 1/255
struct SwirlPaletteTests {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            let name: String
            let P: [Int]
            let V: [Int]?
            let S: [Int]?
            let hasMuted: Bool
            let results: [Result]
        }

        struct Result: Decodable {
            let subtype: String
            let inkMode: String?
            let base: [Int]?
            let gradient: [[Int]]?
            let ink: [Int]
            let accent: [Int]?
            let accentFallback: String?
        }

        let schema: String
        let cases: [Case]
    }

    private static func load() throws -> Fixture {
        let url = try #require(Bundle(for: SwirlPaletteBundleToken.self).url(forResource: "swirl-palette-fixtures-v2", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private static func rgb(_ v: [Int]) -> RGBColor { RGBColor(r: Double(v[0]) / 255, g: Double(v[1]) / 255, b: Double(v[2]) / 255) }

    private static func near(_ a: RGBColor, _ b: [Int]) -> Bool {
        let e = rgb(b)
        return abs(a.r - e.r) <= 1.0 / 255 + 1e-9 && abs(a.g - e.g) <= 1.0 / 255 + 1e-9 && abs(a.b - e.b) <= 1.0 / 255 + 1e-9
    }

    private static func recipe(_ result: Fixture.Result) -> SwirlRecipe {
        let subtype: SwirlSubtype = switch result.subtype {
        case "smokeWater": .smokeWater
        case "smoke": .smoke
        case "pull": .pull
        case "flake": .flake
        default: .chunk
        }
        let ink: SmokeInk? = switch result.inkMode {
        case "dark": .dark
        case "light": .light
        case "accent": .accent
        default: nil
        }
        return SwirlRecipe(subtype: subtype, ink: ink, noiseSeed: 1, body: 0.3, opacity: 0.9)
    }

    @Test func matchesPreviewFixtures() throws {
        let fixture = try Self.load()
        #expect(fixture.schema == "swirl-palette-fixtures-v2" && fixture.cases.count == 13)
        for c in fixture.cases {
            let primary = Self.rgb(c.P)
            let colors = AlbumColors(primary: primary, text: AlbumPalette.textColor(on: primary),
                                     secondary: c.S.map(Self.rgb) ?? AlbumColors.fallback.secondary, hasMuted: c.hasMuted,
                                     vivid: c.V.map(Self.rgb))
            for r in c.results {
                let label = "\(c.name) \(r.subtype) \(r.inkMode ?? "-")"
                let out = SwirlPalette.resolve(Self.recipe(r), colors: colors, reduceTransparency: false)
                switch out.base {
                case .solid(let base):
                    let expected = try #require(r.base, "\(label) 期望漸變")
                    #expect(Self.near(base, expected), "\(label) base \(base)")
                case .gradient(let from, let to):
                    let expected = try #require(r.gradient, "\(label) 期望單色")
                    #expect(Self.near(from, expected[0]) && Self.near(to, expected[1]), "\(label) gradient")
                }
                #expect(Self.near(out.ink, r.ink), "\(label) ink \(out.ink)")
                if let accent = r.accent {
                    #expect(out.accent.map { Self.near($0, accent) } == true, "\(label) accent")
                } else {
                    #expect(out.accent == nil, "\(label) accent")
                }
                let fallback: SmokeInk? = switch r.accentFallback {
                case "dark": .dark
                case "light": .light
                default: nil
                }
                #expect(out.accentFallback == fallback, "\(label) fallback")
            }
        }
    }

    /// v0.8（使用者實機：FOB《Folie à Deux》深墨＝淺墨）：暗底上深墨對比不足時提亮底色、墨色不換——深墨與淺墨一定不同
    @Test func darkAndLightInkStayDistinctOnDarkCovers() {
        for hex: UInt32 in [0x5B1B19, 0x191818, 0x14285A] {
            let p = RGBColor(hex: hex)
            let colors = AlbumColors(primary: p, text: .white, secondary: p, hasMuted: false)
            let dark = SwirlPalette.resolve(SwirlRecipe(subtype: .smoke, ink: .dark, noiseSeed: 1, body: 0.3, opacity: 1), colors: colors, reduceTransparency: false)
            let light = SwirlPalette.resolve(SwirlRecipe(subtype: .smoke, ink: .light, noiseSeed: 1, body: 0.3, opacity: 1), colors: colors, reduceTransparency: false)
            #expect(dark.ink.luminance < light.ink.luminance, "\(hex)")
            guard case .solid(let darkBase) = dark.base, case .solid(let lightBase) = light.base else { Issue.record("solid"); continue }
            #expect(AlbumPalette.contrast(dark.ink, darkBase) >= 2 && AlbumPalette.contrast(light.ink, lightBase) >= 2, "\(hex)")
        }
    }

    /// Reduce Transparency：不論配方都不透明
    @Test func reduceTransparencyMakesOpaque() {
        let colors = AlbumColors(primary: RGBColor(hex: 0x960E1C), text: .white, secondary: RGBColor(hex: 0x786A60))
        let recipe = SwirlRecipe(subtype: .smoke, ink: .dark, noiseSeed: 1, body: 0.3, opacity: 0.9)
        #expect(SwirlPalette.resolve(recipe, colors: colors, reduceTransparency: false).opacity == 0.9)
        #expect(SwirlPalette.resolve(recipe, colors: colors, reduceTransparency: true).opacity == 1)
    }

    /// 強調色：沒有 MUTED（hasMuted 假）時不拿回退輔色當強調色；V 也沒有＝退回並註記
    @Test func accentIgnoresFallbackSecondary() {
        let colors = AlbumColors(primary: RGBColor(hex: 0x1E8C8C), text: .white, secondary: RGBColor(hex: 0xDC5078), hasMuted: false, vivid: nil)
        let recipe = SwirlRecipe(subtype: .smoke, ink: .accent, noiseSeed: 1, body: 0.3, opacity: 1)
        #expect(SwirlPalette.resolve(recipe, colors: colors, reduceTransparency: false).accentFallback != nil)
    }

    /// 拉絲：底很淺時纖維改往黑混（白纖維在白底上看不見）
    @Test func pullOnWhiteUsesDarkFibers() {
        let white = RGBColor(hex: 0xF0EEE8)
        let out = SwirlPalette.resolve(SwirlRecipe(subtype: .pull, ink: nil, noiseSeed: 1, body: 0.4, opacity: 1),
                                       colors: AlbumColors(primary: white, text: .black, secondary: white), reduceTransparency: false)
        #expect(out.ink.luminance < white.luminance)
    }

    /// 正規化 HSL（0…1）與既有百分比 API 一致
    @Test func unitHSLRoundTrip() {
        let c = RGBColor(hex: 0xB45AC8)
        #expect(abs(c.hslUnit.saturation * 100 - c.hsl.saturation) < 1e-9 && abs(c.hslUnit.lightness * 100 - c.hsl.lightness) < 1e-9)
        let back = RGBColor(hueDegrees: c.hslUnit.hue, saturationUnit: c.hslUnit.saturation, lightnessUnit: c.hslUnit.lightness)
        #expect(abs(back.r - c.r) < 1e-9 && abs(back.g - c.g) < 1e-9 && abs(back.b - c.b) < 1e-9)
    }
}
