import Foundation

/// SWIRL 系列的盤面配色（CR-037；yse-swirl-style.md §4.3 決策表）
struct SwirlColors: Hashable {
    enum Base: Hashable {
        case solid(RGBColor)
        /// 斜向（左上→右下）漸變，隨盤轉
        case gradient(RGBColor, RGBColor)
    }

    let base: Base
    let ink: RGBColor
    let accent: RGBColor?
    /// 手選「強調色」但封面沒有合適強調色時，這首歌實際用的墨色（第二排註記）
    let accentFallback: SmokeInk?
    let opacity: Double
}

/// 決策表的唯一實作。所有中間色都量化到 8 bit，與使用者看過的小樣 v14（JS 整數運算）一致——golden 見
/// Tests/Fixtures/swirl-palette-fixtures-v1.json
enum SwirlPalette {
    static let nearBlackBase = RGBColor(hex: 0xDEE1E8)
    static let nearBlackInk = RGBColor(hex: 0x121214)
    static let flakeInk = RGBColor(hex: 0xFCFDFF)
    static let achromaticFlakeBase = RGBColor(hex: 0xD8D8DC)
    static let achromaticDark = RGBColor(hex: 0x3A3A3E)
    static let achromaticChunkFrom = RGBColor(hex: 0x7A7A7E)
    static let achromaticChunkTo = RGBColor(hex: 0xA0A0A4)
    static let chunkVein = RGBColor(hex: 0xF0F3FC)

    static let inkContrast = 2.0
    static let fiberContrast = 1.3
    static let accentMinimumChroma = 0.15
    static let accentMinimumHueDistance = 30.0
    static let achromaticChroma = 0.1

    static func resolve(_ recipe: SwirlRecipe, colors: AlbumColors, reduceTransparency: Bool) -> SwirlColors {
        let p = colors.primary.quantized8
        let opacity = reduceTransparency ? 1 : recipe.opacity
        switch recipe.subtype {
        case .smokeWater:
            return nearBlackSmoke(p, opacity: opacity) ?? solid(p, ink: dark(p), opacity: opacity)
        case .smoke:
            return smoke(p, ink: recipe.ink ?? .dark, colors: colors, opacity: opacity)
        case .pull:
            let fiber = mix(p, .white, 0.6)
            return solid(p, ink: AlbumPalette.contrast(fiber, p) < fiberContrast ? mix(p, .black, 0.35) : fiber, opacity: opacity)
        case .flake:
            let hsl = p.hslUnit
            let achromatic = p.chroma < achromaticChroma
            let base = achromatic ? achromaticFlakeBase : hslColor(hsl.hue, hsl.saturation, max(hsl.lightness, 0.72))
            let vein = achromatic ? achromaticDark : hslColor(hsl.hue, max(hsl.saturation, 0.6), 0.45)
            return SwirlColors(base: .solid(base), ink: flakeInk, accent: vein, accentFallback: nil, opacity: opacity)
        case .chunk:
            let source = (colors.vivid ?? colors.primary).quantized8
            let hsl = source.hslUnit
            guard source.chroma >= achromaticChroma else {
                return SwirlColors(base: .gradient(achromaticChunkFrom, achromaticChunkTo), ink: achromaticDark,
                                   accent: chunkVein, accentFallback: nil, opacity: opacity)
            }
            return SwirlColors(base: .gradient(hslColor(hsl.hue, 0.18, 0.52), hslColor(hsl.hue, 0.18, 0.66)),
                               ink: hslColor(hsl.hue, max(hsl.saturation, 0.7), 0.46), accent: chunkVein, accentFallback: nil, opacity: opacity)
        }
    }

    /// 煙渦（v0.8）：深墨／淺墨的墨色固定，對比不足時把底色往反方向調明度（同色相）——兩者一定不同；
    /// 強調色不足時退回深／淺端中對比較高者並註記。近黑不特例（301 外觀只留給水感）
    private static func smoke(_ p: RGBColor, ink: SmokeInk, colors: AlbumColors, opacity: Double) -> SwirlColors {
        let darkInk = dark(p), lightInk = light(p)
        switch ink {
        case .dark: return solid(base(p, legibleUnder: darkInk, lighten: true), ink: darkInk, opacity: opacity)
        case .light: return solid(base(p, legibleUnder: lightInk, lighten: false), ink: lightInk, opacity: opacity)
        case .accent:
            if let accent = accent(for: p, colors: colors), AlbumPalette.contrast(accent, p) >= inkContrast {
                return solid(p, ink: accent, opacity: opacity)
            }
            // 平手時取深端（小樣以穩定排序保留 dark 在前）
            let useLight = AlbumPalette.contrast(lightInk, p) > AlbumPalette.contrast(darkInk, p)
            let fallback = useLight ? lightInk : darkInk
            return SwirlColors(base: .solid(base(p, legibleUnder: fallback, lighten: !useLight)), ink: fallback, accent: nil,
                               accentFallback: useLight ? .light : .dark, opacity: opacity)
        }
    }

    /// 墨色在主色上對比夠＝主色；否則同色相每次調 0.02 明度直到對比 ≥ 2（最多 60 步、夾在 0.04…0.92）
    private static func base(_ p: RGBColor, legibleUnder ink: RGBColor, lighten: Bool) -> RGBColor {
        guard AlbumPalette.contrast(ink, p) < inkContrast else { return p }
        let hsl = p.hslUnit
        var lightness = hsl.lightness
        for _ in 0..<60 where AlbumPalette.contrast(ink, hslColor(hsl.hue, hsl.saturation, lightness)) < inkContrast {
            lightness += lighten ? 0.02 : -0.02
            if lightness > 0.92 || lightness < 0.04 { break }
        }
        return hslColor(hsl.hue, hsl.saturation, min(0.92, max(0.04, lightness)))
    }

    /// 強調色候選：V → S（只在真的取自封面時），彩度與色相距都要夠；對比不足先把明度推開再交給呼叫端判斷
    private static func accent(for p: RGBColor, colors: AlbumColors) -> RGBColor? {
        let candidates = [colors.vivid, colors.hasMuted ? colors.secondary : nil].compactMap { $0?.quantized8 }
        guard let found = candidates.first(where: { $0.chroma >= accentMinimumChroma && hueDistance($0, p) >= accentMinimumHueDistance }) else {
            return nil
        }
        guard AlbumPalette.contrast(found, p) < inkContrast else { return found }
        let hsl = found.hslUnit
        return hslColor(hsl.hue, hsl.saturation, p.luminance >= 0.18 ? 0.25 : 0.85)
    }

    /// 主色近黑的水感＝301 外觀（灰底黑渦）
    private static func nearBlackSmoke(_ p: RGBColor, opacity: Double) -> SwirlColors? {
        TransparentFinish.isNearBlack(p) ? solid(nearBlackBase, ink: nearBlackInk, opacity: opacity) : nil
    }

    private static func dark(_ c: RGBColor) -> RGBColor { let h = c.hslUnit; return hslColor(h.hue, h.saturation, 0.08) }
    private static func light(_ c: RGBColor) -> RGBColor { let h = c.hslUnit; return hslColor(h.hue, h.saturation * 0.3, 0.94) }

    private static func hslColor(_ hue: Double, _ saturation: Double, _ lightness: Double) -> RGBColor {
        RGBColor(hueDegrees: hue, saturationUnit: saturation, lightnessUnit: lightness).quantized8
    }

    private static func mix(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
        a.over(b, alpha: t).quantized8
    }

    private static func hueDistance(_ a: RGBColor, _ b: RGBColor) -> Double {
        let d = abs(a.hslUnit.hue - b.hslUnit.hue)
        return min(d, 360 - d)
    }

    private static func solid(_ base: RGBColor, ink: RGBColor, opacity: Double) -> SwirlColors {
        SwirlColors(base: .solid(base), ink: ink, accent: nil, accentFallback: nil, opacity: opacity)
    }
}
