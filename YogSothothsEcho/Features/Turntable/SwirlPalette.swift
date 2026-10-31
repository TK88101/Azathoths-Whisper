import Foundation

/// SWIRL 系列的盤面配色（CR-037；yse-swirl-style.md §4.3 決策表）
struct SwirlColors: Equatable {
    enum Base: Equatable {
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
    static let nearBlackBase = RGBColor(r: 222 / 255, g: 225 / 255, b: 232 / 255)
    static let nearBlackInk = RGBColor(r: 18 / 255, g: 18 / 255, b: 20 / 255)
    static let flakeInk = RGBColor(r: 252 / 255, g: 253 / 255, b: 1)
    static let achromaticFlakeBase = RGBColor(r: 216 / 255, g: 216 / 255, b: 220 / 255)
    static let achromaticDark = RGBColor(r: 58 / 255, g: 58 / 255, b: 62 / 255)
    static let achromaticChunkGradient = (RGBColor(r: 122 / 255, g: 122 / 255, b: 126 / 255), RGBColor(r: 160 / 255, g: 160 / 255, b: 164 / 255))
    static let chunkVein = RGBColor(r: 240 / 255, g: 243 / 255, b: 252 / 255)

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
            if TransparentFinish.isNearBlack(p) { return solid(nearBlackBase, ink: nearBlackInk, opacity: opacity) }
            return solid(p, ink: dark(p), opacity: opacity)
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
                return SwirlColors(base: .gradient(achromaticChunkGradient.0, achromaticChunkGradient.1), ink: achromaticDark,
                                   accent: chunkVein, accentFallback: nil, opacity: opacity)
            }
            return SwirlColors(base: .gradient(hslColor(hsl.hue, 0.18, 0.52), hslColor(hsl.hue, 0.18, 0.66)),
                               ink: hslColor(hsl.hue, max(hsl.saturation, 0.7), 0.46), accent: chunkVein, accentFallback: nil, opacity: opacity)
        }
    }

    /// 煙渦：主色近黑＝301 灰底黑渦；否則依取向取墨色，對比不足退回深／淺端中對比較高者
    private static func smoke(_ p: RGBColor, ink: SmokeInk, colors: AlbumColors, opacity: Double) -> SwirlColors {
        if TransparentFinish.isNearBlack(p) { return solid(nearBlackBase, ink: nearBlackInk, opacity: opacity) }
        let darkInk = dark(p), lightInk = light(p)
        let chosen: RGBColor? = switch ink {
        case .dark: darkInk
        case .light: lightInk
        case .accent: accent(for: p, colors: colors)
        }
        if let chosen, AlbumPalette.contrast(chosen, p) >= inkContrast { return solid(p, ink: chosen, opacity: opacity) }
        // 平手時取深端（小樣以穩定排序保留 dark 在前）
        let useLight = AlbumPalette.contrast(lightInk, p) > AlbumPalette.contrast(darkInk, p)
        return SwirlColors(base: .solid(p), ink: useLight ? lightInk : darkInk, accent: nil,
                           accentFallback: ink == .accent ? (useLight ? .light : .dark) : nil, opacity: opacity)
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

    private static func dark(_ c: RGBColor) -> RGBColor { let h = c.hslUnit; return hslColor(h.hue, h.saturation, 0.08) }
    private static func light(_ c: RGBColor) -> RGBColor { let h = c.hslUnit; return hslColor(h.hue, h.saturation * 0.3, 0.94) }

    private static func hslColor(_ hue: Double, _ saturation: Double, _ lightness: Double) -> RGBColor {
        RGBColor(hueDegrees: hue, saturationUnit: saturation, lightnessUnit: lightness).quantized8
    }

    private static func mix(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
        RGBColor(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t).quantized8
    }

    private static func hueDistance(_ a: RGBColor, _ b: RGBColor) -> Double {
        let d = abs(a.hslUnit.hue - b.hslUnit.hue)
        return min(d, 360 - d)
    }

    private static func solid(_ base: RGBColor, ink: RGBColor, opacity: Double) -> SwirlColors {
        SwirlColors(base: .solid(base), ink: ink, accent: nil, accentFallback: nil, opacity: opacity)
    }
}
