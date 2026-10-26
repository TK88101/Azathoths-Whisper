import SwiftUI
import UIKit

/// 轉動參照（sprint-5-detail.md §4.2b v2.0）：base（溝槽＋高光）依 spec 不轉、同心溝紋轉了也看不出，
/// 18°/s 下 CLASSIC 與磨砂盤外圈像靜止——加一層隨唱片轉的紋理。使用者 2026-10-21 看小樣 s5-rotation-cue-preview.html 選定
enum RotationCue: Equatable {
    /// B1 寬光暈（CLASSIC）
    case sheen
    /// B3 放射紋（降低透明度的不透明盤：不放同色點）
    case radial
    /// B3 放射紋＋小樣的同色點（磨砂盤；取代 noise 位圖）
    case radialWithSpecks

    /// 呼叫端傳 resolved style；`.random` 與 `VinylRecordView.styleLayers` 一致走 CLASSIC 外觀。
    /// SPLASH、MARBLE 原本就有明顯旋轉圖案
    static func cue(style: RecordStyle, finish: TransparentFinish?) -> RotationCue? {
        switch (style, finish) {
        case (.classic, _), (.random, _): .sheen
        case (.transparent, .frosted): .radialWithSpecks
        case (.transparent, .opaque): .radial
        default: nil
        }
    }

    /// 放射紋顏色（v2.1 T5／T10）：不透明盤依實際填色選黑白（白盤上白線看不見，實機 ⑤）；磨砂盤維持白
    static func rayColor(finish: TransparentFinish?, colors: AlbumColors) -> RGBColor {
        finish == .opaque ? AlbumPalette.textColor(on: TransparentFinish.opaqueFill(for: colors)) : .white
    }
}

/// B1：兩片很淡的寬扇形（照小樣）；頭尾同為透明，繞回 3 點鐘不接縫（同 `VinylRecordView.rimStops` 原則）
enum RotationSheen {
    struct Stop: Equatable {
        let location: Double
        let opacity: Double
    }

    static let stops: [Stop] = [.init(location: 0, opacity: 0), .init(location: 0.12, opacity: 0.10), .init(location: 0.24, opacity: 0),
                                .init(location: 0.55, opacity: 0), .init(location: 0.66, opacity: 0.07), .init(location: 0.78, opacity: 0),
                                .init(location: 1, opacity: 0)]

    static let gradient = AngularGradient(stops: stops.map { .init(color: .white.opacity($0.opacity), location: $0.location) },
                                          center: .center)
}

/// Park & Miller (1988) 最小標準亂數；與小樣同演算法，但不宣稱同一分布（小樣先消耗了其他欄位的亂數）
struct ParkMiller {
    private static let modulus: UInt64 = 2_147_483_647
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextRaw() -> UInt64 {
        state = state * 16807 % Self.modulus
        return state
    }

    /// (0, 1)
    mutating func next() -> Double { Double(nextRaw()) / Double(Self.modulus) }
}

/// B3 的幾何，單位座標（唱片半徑＝1）。座標系照小樣：內緣 0.33（App 標籤半徑 0.452 會蓋住內側，露出的環帶密度與小樣一致）；
/// 放射線參數逐字取自小樣 L41、L51；角度用 [0, 2π)（小樣 `rnd()*7` 超過 2π 是瑕疵，不照抄）。
/// 點照使用者選的小樣 A（v2.1 T1，`s5-speck-shape-preview.html`）：輕度不規則——偏態點徑、長寬比 70／27／3 分桶、
/// 長軸＝放射向 ±45°、2θ／3θ 低頻起伏、15% 帶 1–2 顆衛星小點；面積以基準橢圓守恆（起伏不另補償）
struct RadialField: Equatable {
    struct Satellite: Equatable {
        let angle: Double
        let distance: Double
        let radius: Double
    }

    struct Speck: Equatable {
        let angle: Double
        let radius: Double
        /// 等面積圓的半徑
        let size: Double
        /// 長寬比 k ≥ 1
        let aspect: Double
        /// 長軸方向（弧度）
        let orientation: Double
        /// 邊緣起伏：2θ、3θ 兩個諧波的幅度與相位
        let wobble2: Double
        let wobble3: Double
        let phase2: Double
        let phase3: Double
        let satellites: [Satellite]

        var semiMajor: Double { size * aspect.squareRoot() }
        var semiMinor: Double { size / aspect.squareRoot() }
    }

    struct Ray: Equatable {
        let angle: Double
        let opacity: Double
        let width: Double
    }

    static let innerRadius = 0.33
    static let rayStart = 0.35
    static let rayEnd = 0.99
    static let speckCount = 900
    static let rayCount = 260
    /// 長寬比分桶（累積機率、下限、上限）
    static let aspectBuckets: [(cumulative: Double, range: ClosedRange<Double>)] = [(0.70, 1...1.35), (0.97, 1.35...2.5), (1, 2.5...4)]
    static let orientationJitter = Double.pi / 4
    static let satelliteChance = 0.15

    let specks: [Speck]
    let rays: [Ray]

    static let standard = generate(seed: 7)

    static func generate(seed: UInt64) -> RadialField {
        var rng = ParkMiller(seed: seed)
        let specks = (0..<speckCount).map { _ in speck(&rng) }
        let rays = (0..<rayCount).map { _ in
            Ray(angle: rng.next() * 2 * .pi, opacity: 0.015 + rng.next() * 0.06, width: 0.002 + rng.next() * 0.006)
        }
        return RadialField(specks: specks, rays: rays)
    }

    /// 亂數消耗順序固定（golden 測試依此）：角度、半徑、點徑、長寬比分桶、長寬比、方向、起伏×4、衛星
    private static func speck(_ rng: inout ParkMiller) -> Speck {
        let angle = rng.next() * 2 * .pi
        let radius = innerRadius + rng.next() * (1 - innerRadius)
        let u = rng.next()
        let size = 0.002 + u * u * 0.014
        let bucket = rng.next()
        let range = aspectBuckets.first { bucket < $0.cumulative }?.range ?? aspectBuckets[aspectBuckets.count - 1].range
        let aspect = range.lowerBound + rng.next() * (range.upperBound - range.lowerBound)
        let orientation = angle + (rng.next() * 2 - 1) * orientationJitter
        let wobble2 = 0.12 * (0.5 + 0.5 * rng.next())
        let wobble3 = 0.06 * rng.next()
        let phase2 = rng.next() * 2 * .pi
        let phase3 = rng.next() * 2 * .pi
        var satellites: [Satellite] = []
        if rng.next() < satelliteChance {
            let count = rng.next() < 0.4 ? 2 : 1
            satellites = (0..<count).map { _ in
                Satellite(angle: rng.next() * 2 * .pi, distance: size * (1.1 + rng.next() * 0.8), radius: size * (0.2 + rng.next() * 0.25))
            }
        }
        return Speck(angle: angle, radius: radius, size: size, aspect: aspect, orientation: orientation,
                     wobble2: wobble2, wobble3: wobble3, phase2: phase2, phase3: phase3, satellites: satellites)
    }
}

/// 點與放射線的遮罩圖：只在尺寸變化時重畫，每幀只旋轉。點是白色不透明（視圖再以同色系上色）、線帶各自的 alpha。
/// 快取鍵＝像素邊長（已含 displayScale），每種最多 2 組尺寸（最近使用優先保留）
@MainActor
enum RotationCueMasks {
    private enum Kind { case specks, rays }

    private static let capacity = 2
    private static var cache: [Kind: [(side: Int, image: UIImage)]] = [:]

    static func specks(pixelSide: Int) -> UIImage { image(.specks, pixelSide: pixelSide) }
    static func rays(pixelSide: Int) -> UIImage { image(.rays, pixelSide: pixelSide) }

    /// 點遮罩快取中的尺寸，舊→新（測試用）
    static var cachedSides: [Int] { cache[.specks, default: []].map(\.side) }

    static func resetCache() { cache = [:] }

    private static func image(_ kind: Kind, pixelSide: Int) -> UIImage {
        var entries = cache[kind, default: []]
        if let index = entries.firstIndex(where: { $0.side == pixelSide }) {
            let hit = entries.remove(at: index)
            cache[kind] = entries + [hit]
            return hit.image
        }
        let rendered = render(kind, pixelSide: pixelSide)
        cache[kind] = Array((entries + [(pixelSide, rendered)]).suffix(capacity))
        return rendered
    }

    private static func render(_ kind: Kind, pixelSide: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let side = CGFloat(pixelSide), half = side / 2
        let field = RadialField.standard
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            func point(_ angle: Double, _ radius: Double) -> CGPoint {
                CGPoint(x: half + cos(angle) * radius * half, y: half + sin(angle) * radius * half)
            }
            switch kind {
            case .specks:
                // 照小樣靠圓形 clip：起伏、長軸與衛星可越過盤緣，裁掉
                cg.addEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
                cg.clip()
                cg.setFillColor(UIColor.white.cgColor)
                for speck in field.specks {
                    let center = point(speck.angle, speck.radius)
                    cg.addPath(speckPath(speck, center: center, scale: half))
                    for satellite in speck.satellites {
                        let r = satellite.radius * half
                        let c = CGPoint(x: center.x + cos(satellite.angle) * satellite.distance * half,
                                        y: center.y + sin(satellite.angle) * satellite.distance * half)
                        cg.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    }
                }
                cg.fillPath()
            case .rays:
                cg.setLineCap(.butt)
                for ray in field.rays {
                    cg.setStrokeColor(UIColor.white.withAlphaComponent(ray.opacity).cgColor)
                    cg.setLineWidth(ray.width * half)
                    cg.move(to: point(ray.angle, RadialField.rayStart))
                    cg.addLine(to: point(ray.angle, RadialField.rayEnd))
                    cg.strokePath()
                }
            }
        }
    }
}

extension RotationCueMasks {
    /// 不規則小島（同小樣）：12 點的基準橢圓乘上 2θ／3θ 起伏，以中點二次曲線閉合
    static func speckPath(_ speck: RadialField.Speck, center: CGPoint, scale: CGFloat) -> CGPath {
        let sides = 12
        let points = (0..<sides).map { i -> CGPoint in
            let t = Double(i) / Double(sides) * 2 * .pi
            let m = 1 + speck.wobble2 * sin(2 * t + speck.phase2) + speck.wobble3 * sin(3 * t + speck.phase3)
            let x = cos(t) * speck.semiMajor * m, y = sin(t) * speck.semiMinor * m
            let o = speck.orientation
            return CGPoint(x: center.x + (x * cos(o) - y * sin(o)) * scale, y: center.y + (x * sin(o) + y * cos(o)) * scale)
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let path = CGMutablePath()
        path.move(to: mid(points[sides - 1], points[0]))
        for i in 0..<sides {
            path.addQuadCurve(to: mid(points[i], points[(i + 1) % sides]), control: points[i])
        }
        path.closeSubpath()
        return path
    }
}

/// 環形（內徑為直徑的比例）：光暈只畫在標籤外緣到盤緣
struct RingShape: Shape {
    let innerFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        let inset = rect.width * (1 - innerFraction) / 2
        path.addEllipse(in: rect.insetBy(dx: inset, dy: inset))
        return path
    }
}
