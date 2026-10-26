import CoreGraphics
import SwiftUI

/// 一張唱片封套的磨損形狀（#6-1 第二輪 F2 ④「中、每張不同」，使用者 2026-10-22 定案；s6-61-round2.md §4 P1）。
/// 依專輯 ID 決定、跨啟動相同；比例欄位乘上 `SpineWear` 的基準值與 u（cover／764）才是 pt
struct SpineWearShape: Equatable, Sendable {
    enum Edge: Equatable, Sendable { case top, bottom, left, right }
    struct Nick: Equatable, Sendable {
        let edge: Edge
        /// 沿該邊的位置（0…1）
        let position: CGFloat
        /// 半徑（u＝1、未乘新舊）
        let radius: CGFloat
    }

    /// 整體新舊
    let age: CGFloat
    /// 正面四角：左上、右上、左下、右下
    let corners: [CGFloat]
    /// 正面四邊：上、下、左、右
    let edges: [CGFloat]
    /// 書脊上、下端
    let spineEnds: [CGFloat]
    /// 書脊折邊側的磨痕寬
    let spineFoldRub: CGFloat
    let frontNicks: [Nick]
    let spineNicks: [Nick]
}

/// 向量磨損路徑：core＝紙漿色實心；halo＝同一組形狀放大一圈、抖得更兇，以纖維遮罩填（＝起毛），同小樣 fuzz 濾鏡；
/// flecks＝細邊的碎屑帶，以碎塊遮罩填
struct SpineWearPaths: Equatable {
    let core: Path
    let halo: Path
    let flecks: Path
}

enum SpineWear {
    enum Surface: Hashable, Sendable { case front, spine }

    // 基準（「中」、u＝1；小樣 A＝764 時的 px）
    static let cornerRadius: CGFloat = 15
    static let edgeWidth: CGFloat = 1.6
    static let spineEnd: CGFloat = 5
    /// 起毛帶寬
    static let fuzzWidth: CGFloat = 8
    static let jagAmplitude: CGFloat = 4.5
    /// 起毛帶的抖動是實心的 1.6 倍（小樣 fuzz 位移 scale＝1.6×d）
    static let haloJagScale: CGFloat = 1.6
    /// 鋸齒雜訊的格距（u＝1；小樣位移雜訊頻率 0.28／px）與輪廓取點間距
    static let jagSpacing: CGFloat = 1 / 0.28
    static let pointSpacing: CGFloat = 1
    /// 約 1/5 的角幾乎完好
    static let intactCornerChance = 0.22
    /// 新舊、書脊上下端的取樣範圍（書脊烘焙的「普通」區間由此推出）
    static let ageRange: ClosedRange<Double> = 0.6...1.3
    static let spineEndRange: ClosedRange<Double> = 0.3...1.6

    /// FNV-1a 64
    static func seed(albumID: String) -> UInt64 {
        albumID.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    static func shape(albumID: String) -> SpineWearShape {
        var rng = SeededGenerator(seed: seed(albumID: albumID))
        func uniform(_ range: ClosedRange<Double>) -> CGFloat { CGFloat(range.lowerBound + rng.nextUnit() * (range.upperBound - range.lowerBound)) }
        let age = uniform(ageRange)
        let corners = (0..<4).map { _ in rng.nextUnit() < intactCornerChance ? uniform(0.15...0.35) : uniform(0.5...1.5) }
        let edges = (0..<4).map { _ in uniform(0.35...1.45) }
        let spineEnds = (0..<2).map { _ in uniform(spineEndRange) }
        let rub = uniform(0.35...1.45)
        let frontEdges: [SpineWearShape.Edge] = [.top, .bottom, .left, .right]
        let frontNicks = (0..<Int(rng.next() % 4)).map { _ in
            SpineWearShape.Nick(edge: frontEdges[Int(rng.next() % 4)], position: uniform(0.1...0.9), radius: uniform(1.5...5))
        }
        let spineNicks = (0..<Int(rng.next() % 3)).map { _ in
            SpineWearShape.Nick(edge: rng.next() % 2 == 0 ? .left : .right, position: uniform(0.1...0.9), radius: uniform(1.5...5))
        }
        return SpineWearShape(age: age, corners: corners, edges: edges, spineEnds: spineEnds, spineFoldRub: rub,
                              frontNicks: frontNicks, spineNicks: spineNicks)
    }

    static func nickCenter(_ nick: SpineWearShape.Nick, size: CGSize) -> CGPoint {
        switch nick.edge {
        case .top: CGPoint(x: nick.position * size.width, y: 0)
        case .bottom: CGPoint(x: nick.position * size.width, y: size.height)
        case .left: CGPoint(x: 0, y: nick.position * size.height)
        case .right: CGPoint(x: size.width, y: nick.position * size.height)
        }
    }

    /// 座標＝該面未鏡像的本地座標（書脊以左側盒方向：折邊在 trailing）；u＝面高／764。
    /// 形狀與尺寸比例同小樣（s6-spine-realism-preview.html `wearSVG`）：每個形狀各畫實心與放大的起毛兩份
    static func paths(albumID: String, shape: SpineWearShape, surface: Surface, size: CGSize) -> SpineWearPaths {
        let u = size.height / SpineCarouselMetrics.referenceCover, g = shape.age
        let jag = jagAmplitude * u, haloJag = jag * haloJagScale, fuzz = fuzzWidth * u * g
        var coreJag = Jag(seed: seed(albumID: albumID) ^ (surface == .front ? 0x46 : 0x53), spacing: jagSpacing * u)
        var haloNoise = Jag(seed: seed(albumID: albumID) ^ (surface == .front ? 0x66 : 0x73), spacing: jagSpacing * u)
        var core = Path(), halo = Path(), flecks = Path()
        func disc(_ center: CGPoint, radius: CGFloat, haloRadius: CGFloat) {
            guard radius > 0 else { return }
            core.addPath(coreJag.circle(center: center, radius: radius, amplitude: min(jag, 0.4 * radius), step: pointSpacing * u))
            halo.addPath(haloNoise.circle(center: center, radius: haloRadius, amplitude: min(haloJag, 0.4 * haloRadius), step: pointSpacing * u))
        }
        // 沿一條邊的帶。solid＝false 的細邊（正面四邊、書脊折邊）只有起毛的細碎白點、不畫實心：
        // 實心細帶被推移後會連成一條彎曲白線，像畫上去的線（使用者 2026-10-22 看模擬器截圖）
        func band(_ edge: SpineWearShape.Edge, depth: CGFloat, haloDepth: CGFloat, amplitude: CGFloat, solid: Bool) {
            guard depth > 0 else { return }
            if solid {
                core.addPath(coreJag.band(edge: edge, depth: depth, amplitude: amplitude, size: size, step: pointSpacing * u))
            } else {
                // 細帶被位移打散的範圍：自邊緣起 depth＋振幅（往外的一半在面外、被裁掉）
                flecks.addRect(Self.strip(edge: edge, depth: depth + amplitude, size: size))
            }
            halo.addPath(haloNoise.band(edge: edge, depth: haloDepth, amplitude: amplitude * haloJagScale, size: size, step: pointSpacing * u))
        }
        switch surface {
        case .front:
            let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            for (corner, scale) in zip(corners, shape.corners) {
                disc(corner, radius: cornerRadius * u * g * scale, haloRadius: (cornerRadius * u * g + fuzz * 1.6) * scale)
            }
            // 小樣：左邊（折邊側）的起毛帶較窄（×0.6）
            for (edge, scale) in zip([SpineWearShape.Edge.top, .bottom, .left, .right], shape.edges) {
                let e = edgeWidth * u * g
                band(edge, depth: e * scale, haloDepth: (e + fuzz * (edge == .left ? 0.6 : 1)) * scale, amplitude: jag, solid: false)
            }
            for nick in shape.frontNicks {
                let r = nick.radius * u * g
                disc(nickCenter(nick, size: size), radius: r, haloRadius: r + fuzz * 0.8)
            }
        case .spine:
            for (edge, scale) in zip([SpineWearShape.Edge.top, .bottom], shape.spineEnds) {
                let depth = spineEnd * u * g * scale
                band(edge, depth: depth, haloDepth: (spineEnd * u * g + fuzz * 1.5) * scale, amplitude: min(jag, 0.4 * depth), solid: true)
            }
            let rub = edgeWidth * 0.8 * u * g
            band(.right, depth: rub * shape.spineFoldRub, haloDepth: edgeWidth * u * g + fuzz * 0.5, amplitude: jag, solid: false)
            for nick in shape.spineNicks {
                let r = nick.radius * u * g
                disc(nickCenter(nick, size: size), radius: r, haloRadius: r + fuzz * 0.8)
            }
        }
        return SpineWearPaths(core: core, halo: halo, flecks: flecks)
    }

    static func strip(edge: SpineWearShape.Edge, depth: CGFloat, size: CGSize) -> CGRect {
        switch edge {
        case .top: CGRect(x: 0, y: 0, width: size.width, height: depth)
        case .bottom: CGRect(x: 0, y: size.height - depth, width: size.width, height: depth)
        case .left: CGRect(x: 0, y: 0, width: depth, height: size.height)
        case .right: CGRect(x: size.width - depth, y: 0, width: depth, height: size.height)
        }
    }

    /// 1D value noise（−1…1）：格點值由種子雜湊、格點間 smoothstep；每畫一個形狀往後跳一段，形狀之間互不相關。
    /// 每個形狀先把用得到的格點值算成表再內插（不逐點重算雜湊）
    struct Jag {
        let seed: UInt64
        let spacing: CGFloat
        private var offset: Int64 = 0

        init(seed: UInt64, spacing: CGFloat) {
            self.seed = seed
            self.spacing = spacing
        }

        private func lattice(_ i: Int64) -> Double { Self.lattice(seed: seed, i) }

        /// 格點值（−1…1）：書脊烘焙的輪廓雜訊（`SpineBakeOutline.Noise`）共用同一個雜湊
        static func lattice(seed: UInt64, _ i: Int64) -> Double {
            var rng = SeededGenerator(seed: seed ^ (UInt64(bitPattern: i) &* 0x9E37_79B9_7F4A_7C15))
            return rng.nextUnit() * 2 - 1
        }

        /// 沿長度 `length`（pt）的雜訊取樣器
        private mutating func profile(length: CGFloat) -> (CGFloat) -> CGFloat {
            let base = offset
            let cells = Int((length / spacing).rounded(.up)) + 2
            offset += Int64(cells) + 997
            let table = (0..<cells).map { lattice(base + Int64($0)) }
            let spacing = spacing
            return { along in
                let t = Double(max(0, along) / spacing)
                let i = min(Int(t), cells - 2), f = t - Double(i)
                let s = f * f * (3 - 2 * f)
                return CGFloat(table[i] * (1 - s) + table[i + 1] * s)
            }
        }

        mutating func circle(center: CGPoint, radius: CGFloat, amplitude: CGFloat, step: CGFloat) -> Path {
            let circumference = 2 * .pi * radius
            let noise = profile(length: circumference)
            let count = max(12, Int((circumference / step).rounded(.up)))
            let points = (0..<count).map { k -> CGPoint in
                let fraction = CGFloat(k) / CGFloat(count)
                let r = radius + amplitude * noise(circumference * fraction)
                let angle = 2 * .pi * fraction
                return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            }
            return Self.polygon(points)
        }

        /// 所有形狀統一繞向（有號面積 > 0）：非零填色時重疊處才是聯集，不會互相抵消成洞
        static func polygon(_ points: [CGPoint]) -> Path {
            let doubled = zip(points, points.dropFirst() + points.prefix(1)).reduce(CGFloat(0)) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
            var path = Path()
            path.addLines(doubled < 0 ? points.reversed() : points)
            path.closeSubpath()
            return path
        }

        /// 沿一條邊、寬 `depth` 的細帶，整條沿法向被雜訊推移 ±amplitude（同小樣的位移貼圖：粗細不變、位置抖動）；
        /// 推到面外的部分會被裁掉，所以貼邊處斷斷續續
        mutating func band(edge: SpineWearShape.Edge, depth: CGFloat, amplitude: CGFloat, size: CGSize, step: CGFloat) -> Path {
            let horizontal = edge == .top || edge == .bottom
            let length = horizontal ? size.width : size.height
            let noise = profile(length: length)
            let count = max(2, Int((length / step).rounded(.up)) + 1)
            var near: [CGPoint] = [], far: [CGPoint] = []
            near.reserveCapacity(count); far.reserveCapacity(count)
            func point(_ along: CGFloat, _ d: CGFloat) -> CGPoint {
                switch edge {
                case .top: CGPoint(x: along, y: d)
                case .bottom: CGPoint(x: along, y: size.height - d)
                case .left: CGPoint(x: d, y: along)
                case .right: CGPoint(x: size.width - d, y: along)
                }
            }
            for k in 0..<count {
                let along = length * CGFloat(k) / CGFloat(count - 1)
                let shift = amplitude * noise(along)
                // 往面外推的部分以 −1 封住（之後被裁掉）；往內推則留出縫
                near.append(point(along, max(-1, shift)))
                far.append(point(along, max(-1, shift + depth)))
            }
            return Self.polygon(near + far.reversed())
        }
    }
}

/// 磨損路徑快取（LRU）：鍵＝專輯、面、尺寸（取到 0.5 pt）。向量路徑，不依螢幕倍率與封面內容
@MainActor
final class SpineWearCache {
    static let shared = SpineWearCache(capacity: 64)

    private struct Key: Hashable {
        let albumID: String
        let surface: SpineWear.Surface
        let width: Int, height: Int
    }

    private let capacity: Int
    private var entries: [Key: SpineWearPaths] = [:]
    /// 最久未用在前
    private var order: [Key] = []
    private(set) var buildCount = 0
    var count: Int { entries.count }

    init(capacity: Int) { self.capacity = capacity }

    func paths(albumID: String, surface: SpineWear.Surface, size: CGSize) -> SpineWearPaths {
        let key = Key(albumID: albumID, surface: surface, width: Int((size.width * 2).rounded()), height: Int((size.height * 2).rounded()))
        if let hit = entries[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return hit
        }
        buildCount += 1
        let built = SpineWear.paths(albumID: albumID, shape: SpineWear.shape(albumID: albumID), surface: surface, size: size)
        entries[key] = built
        order.append(key)
        if order.count > capacity { entries[order.removeFirst()] = nil }
        return built
    }
}

/// 磨損層：起毛帶以纖維遮罩填，再填紙漿色實心；裁在該面內（不溢到鄰盒）
struct SpineWearOverlay: View {
    let albumID: String
    let surface: SpineWear.Surface
    let size: CGSize

    var body: some View {
        let paths = SpineWearCache.shared.paths(albumID: albumID, surface: surface, size: size)
        ZStack {
            paths.halo.fill(ImagePaint(image: Image(decorative: PaperFiber.haloImage, scale: 1)))
            paths.flecks.fill(ImagePaint(image: Image(decorative: PaperFiber.fleckImage, scale: 1)))
            paths.core.fill(Color(red: PaperFiber.pulp.red, green: PaperFiber.pulp.green, blue: PaperFiber.pulp.blue))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Rectangle())
        .allowsHitTesting(false)
    }
}

/// 書脊磨損等級（s6-61-g-perf-wear.md T0）：截圖 fixture 依此分級，可重現
extension SpineWear {
    enum Grade: CaseIterable, Sendable { case new, normal, heavy }

    static let normalScore: CGFloat = 0.6
    static let heavyScore: CGFloat = 1.1

    /// 書脊磨損量＝新舊 × 上下端平均（約 0.18…2.08）
    static func spineScore(_ shape: SpineWearShape) -> CGFloat {
        shape.age * (shape.spineEnds[0] + shape.spineEnds[1]) / 2
    }

    static func grade(score: CGFloat) -> Grade {
        score < normalScore ? .new : score < heavyScore ? .normal : .heavy
    }

    static func grade(albumID: String) -> Grade { grade(score: spineScore(shape(albumID: albumID))) }
}
