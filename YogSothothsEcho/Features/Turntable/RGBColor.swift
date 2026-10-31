import Foundation

/// 唱片取色用的純值顏色（sRGB，0…1）；轉 SwiftUI.Color 在視圖層做
struct RGBColor: Equatable, Hashable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    /// 相對亮度（sRGB 線性化；同 Compose `Color.luminance()`）
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// 彩度（max−min）：黑主色判定與取色調查共用
    var chroma: Double { max(r, g, b) - min(r, g, b) }

    /// HSB（色相 0…360°、飽和與明度 0…1；同 SwiftUI `Color(hue:saturation:brightness:)`）：曲庫佔位色用
    init(hue: Double, saturation s: Double, brightness v: Double) {
        let h = hue.truncatingRemainder(dividingBy: 360) / 60, c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        self.init(r: r + m, g: g + m, b: b + m)
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(r: Double(hex >> 16 & 0xFF) / 255, g: Double(hex >> 8 & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    static let white = RGBColor(r: 1, g: 1, b: 1)
    static let black = RGBColor(r: 0, g: 0, b: 0)
}

extension RGBColor {
    /// CSS hsl()：色相度、飽和與亮度 0–100
    init(hue: Double, saturation: Double, lightness: Double) {
        let s = saturation / 100, l = lightness / 100
        let a = s * min(l, 1 - l)
        func f(_ n: Double) -> Double {
            let k = (n + hue / 30).truncatingRemainder(dividingBy: 12)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        self.init(r: f(0), g: f(8), b: f(4))
    }

    /// 色相度 [0, 360)、飽和與亮度 0–100（CSS hsl 的反函數）
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(r, g, b), low = min(r, g, b), l = (high + low) / 2
        guard high > low else { return (0, 0, l * 100) }
        let d = high - low
        let s = d / (1 - abs(2 * l - 1))
        let raw: Double = switch high {
        case r: 60 * ((g - b) / d)
        case g: 60 * ((b - r) / d + 2)
        default: 60 * ((r - g) / d + 4)
        }
        let hue = (raw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return (hue, s * 100, l * 100)
    }
}

extension RGBColor {
    /// 正規化 HSL：色相度、飽和與亮度 0…1（SWIRL 配色用；既有 `hsl` 是百分比，不改）
    var hslUnit: (hue: Double, saturation: Double, lightness: Double) {
        let v = hsl
        return (v.hue, v.saturation / 100, v.lightness / 100)
    }

    /// 正規化 HSL 建色；飽和與亮度先夾到 0…1
    init(hueDegrees: Double, saturationUnit: Double, lightnessUnit: Double) {
        self.init(hue: hueDegrees, saturation: min(max(saturationUnit, 0), 1) * 100, lightness: min(max(lightnessUnit, 0), 1) * 100)
    }

    /// 量化到 8 bit（與配色小樣的整數運算一致）
    var quantized8: RGBColor {
        RGBColor(r: (r * 255).rounded() / 255, g: (g * 255).rounded() / 255, b: (b * 255).rounded() / 255)
    }
}

extension RGBColor {
    /// source-over：把 `top` 以 `alpha` 疊在自己上面
    func over(_ top: RGBColor, alpha: Double) -> RGBColor {
        RGBColor(r: top.r * alpha + r * (1 - alpha), g: top.g * alpha + g * (1 - alpha), b: top.b * alpha + b * (1 - alpha))
    }
}

/// 封面取色結果（spec「颜色取自封面主色」）：P＝主色、T＝P 上的文字色（只會是純白或純黑）、S＝柔和色
struct AlbumColors: Equatable {
    let primary: RGBColor
    let text: RGBColor
    let secondary: RGBColor
    /// `secondary` 是否真的取自封面（Palette 找到 MUTED）；否＝回退值 #46403C（v2.1 T9：磨砂盤不拿回退值當封面色）
    let hasMuted: Bool
    /// 封面上最多的鮮豔色相（v2.1 T11：黑主色的 TRANSPARENT 用；MUTED 會排除血紅這類高飽和色）
    let vivid: RGBColor?

    init(primary: RGBColor, text: RGBColor, secondary: RGBColor, hasMuted: Bool = true, vivid: RGBColor? = nil) {
        self.primary = primary
        self.text = text
        self.secondary = secondary
        self.hasMuted = hasMuted
        self.vivid = vivid
    }

    /// 沒有封面時：BLUR 主題的回退值（D6）
    static let fallback = AlbumColors(primary: RGBColor(hex: 0x1E1D1D), text: RGBColor(hex: 0x747474),
                                      secondary: RGBColor(hex: 0x46403C), hasMuted: false)
}
