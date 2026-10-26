import CoreGraphics
import SwiftUI

/// F10 背景的純函式（附錄 E.3；與小樣 `s6-round2-overview.html` 的 CSS 同式，並以 Chrome 截圖取樣驗證）。
/// 座標一律是畫面（點）座標；顏色是 sRGB 0…1、source-over 疊色
enum BackgroundModel {
    /// 一個柔光色點：位置為擴張圖層的比例（0…1）
    struct ColorPoint: Equatable, Sendable {
        let x: Double
        let y: Double
        let light: RGBColor
        let dark: RGBColor

        func color(_ scheme: ColorScheme) -> RGBColor { scheme == .dark ? dark : light }
    }

    /// 擴張圖層：比畫面四邊各大 12%（小樣 `.bgl{inset:-12%}`）
    static let layerInset = 0.12
    /// 色點橢圓半徑（圖層寬高的比例）與柔光終點（CSS `ellipse 72% 80%`、`transparent 72%`）
    static let pointRadius = (x: 0.72, y: 0.80)
    static let pointFadeEnd = 0.72
    /// 最上層的黑：深色 0.10、淺色 0.035
    static func dimOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.10 : 0.035 }

    /// 取樣一次要算數百點：色點表只建一次
    private static let pointTable = Dictionary(uniqueKeysWithValues: BackgroundPreset.allCases.map { ($0, makePoints($0)) })

    static func points(_ preset: BackgroundPreset) -> [ColorPoint] { pointTable[preset] ?? [] }

    private static func makePoints(_ preset: BackgroundPreset) -> [ColorPoint] {
        func p(_ x: Double, _ y: Double, _ light: UInt32, _ dark: UInt32) -> ColorPoint {
            ColorPoint(x: x / 100, y: y / 100, light: RGBColor(hex: light), dark: RGBColor(hex: dark))
        }
        return switch preset {
        case .moss: [p(84, 10, 0xD7CE45, 0x7D7927), p(18, 45, 0x8B9B75, 0x26382D), p(53, 97, 0xED9A67, 0x9E4D34)]
        case .aurora: [p(93, 8, 0x55C97B, 0x278653), p(62, 87, 0x22AFC2, 0x087693), p(4, 36, 0x2D396D, 0x171D3E)]
        case .indigo: [p(7, 17, 0x405AAA, 0x1C285D), p(78, 62, 0x48B8BB, 0x176C73), p(48, 100, 0x70B9DC, 0x29627F)]
        case .forest: [p(7, 20, 0x416B63, 0x1C3935), p(89, 19, 0x8DBF8E, 0x476D4B), p(58, 96, 0x6B93BD, 0x31536F)]
        case .roseGraphite: [p(10, 18, 0x4E485B, 0x292633), p(88, 28, 0xC9828D, 0x794650), p(61, 93, 0xB9A1A2, 0x645359)]
        case .terracotta: [p(12, 8, 0x573A4A, 0x30212B), p(88, 38, 0xC77555, 0x7F3F32), p(43, 98, 0x9F745F, 0x5D463B)]
        case .silverBlue: [p(10, 12, 0x78879F, 0x354052), p(88, 20, 0xC3CCD0, 0x68737C), p(55, 96, 0x7BA9B8, 0x3C697A)]
        }
    }

    /// 底色＝該主題下亮度最低的色點
    static func baseColor(preset: BackgroundPreset, scheme: ColorScheme) -> RGBColor {
        points(preset).map { $0.color(scheme) }.min { $0.luminance < $1.luminance } ?? .black
    }

    /// 擴張圖層的框（畫面座標）
    static func layerFrame(in size: CGSize) -> CGRect {
        CGRect(x: -layerInset * size.width, y: -layerInset * size.height,
               width: (1 + 2 * layerInset) * size.width, height: (1 + 2 * layerInset) * size.height)
    }

    /// 某點的漸層色（不含倒影、陰影帶、壓暗）：底色上由陣列最後一點先疊、第一點最後疊（CSS 第一層在最上），最後疊黑
    static func presetColor(preset: BackgroundPreset, scheme: ColorScheme, at point: CGPoint, in size: CGSize) -> RGBColor {
        let layer = layerFrame(in: size)
        var color = baseColor(preset: preset, scheme: scheme)
        for spot in points(preset).reversed() {
            let dx = (point.x - layer.minX - spot.x * layer.width) / (pointRadius.x * layer.width)
            let dy = (point.y - layer.minY - spot.y * layer.height) / (pointRadius.y * layer.height)
            let alpha = max(0, 1 - (dx * dx + dy * dy).squareRoot() / pointFadeEnd)
            color = color.over(spot.color(scheme), alpha: alpha)
        }
        return color.over(.black, alpha: dimOpacity(scheme))
    }

    /// 四周壓暗（小樣 `radial-gradient(closest-side at 50% 48%, transparent 45%, rgba(0,0,0,.6) 140%)`）
    static let vignetteCenter = (x: 0.5, y: 0.48)
    static let vignetteStops = (clear: 0.45, full: 1.40)
    static let vignetteOpacity = 0.6

    static func vignetteRadii(in size: CGSize) -> (x: CGFloat, y: CGFloat) {
        let cx = vignetteCenter.x * size.width, cy = vignetteCenter.y * size.height
        return (min(cx, size.width - cx), min(cy, size.height - cy))
    }

    static func vignetteAlpha(at point: CGPoint, in size: CGSize) -> Double {
        let radii = vignetteRadii(in: size)
        let dx = (point.x - vignetteCenter.x * size.width) / radii.x, dy = (point.y - vignetteCenter.y * size.height) / radii.y
        let d = (dx * dx + dy * dy).squareRoot()
        return vignetteOpacity * min(1, max(0, (d - vignetteStops.clear) / (vignetteStops.full - vignetteStops.clear)))
    }

    /// 倒影遮罩（小樣 `-webkit-box-reflect` 的 `linear-gradient(transparent 62%, rgba(255,255,255,.22) 84%, rgba(255,255,255,0) 100%)`）：
    /// q＝原圖座標下的高度比例（遮罩隨內容翻轉）
    static let reflectionStops = (start: 0.62, peak: 0.84, peakAlpha: 0.22)

    static func reflectionAlpha(q: Double) -> Double {
        let s = reflectionStops
        if q < s.start || q > 1 { return 0 }
        if q <= s.peak { return s.peakAlpha * (q - s.start) / (s.peak - s.start) }
        return s.peakAlpha * (1 - q) / (1 - s.peak)
    }

    /// 螢幕點 y 的倒影來自原圖 2y₀−y（y₀＝地面線）
    static func reflectionSourceFraction(y: CGFloat, floor: CGFloat, height: CGFloat) -> Double {
        Double((2 * floor - y) / height)
    }
}
