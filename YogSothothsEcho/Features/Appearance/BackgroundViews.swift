import SwiftUI
import UIKit

/// CSS 的橢圓放射漸層＝縱向縮放的圓（附錄 E.3；不用 `EllipticalGradient`）：圓形 `RadialGradient` 半徑 rx，
/// 以中心為錨 `scaleEffect(y: ry/rx)`。`reach`＝畫到幾倍 rx（超出最後一個 stop 的部分以最後的顏色延伸）
private struct EllipseGradient: View {
    let stops: [Gradient.Stop]
    let center: CGPoint
    let radii: (x: CGFloat, y: CGFloat)
    var reach: CGFloat = 1

    var body: some View {
        let side = 2 * radii.x * reach
        RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: radii.x)
            .frame(width: side, height: side)
            .scaleEffect(x: 1, y: radii.y / radii.x, anchor: .center)
            .position(center)
    }
}

/// 側封頁／詳情「漸層」背景（E.3）：最暗色點鋪底，色點由最後一點先疊；最後疊黑。Reduce Transparency＝不透明的最暗色點單色（E.5）
struct PresetGradientView: View {
    let preset: BackgroundPreset
    let scheme: ColorScheme
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            let layer = BackgroundModel.layerFrame(in: proxy.size)
            ZStack(alignment: .topLeading) {
                BackgroundModel.baseColor(preset: preset, scheme: scheme).color
                if !reduceTransparency {
                    ForEach(Array(BackgroundModel.points(preset).enumerated().reversed()), id: \.offset) { _, point in
                        let color = point.color(scheme).color
                        EllipseGradient(stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: BackgroundModel.pointFadeEnd)],
                                        center: CGPoint(x: layer.minX + point.x * layer.width, y: layer.minY + point.y * layer.height),
                                        radii: (BackgroundModel.pointRadius.x * layer.width, BackgroundModel.pointRadius.y * layer.height))
                    }
                    Color.black.opacity(BackgroundModel.dimOpacity(scheme))
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// 四周壓暗（E.3①）：Reduce Transparency 下保留（裝飾暗角，不影響可讀性）
struct VignetteView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size, radii = BackgroundModel.vignetteRadii(in: size)
            let stops = BackgroundModel.vignetteStops
            EllipseGradient(stops: [.init(color: .clear, location: stops.clear / stops.full),
                                    .init(color: .black.opacity(BackgroundModel.vignetteOpacity), location: 1)],
                            center: CGPoint(x: BackgroundModel.vignetteCenter.x * size.width, y: BackgroundModel.vignetteCenter.y * size.height),
                            radii: (radii.x * stops.full, radii.y * stops.full), reach: 1.2)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// 淡陰影帶（E.3③）：地面線上方 30 起、高 120、寬 110%；橢圓 55%×45% 在 (50%, 28%)，黑 0.40 → 78% 透明，模糊 6。
/// 小樣值以 13 吋（A＝764）為準，`unit`＝A/764 等比例
struct ShadowBandView: View {
    let floor: CGFloat
    let width: CGFloat
    let unit: CGFloat

    static let rise: CGFloat = 30
    static let height: CGFloat = 120
    static let overhang: CGFloat = 0.05
    static let center = (x: 0.5, y: 0.28)
    static let radius = (x: 0.55, y: 0.45)
    static let opacity = 0.40
    static let fadeEnd = 0.78
    static let blur: CGFloat = 6

    var body: some View {
        let bandWidth = width * (1 + 2 * Self.overhang), bandHeight = Self.height * unit
        EllipseGradient(stops: [.init(color: .black.opacity(Self.opacity), location: 0), .init(color: .clear, location: Self.fadeEnd)],
                        center: CGPoint(x: Self.center.x * bandWidth, y: Self.center.y * bandHeight),
                        radii: (Self.radius.x * bandWidth, Self.radius.y * bandHeight))
            .frame(width: bandWidth, height: bandHeight)
            .clipped()
            .blur(radius: Self.blur * unit)
            .offset(x: -Self.overhang * width, y: floor - Self.rise * unit)
            .frame(width: width, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}

/// 地面倒影（E.3②）：內容以地面線垂直鏡射、遮罩在原圖座標（隨內容翻轉）；不裁切、不收觸控。只畫鏡像本身
private struct FloorMirror: ViewModifier {
    let floor: CGFloat
    let size: CGSize

    func body(content: Content) -> some View {
        let s = BackgroundModel.reflectionStops
        content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: s.start), .init(color: .white.opacity(s.peakAlpha), location: s.peak),
                                       .init(color: .white.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .scaleEffect(x: 1, y: -1, anchor: UnitPoint(x: 0.5, y: floor / size.height))
            .allowsHitTesting(false)
    }
}

extension View {
    /// 只畫鏡像（側封：整層盒子鏡射一次、一個遮罩，疊在所有盒子之下）。`size`＝瀏覽區（遮罩的 q 以其高為分母）；`floor`＝地面線
    func floorMirror(floor: CGFloat, size: CGSize) -> some View {
        modifier(FloorMirror(floor: floor, size: size))
    }

    /// 本體＋其鏡像（Render 測試用的單一內容版本）
    @ViewBuilder func floorReflection(floor: CGFloat, size: CGSize, enabled: Bool) -> some View {
        if enabled {
            frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(alignment: .topLeading) { self.floorMirror(floor: floor, size: size) }
        } else {
            self
        }
    }
}

/// 專輯主色背景（E.4）：145° 線性底 c2→c1＋右上同色柔光，最後疊黑；圖層同漸層擴張 12%
struct AlbumColorBackgroundView: View {
    let primary: RGBColor
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { proxy in
            let layer = BackgroundModel.layerFrame(in: proxy.size)
            let stops = DetailBackgroundModel.albumColorStops(primary: primary, scheme: scheme)
            let glow = DetailBackgroundModel.albumGlow(primary: primary, scheme: scheme)
            let line = Self.gradientLine(in: layer.size)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [stops.c2.color, stops.c1.color], startPoint: line.start, endPoint: line.end)
                    .frame(width: layer.width, height: layer.height)
                    .offset(x: layer.minX, y: layer.minY)
                EllipseGradient(stops: [.init(color: glow.color.color.opacity(glow.alpha), location: 0),
                                        .init(color: glow.color.color.opacity(0), location: BackgroundModel.pointFadeEnd)],
                                center: CGPoint(x: layer.minX + DetailBackgroundModel.glowCenter.x * layer.width,
                                                y: layer.minY + DetailBackgroundModel.glowCenter.y * layer.height),
                                radii: (DetailBackgroundModel.glowRadius.x * layer.width, DetailBackgroundModel.glowRadius.y * layer.height))
                Color.black.opacity(BackgroundModel.dimOpacity(scheme))
            }
        }
        .clipped()
    }

    /// CSS 角度漸層的起訖點（圖層比例）
    static func gradientLine(in size: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        let axis = DetailBackgroundModel.gradientAxis(degrees: DetailBackgroundModel.albumGradientDegrees, in: size)
        let dx = axis.dx * axis.length / 2 / size.width, dy = axis.dy * axis.length / 2 / size.height
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

/// 詳情背景（E.4）：依內容畫三種之一；換內容 0.2 s 交叉淡化（Reduce Motion 直接換）
struct DetailBackgroundView: View {
    let content: DetailBackgroundController.Content
    let preset: BackgroundPreset
    let scheme: ColorScheme
    let reduceTransparency: Bool
    let reduceMotion: Bool

    static let crossfade = 0.2

    var body: some View {
        ZStack {
            layer.id(content)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Self.crossfade), value: content)
        .allowsHitTesting(false)
    }

    /// 裝飾圖不進 AX 樹（不用 accessibilityHidden：殼層唱機開→關把祖先的 hidden 切回 false 後，子孫掛的 hidden 反而把背景層
    /// 變成溢出畫面的大 AX 框、蓋住返回鍵，`testTurntableFromDetailReturnsToDetail` 實測）
    private func decorative(_ image: UIImage) -> Image {
        image.cgImage.map { Image(decorative: $0, scale: image.scale) } ?? Image(uiImage: image)
    }

    @ViewBuilder private var layer: some View {
        if reduceTransparency {
            DetailBackgroundModel.flatColor(content, preset: preset, scheme: scheme).color
        } else {
            switch content {
            case .gradient:
                PresetGradientView(preset: preset, scheme: scheme, reduceTransparency: false)
            case .albumColor(let primary):
                AlbumColorBackgroundView(primary: primary, scheme: scheme)
            case .blur(let blur):
                GeometryReader { proxy in
                    decorative(blur.image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(Color.black.opacity(DetailBackgroundModel.blurDim))
                }
            }
        }
    }
}

/// 選單裡的色票：圓形、以漸層純函式取 3 點（不透明原色，不被選單染成單色）
@MainActor
enum BackgroundSwatch {
    private static let side: CGFloat = 22
    /// 7 組×深淺最多 14 張，畫一次就留著（殼層重算時選單內容會重新求值）
    private static var cache: [String: UIImage] = [:]

    static func image(_ preset: BackgroundPreset, scheme: ColorScheme) -> UIImage {
        let key = "\(preset.rawValue).\(scheme == .dark)"
        if let cached = cache[key] { return cached }
        let image = render(preset, scheme: scheme)
        cache[key] = image
        return image
    }

    private static func render(_ preset: BackgroundPreset, scheme: ColorScheme) -> UIImage {
        let size = CGSize(width: side, height: side), canvas = CGSize(width: 1376, height: 1032)
        let colors = [CGPoint(x: 200, y: 150), CGPoint(x: 1200, y: 200), CGPoint(x: 700, y: 950)]
            .map { BackgroundModel.presetColor(preset: preset, scheme: scheme, at: $0, in: canvas) }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: rect).addClip()
            let cg = colors.map { UIColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1).cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cg, locations: [0, 0.5, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
