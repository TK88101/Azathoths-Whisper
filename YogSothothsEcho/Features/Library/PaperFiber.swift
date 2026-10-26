import CoreGraphics
import Foundation

/// 紙張紋理（#6-1 第二輪 F2 ⑤「中」、④毛邊，使用者 2026-10-22 定案；s6-61-round2.md §4 P1、附錄 D）：與小樣同一類雜訊（`Turbulence`＝feTurbulence）、
/// 同頻率與種子、同透明度公式，四邊無縫的平鋪圖，各只產生一次。小樣濾鏡在線性 RGB 運算，色票由線性轉回 sRGB
enum PaperFiber {
    /// 紙漿色 #EBE5D6（sRGB）
    static let pulp = (red: 0xEB / 255.0, green: 0xE5 / 255.0, blue: 0xD6 / 255.0)

    struct Layer {
        /// sRGB
        let color: (Double, Double, Double)
        let frequencyX: Double, frequencyY: Double
        let octaves: Int
        let seed: Int
        /// alpha＝clamp(gain × 通道 + bias)（小樣 feColorMatrix 第四列）
        let channel: Int, gain: Double, bias: Double
        let opacity: Double
    }

    static func sRGB(_ linear: Double) -> Double {
        linear <= 0.003_130_8 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    /// 小樣的線性 RGB 色票 → sRGB
    private static func fromLinear(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) { (sRGB(r), sRGB(g), sRGB(b)) }
    private static let white = (1.0, 1.0, 1.0)

    static let tileSide = 260
    static let haloSide = 128
    static let edgeLightSide = 180

    /// 紙纖維：A 深纖維、B 淺纖維、C 雜點、D 細噪（依序疊；值抄自小樣 FIB_DARK2／FIB_LIGHT2／SPECK／NOISE_DARK 與「中」的不透明度）
    static let layers: [Layer] = [
        Layer(color: fromLinear(0.12, 0.10, 0.08), frequencyX: 0.05, frequencyY: 1.1, octaves: 2, seed: 4, channel: 0, gain: 3.4, bias: -1.55, opacity: 0.13),
        Layer(color: fromLinear(0.96, 0.94, 0.88), frequencyX: 0.06, frequencyY: 1.3, octaves: 2, seed: 12, channel: 1, gain: 3.4, bias: -1.6, opacity: 0.11),
        Layer(color: fromLinear(0.10, 0.08, 0.06), frequencyX: 1.2, frequencyY: 1.2, octaves: 1, seed: 21, channel: 0, gain: 7, bias: -4.4, opacity: 0.22),
        Layer(color: fromLinear(0, 0, 0), frequencyX: 0.85, frequencyY: 0.85, octaves: 3, seed: 3, channel: 0, gain: 1.6, bias: -0.62, opacity: 0.06),
    ]
    /// 磨損毛邊：小樣 fuzz 濾鏡的纖維遮罩（1.4／0.5、2 octaves，alpha＝clamp(3A−1.45)），紙漿色、×0.9
    static let haloLayer = Layer(color: pulp, frequencyX: 1.4, frequencyY: 0.5, octaves: 2, seed: 10, channel: 3, gain: 3, bias: -1.45, opacity: 0.9)
    /// 細邊碎屑：小樣把 1.6 pt 細帶以位移貼圖（雜訊頻率 0.28、±4.5）打散成碎段，約 1/4 像素＝實心紙漿色；以同頻率雜訊門檻化模擬
    static let fleckLayer = Layer(color: pulp, frequencyX: 0.28, frequencyY: 0.28, octaves: 1, seed: 11, channel: 3, gain: 8, bias: -4.64, opacity: 1)
    /// 邊緣磨白的淺色雜點（小樣 NOISE_LIGHT：0.9、2 octaves、種子 9，白、alpha＝clamp(1.8R−0.9)）
    static let edgeLightLayer = Layer(color: white, frequencyX: 0.9, frequencyY: 0.9, octaves: 2, seed: 9, channel: 0, gain: 1.8, bias: -0.9, opacity: 1)

    static func alpha(of layer: Layer, side: Int) -> [Double] {
        Turbulence(seed: layer.seed)
            .fractalNoiseTile(channel: layer.channel, width: side, height: side, baseFrequencyX: layer.frequencyX,
                              baseFrequencyY: layer.frequencyY, octaves: layer.octaves)
            .map { min(1, max(0, layer.gain * $0 + layer.bias)) }
    }

    /// 各層依序 source-over 疊在透明底上（premultiplied RGBA8）
    static func bytes(_ layers: [Layer], side: Int) -> [UInt8] {
        let count = side * side
        var r = [Double](repeating: 0, count: count), g = r, b = r, a = r
        for layer in layers {
            let alpha = alpha(of: layer, side: side)
            for i in 0..<count {
                let s = alpha[i] * layer.opacity
                r[i] = layer.color.0 * s + r[i] * (1 - s)
                g[i] = layer.color.1 * s + g[i] * (1 - s)
                b[i] = layer.color.2 * s + b[i] * (1 - s)
                a[i] = s + a[i] * (1 - s)
            }
        }
        var out = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            out[i * 4] = UInt8((r[i] * 255).rounded()); out[i * 4 + 1] = UInt8((g[i] * 255).rounded())
            out[i * 4 + 2] = UInt8((b[i] * 255).rounded()); out[i * 4 + 3] = UInt8((a[i] * 255).rounded())
        }
        return out
    }

    static let tileImage = image(bytes(layers, side: tileSide), side: tileSide)
    static let haloImage = image(bytes([haloLayer], side: haloSide), side: haloSide)
    static let fleckImage = image(bytes([fleckLayer], side: haloSide), side: haloSide)
    static let edgeLightImage = image(bytes([edgeLightLayer], side: edgeLightSide), side: edgeLightSide)

    /// 首次用到時才產生的圖約百毫秒級：曲庫畫面出現時先在背景產生，免得第一次捲動卡在主執行緒
    static func prewarm() {
        _ = (tileImage, haloImage, fleckImage, edgeLightImage)
    }

    private static func image(_ bytes: [UInt8], side: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
