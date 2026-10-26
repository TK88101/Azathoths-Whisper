import Observation
import SwiftUI
import UIKit

/// 詳情頁字色（附錄 E.4，不加墊層）：深底白字、淺底深字 #16130F
enum DetailInk: Equatable, Sendable {
    case white, dark

    static let darkInk = RGBColor(hex: 0x16130F)

    var color: Color { self == .white ? .white : Self.darkInk.color }

    /// 次要文字（藝人、序號、時長）：平常 0.6；系統「增加對比」時不透明（E.5）
    func secondaryOpacity(increasedContrast: Bool) -> Double { increasedContrast ? 1 : 0.6 }
}

/// F10 詳情背景的純函式（附錄 E.4；與小樣 `bgColorAt` 同式）
enum DetailBackgroundModel {
    static let saturationRange = 18.0...48.0
    /// 唱機式模糊上的黑（同 `TurntableBackground.dimOpacity`）
    static let blurDim = TurntableBackground.dimOpacity
    /// 字色門檻：交叉點 0.194（白／#16130F 對比相等）±0.02 遲滯
    static let inkCrossover = 0.194
    static let inkWhiteAtOrBelow = 0.174
    static let inkDarkAtOrAbove = 0.214
    /// 封面投影：背景亮度 ≤0.16 → 0.675、≥0.30 → 0.25，之間線性
    static let shadowLuminance = (dark: 0.16, light: 0.30)
    static let shadowOpacity = (dark: 0.675, light: 0.25)
    static let samplesPerSide = 12

    static func clampedSaturation(of color: RGBColor) -> Double {
        min(saturationRange.upperBound, max(saturationRange.lowerBound, color.hsl.saturation))
    }

    /// 145° 線性底的兩端：c2（起點）→ c1（終點）
    static func albumColorStops(primary: RGBColor, scheme: ColorScheme) -> (c1: RGBColor, c2: RGBColor) {
        let h = primary.hsl.hue, s = clampedSaturation(of: primary)
        return scheme == .dark
            ? (RGBColor(hue: h, saturation: s, lightness: 22), RGBColor(hue: h, saturation: s, lightness: 32))
            : (RGBColor(hue: h, saturation: min(s, 40), lightness: 80), RGBColor(hue: h, saturation: min(s + 8, 50), lightness: 88))
    }

    /// 右上 (75%, 12%) 同色柔光：橢圓 85%×90%，0→72% 透明
    static func albumGlow(primary: RGBColor, scheme: ColorScheme) -> (color: RGBColor, alpha: Double) {
        let h = primary.hsl.hue, s = clampedSaturation(of: primary)
        return scheme == .dark ? (RGBColor(hue: h, saturation: min(s + 10, 58), lightness: 46), 0.55)
                               : (RGBColor(hue: h, saturation: s, lightness: 96), 0.8)
    }

    static let albumGradientDegrees = 145.0
    static let glowCenter = (x: 0.75, y: 0.12)
    static let glowRadius = (x: 0.85, y: 0.90)

    /// CSS 角度漸層的軸：方向（0° 朝上、順時針）與長度＝|W·sinθ|＋|H·cosθ|（漸層線過中心）
    static func gradientAxis(degrees: Double, in size: CGSize) -> (dx: Double, dy: Double, length: Double) {
        let angle = degrees * .pi / 180, dx = sin(angle), dy = -cos(angle)
        return (dx, dy, abs(size.width * dx) + abs(size.height * dy))
    }

    /// CSS 線性漸層的位置 t（0＝起點、1＝終點）
    static func linearPosition(degrees: Double, at point: CGPoint, in frame: CGRect) -> Double {
        let axis = gradientAxis(degrees: degrees, in: frame.size)
        let t = ((point.x - frame.midX) * axis.dx + (point.y - frame.midY) * axis.dy) / axis.length + 0.5
        return min(1, max(0, t))
    }

    static func albumColor(primary: RGBColor, scheme: ColorScheme, at point: CGPoint, in size: CGSize) -> RGBColor {
        let layer = BackgroundModel.layerFrame(in: size)
        let stops = albumColorStops(primary: primary, scheme: scheme)
        let t = linearPosition(degrees: albumGradientDegrees, at: point, in: layer)
        var color = stops.c2.over(stops.c1, alpha: t)
        let glow = albumGlow(primary: primary, scheme: scheme)
        let dx = (point.x - layer.minX - glowCenter.x * layer.width) / (glowRadius.x * layer.width)
        let dy = (point.y - layer.minY - glowCenter.y * layer.height) / (glowRadius.y * layer.height)
        let fade = max(0, 1 - (dx * dx + dy * dy).squareRoot() / BackgroundModel.pointFadeEnd)
        color = color.over(glow.color, alpha: glow.alpha * fade)
        return color.over(.black, alpha: BackgroundModel.dimOpacity(scheme))
    }

    static func ink(luminance: Double, previous: DetailInk?) -> DetailInk {
        if luminance <= inkWhiteAtOrBelow { return .white }
        if luminance >= inkDarkAtOrAbove { return .dark }
        return previous ?? (luminance < inkCrossover ? .white : .dark)
    }

    static func coverShadowOpacity(luminance: Double) -> Double {
        let t = min(1, max(0, (luminance - shadowLuminance.dark) / (shadowLuminance.light - shadowLuminance.dark)))
        return shadowOpacity.dark + (shadowOpacity.light - shadowOpacity.dark) * t
    }

    /// 資訊區：封面正下方 8 pt 起、高 0.45 倍封面
    static func infoRegion(cover: CGRect) -> CGRect {
        CGRect(x: cover.minX, y: cover.maxY + 8, width: cover.width, height: 0.45 * cover.height)
    }

    /// 封面下方（投影落點）：高 0.15 倍封面
    static func underCoverRegion(cover: CGRect) -> CGRect {
        CGRect(x: cover.minX, y: cover.maxY, width: cover.width, height: 0.15 * cover.height)
    }

    /// 曲目區＝曲目清單的實際 frame
    static func listRegion(cover: CGRect, size: CGSize) -> CGRect { DetailLayout.tracksFrame(cover: cover, size: size) }

    /// 12×12 格中心點的 WCAG 相對亮度平均
    static func averageLuminance(in rect: CGRect, color: (CGPoint) -> RGBColor) -> Double {
        let n = samplesPerSide
        var sum = 0.0
        for i in 0..<n {
            for j in 0..<n {
                let point = CGPoint(x: rect.minX + rect.width * (CGFloat(i) + 0.5) / CGFloat(n),
                                    y: rect.minY + rect.height * (CGFloat(j) + 0.5) / CGFloat(n))
                sum += color(point).luminance
            }
        }
        return sum / Double(n * n)
    }

    /// Reduce Transparency 的不透明單色（E.5；唯一定義，畫面與取樣共用）：漸層＝最暗色點、主色＝c1、模糊＝封面主色
    static func flatColor(_ content: DetailBackgroundController.Content, preset: BackgroundPreset, scheme: ColorScheme) -> RGBColor {
        switch content {
        case .gradient: BackgroundModel.baseColor(preset: preset, scheme: scheme)
        case .albumColor(let primary): albumColorStops(primary: primary, scheme: scheme).c1
        case .blur(let blur): blur.primary
        }
    }

    /// 某點的最終背景色（含最上層的黑）
    static func color(_ content: DetailBackgroundController.Content, preset: BackgroundPreset, scheme: ColorScheme,
                      reduceTransparency: Bool, at point: CGPoint, in size: CGSize) -> RGBColor {
        if reduceTransparency { return flatColor(content, preset: preset, scheme: scheme) }
        return switch content {
        case .gradient: BackgroundModel.presetColor(preset: preset, scheme: scheme, at: point, in: size)
        case .albumColor(let primary): albumColor(primary: primary, scheme: scheme, at: point, in: size)
        case .blur(let blur): blur.sampler.color(at: point, in: size)
        }
    }
}

/// 模糊圖的取樣器：與畫面同一個 aspect-fill 映射、雙線性、疊黑 0.2
struct BlurSampler: Sendable {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int

    init?(image: UIImage) {
        guard let source = image.cgImage, source.width > 0, source.height > 0 else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.pixels = pixels
        self.width = width
        self.height = height
    }

    func color(at point: CGPoint, in size: CGSize) -> RGBColor {
        let scale = max(size.width / CGFloat(width), size.height / CGFloat(height))
        let origin = CGPoint(x: (size.width - CGFloat(width) * scale) / 2, y: (size.height - CGFloat(height) * scale) / 2)
        let fx = min(CGFloat(width - 1), max(0, (point.x - origin.x) / scale - 0.5))
        let fy = min(CGFloat(height - 1), max(0, (point.y - origin.y) / scale - 0.5))
        let x0 = Int(fx), y0 = Int(fy), x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let tx = Double(fx - CGFloat(x0)), ty = Double(fy - CGFloat(y0))
        func channel(_ c: Int) -> Double {
            func at(_ x: Int, _ y: Int) -> Double { Double(pixels[(y * width + x) * 4 + c]) / 255 }
            let top = at(x0, y0) * (1 - tx) + at(x1, y0) * tx, bottom = at(x0, y1) * (1 - tx) + at(x1, y1) * tx
            return top * (1 - ty) + bottom * ty
        }
        return RGBColor(r: channel(0), g: channel(1), b: channel(2)).over(.black, alpha: DetailBackgroundModel.blurDim)
    }
}

/// 背景 Task 的產物：主色（albumColor 與 Reduce Transparency 用）、模糊圖與其取樣器
struct DetailBackgroundProduct: Sendable {
    let primary: RGBColor
    let blurred: UIImage?
    let sampler: BlurSampler?

    init(primary: RGBColor, blurred: UIImage?) {
        self.primary = primary
        self.blurred = blurred
        sampler = blurred.flatMap(BlurSampler.init(image:))
    }

    /// 正式產生器：取色與模糊都在呼叫端的背景 Task 做（不在主執行緒）
    static func produce(_ image: UIImage, _ mode: DetailBackgroundMode) async -> DetailBackgroundProduct? {
        let primary = AlbumPalette.extract(from: image).primary
        guard mode == .turntableBlur else { return DetailBackgroundProduct(primary: primary, blurred: nil) }
        guard let blurred = TurntableBackground.blurred(image) else { return nil }
        return DetailBackgroundProduct(primary: primary, blurred: blurred)
    }
}

/// 一個詳情頁上的字色與投影：兩區各自遲滯；換專輯重新首判
struct DetailInkState: Equatable {
    private(set) var info: DetailInk = .white
    private(set) var list: DetailInk = .white
    private(set) var coverShadowOpacity = DetailBackgroundModel.shadowOpacity.dark
    private var decided = false

    mutating func update(info infoL: Double, list listL: Double, under underL: Double) {
        info = DetailBackgroundModel.ink(luminance: infoL, previous: decided ? info : nil)
        list = DetailBackgroundModel.ink(luminance: listL, previous: decided ? list : nil)
        coverShadowOpacity = DetailBackgroundModel.coverShadowOpacity(luminance: underL)
        decided = true
    }

    mutating func reset() { self = DetailInkState() }
}

/// 詳情背景的產生、快取與競態防線（附錄 E.4）：鍵＝(albumID, artworkToken, mode, 主題)；結果回主執行緒時
/// 比對世代（＝目前請求）才套用；新專輯開啟的同步初態＝漸層
@MainActor
@Observable
final class DetailBackgroundController {
    final class Blurred: Hashable {
        let image: UIImage
        let sampler: BlurSampler
        let primary: RGBColor

        init(image: UIImage, sampler: BlurSampler, primary: RGBColor) {
            self.image = image
            self.sampler = sampler
            self.primary = primary
        }

        static func == (a: Blurred, b: Blurred) -> Bool { a === b }
        func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    }

    enum Content: Hashable {
        case gradient
        case albumColor(RGBColor)
        case blur(Blurred)
    }

    struct Request: Equatable {
        let albumID: String
        let artworkToken: String?
        let image: UIImage?
        let mode: DetailBackgroundMode
        let scheme: ColorScheme

        /// 圖以同一個物件判斷（spine → 原檔是換了一張圖）
        static func == (a: Request, b: Request) -> Bool {
            a.albumID == b.albumID && a.artworkToken == b.artworkToken && a.image === b.image && a.mode == b.mode && a.scheme == b.scheme
        }
    }

    /// 取字色要的版面（詳情局部座標）
    struct Layout: Equatable {
        let cover: CGRect
        let size: CGSize
        let preset: BackgroundPreset
        let reduceTransparency: Bool
    }

    /// 同一 token 下 spine 小圖與原檔是兩份結果（以像素寬區分；codex simcodex R1）
    private struct Key: Hashable {
        let albumID: String
        let artworkToken: String?
        let pixelWidth: Int
        let mode: DetailBackgroundMode
        let scheme: ColorScheme
    }

    private final class KeyBox: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private final class ContentBox {
        let content: Content
        init(_ content: Content) { self.content = content }
    }

    static let cacheLimit = 16

    private(set) var content: Content = .gradient
    private(set) var ink = DetailInkState()

    @ObservationIgnored private let produce: @Sendable (UIImage, DetailBackgroundMode) async -> DetailBackgroundProduct?
    @ObservationIgnored private let cache = NSCache<KeyBox, ContentBox>()
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private var layout: Layout?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var memoryWarning: NSObjectProtocol?

    init(produce: @escaping @Sendable (UIImage, DetailBackgroundMode) async -> DetailBackgroundProduct? = DetailBackgroundProduct.produce) {
        self.produce = produce
        cache.countLimit = Self.cacheLimit
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeCache() }
        }
    }

    isolated deinit {
        task?.cancel()
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
    }

    func update(_ next: Request) {
        let albumChanged = request?.albumID != next.albumID
        request = next
        generation += 1
        task?.cancel()
        if albumChanged {
            content = .gradient
            ink.reset()
        }
        guard next.mode != .gradient, let image = next.image else { return apply(.gradient) }
        let key = Key(albumID: next.albumID, artworkToken: next.artworkToken, pixelWidth: image.cgImage?.width ?? 0, mode: next.mode,
                      scheme: next.scheme)
        if let cached = cache.object(forKey: KeyBox(key)) { return apply(cached.content) }
        recomputeInk()
        let generation = generation, produce = produce, mode = next.mode
        task = Task { [weak self] in
            let product = await produce(image, mode)
            guard let self, generation == self.generation, let product, let content = Self.content(product, mode: mode) else { return }
            cache.setObject(ContentBox(content), forKey: KeyBox(key))
            apply(content)
        }
    }

    func updateLayout(_ next: Layout) {
        guard next != layout else { return }
        layout = next
        recomputeInk()
    }

    func purgeCache() { cache.removeAllObjects() }

    private func apply(_ next: Content) {
        content = next
        recomputeInk()
    }

    private func recomputeInk() {
        guard let layout, let request else { return }
        let content = content, size = layout.size
        let color = { (point: CGPoint) in
            DetailBackgroundModel.color(content, preset: layout.preset, scheme: request.scheme, reduceTransparency: layout.reduceTransparency,
                                        at: point, in: size)
        }
        var next = ink
        next.update(info: DetailBackgroundModel.averageLuminance(in: DetailBackgroundModel.infoRegion(cover: layout.cover), color: color),
                    list: DetailBackgroundModel.averageLuminance(in: DetailBackgroundModel.listRegion(cover: layout.cover, size: size), color: color),
                    under: DetailBackgroundModel.averageLuminance(in: DetailBackgroundModel.underCoverRegion(cover: layout.cover), color: color))
        if next != ink { ink = next }
    }

    private static func content(_ product: DetailBackgroundProduct, mode: DetailBackgroundMode) -> Content? {
        switch mode {
        case .gradient: return .gradient
        case .albumColor: return .albumColor(product.primary)
        case .turntableBlur:
            guard let image = product.blurred, let sampler = product.sampler else { return nil }
            return .blur(Blurred(image: image, sampler: sampler, primary: product.primary))
        }
    }
}
