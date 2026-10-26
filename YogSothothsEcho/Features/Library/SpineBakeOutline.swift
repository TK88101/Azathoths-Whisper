import CoreGraphics
import SwiftUI

/// 書脊的不規則剪影與泛白磨損（s6-61-g-perf-wear.md §5.1；Codex wear_r1 收斂）。
/// 座標＝左側盒方向的書脊本地 pt（折邊在 trailing）；u＝面高／764。全部由專輯 ID 的種子決定
enum SpineBakeOutline {
    /// 泛白露紙色：偏暖、低飽和的灰米色（不是純白）
    static let paper = (red: 0.80, green: 0.76, blue: 0.69)
    /// 長邊內縮上限（pt，u＝1）
    static let maxEdgeInset: CGFloat = 2.4
    /// 最小起伏（pt，u＝1）
    static let minimumWobble: CGFloat = 0.8

    struct Profile {
        let ends: [CGFloat]
        let edgeAmplitude: CGFloat
        let cornerRadius: CGFloat
        let strength: CGFloat
        let u: CGFloat
    }

    /// 原始磨損量的範圍（`SpineWear.spineScore`＝新舊 × 上下端平均，由產生器的取樣範圍推出）與實際使用的「普通」區間
    static let rawScoreRange: ClosedRange<CGFloat> =
        CGFloat(SpineWear.ageRange.lowerBound * SpineWear.spineEndRange.lowerBound)...CGFloat(SpineWear.ageRange.upperBound * SpineWear.spineEndRange.upperBound)
    static let normalBand: ClosedRange<CGFloat> = 0.65...1.05

    /// 使用者 2026-10-23（看 T0 小樣）：磨損程度一律「普通」——原始磨損量線性壓進普通區間，各專輯的相對輕重保留
    static func effectiveScore(_ shape: SpineWearShape) -> CGFloat {
        let raw = SpineWear.spineScore(shape)
        let t = (raw - rawScoreRange.lowerBound) / (rawScoreRange.upperBound - rawScoreRange.lowerBound)
        return normalBand.lowerBound + min(1, max(0, t)) * (normalBand.upperBound - normalBand.lowerBound)
    }

    static func profile(_ shape: SpineWearShape, u: CGFloat) -> Profile {
        let score = effectiveScore(shape), k = score / max(0.01, SpineWear.spineScore(shape))
        let strength = min(1.3, max(0.3, score / 1.2))
        let ends = shape.spineEnds.map { min(2.5, max(0.5, 1.1 * $0 * shape.age * k)) * u }
        return Profile(ends: ends, edgeAmplitude: (0.45 + 0.55 * strength) * u, cornerRadius: (1.2 + 2.4 * strength) * u,
                       strength: strength, u: u)
    }

    /// 1D value noise（−1…1）：格點值同 `SpineWear.Jag.lattice`、格點間 smoothstep；逐點取樣（書脊只有數十個點）
    struct Noise {
        let seed: UInt64
        let spacing: CGFloat

        func callAsFunction(_ t: CGFloat) -> CGFloat {
            let x = max(0, t) / spacing
            let i = Int64(x.rounded(.down)), f = x - CGFloat(i)
            let s = f * f * (3 - 2 * f)
            return CGFloat(SpineWear.Jag.lattice(seed: seed, i)) * (1 - s) + CGFloat(SpineWear.Jag.lattice(seed: seed, i + 1)) * s
        }
    }

    /// 上下端內縮（pt）：粗細兩層雜訊，沿寬度至少起伏數次
    static func endInset(_ p: Profile, end: Int, x: CGFloat, width: CGFloat, seed: UInt64) -> CGFloat {
        let coarse = Noise(seed: seed ^ (0xE0 + UInt64(end)), spacing: width / 5)
        let fine = Noise(seed: seed ^ (0xF0 + UInt64(end)), spacing: width / 12)
        let wave = 0.5 + 0.35 * coarse(x) + 0.15 * fine(x)
        // 再新的封套也不是直角：至少約 0.8 pt 的起伏（實機 2× 下 ≥ 1.5 px）
        let jitter = Noise(seed: seed ^ (0xD0 + UInt64(end)), spacing: width / 10)
        return p.ends[end] * (0.3 + 0.9 * wave) + 1.25 * minimumWobble * p.u * (0.5 + 0.5 * jitter(x))
    }

    /// 長邊內縮（pt）：微凹凸＋淺缺口，夾在上限內
    static func edgeInset(_ p: Profile, left: Bool, y: CGFloat, shape: SpineWearShape, size: CGSize, seed: UInt64) -> CGFloat {
        let u = p.u
        let noise = Noise(seed: seed ^ (left ? 0xA1 : 0xA2), spacing: 9 * u)
        // 長邊的凹凸比端面細：最小幅度取 1.4 倍（2× 下約 2 px 的起伏才看得出不是直線）
        var inset = max(p.edgeAmplitude, 1.4 * minimumWobble * u) * (0.5 + 0.5 * noise(y))
        for nick in shape.spineNicks where (nick.edge == .left) == left {
            let center = nick.position * size.height, radius = nick.radius * u * shape.age
            let d = abs(y - center)
            if d < radius { inset += 0.9 * u * (1 - d / radius) * (1 - d / radius) }
        }
        return min(inset, maxEdgeInset * u)
    }

    /// 剪影：四條雜訊曲線各自裁切（交集），四角再以抖動扇形挖缺
    static func clip(_ canvas: SpineBake.Canvas, albumID: String, shape: SpineWearShape) {
        let ctx = canvas.ctx, size = canvas.size
        let u = size.height / SpineCarouselMetrics.referenceCover, seed = SpineWear.seed(albumID: albumID)
        let p = profile(shape, u: u), step: CGFloat = 0.25
        let xs = Array(stride(from: 0, through: size.width, by: step)) + [size.width]
        let ys = Array(stride(from: 0, through: size.height, by: step)) + [size.height]
        func addPolygon(_ points: [CGPoint]) {
            ctx.addLines(between: points)
            ctx.closePath()
            ctx.clip()
        }
        addPolygon(xs.map { CGPoint(x: $0, y: endInset(p, end: 0, x: $0, width: size.width, seed: seed)) }
            + [CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)])
        addPolygon(xs.map { CGPoint(x: $0, y: size.height - endInset(p, end: 1, x: $0, width: size.width, seed: seed)) }
            + [CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: 0)])
        addPolygon(ys.map { CGPoint(x: edgeInset(p, left: true, y: $0, shape: shape, size: size, seed: seed), y: $0) }
            + [CGPoint(x: size.width, y: size.height), CGPoint(x: size.width, y: 0)])
        addPolygon(ys.map { CGPoint(x: size.width - edgeInset(p, left: false, y: $0, shape: shape, size: size, seed: seed), y: $0) }
            + [CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0)])
        // 四角：整面＋抖動扇形，奇偶規則＝挖掉扇形
        for chip in cornerChips(albumID: albumID, shape: shape, size: size) {
            ctx.addRect(CGRect(origin: .zero, size: size))
            ctx.addPath(chip.cgPath)
            ctx.clip(using: .evenOdd)
        }
    }

    /// 四角缺口（左側盒書脊座標；順序：左上、右上＝折邊上角、左下、右下＝折邊下角）。圓心在盒子的角上：
    /// 折邊兩角的缺口越過折邊就是正面的折邊角——正面遮罩（`FrontFoldMask`）用同一組路徑，兩面接齊（G2 接縫）
    static func cornerChips(albumID: String, shape: SpineWearShape, size: CGSize) -> [Path] {
        let u = size.height / SpineCarouselMetrics.referenceCover
        let p = profile(shape, u: u)
        var jag = SpineWear.Jag(seed: SpineWear.seed(albumID: albumID) ^ 0xC0, spacing: 1.2 * u)
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        return corners.enumerated().map { index, corner in
            let radius = p.cornerRadius * (0.6 + 0.8 * CGFloat(shape.corners[index] / 1.5))
            return jag.circle(center: corner, radius: radius, amplitude: 0.35 * radius, step: 0.4 * u)
        }
    }

    /// 泛白：上下端露紙（纖維狀）＋輪廓內的淡露紙帶＋沿邊成簇的短擦痕＋角落扇形擦痕＋極淡 screen 纖維
    static func drawWear(_ canvas: SpineBake.Canvas, albumID: String, shape: SpineWearShape) {
        let ctx = canvas.ctx, size = canvas.size
        let u = size.height / SpineCarouselMetrics.referenceCover, seed = SpineWear.seed(albumID: albumID)
        let p = profile(shape, u: u)
        var rng = SeededGenerator(seed: seed ^ 0x5C)
        func uniform(_ range: ClosedRange<CGFloat>) -> CGFloat { range.lowerBound + CGFloat(rng.nextUnit()) * (range.upperBound - range.lowerBound) }
        let rect = CGRect(origin: .zero, size: size)
        // 上下端：實心淡露紙＋纖維露紙，深度＝端內縮最大值的約 2 倍
        for end in 0..<2 {
            let depth = 2 * p.ends[end] + 1.5 * u
            let band = end == 0 ? CGRect(x: 0, y: 0, width: size.width, height: depth)
                : CGRect(x: 0, y: size.height - depth, width: size.width, height: depth)
            fill(ctx, band, alpha: 0.18 + 0.12 * p.strength)
            TextureDrawing.tile(ctx, PaperFiber.haloImage, in: band, clip: CGPath(rect: band, transform: nil), alpha: min(0.95, 0.55 + 0.3 * p.strength))
            let edge = end == 0 ? CGRect(x: 0, y: 0, width: size.width, height: p.ends[end] + 0.6 * u)
                : CGRect(x: 0, y: size.height - p.ends[end] - 0.6 * u, width: size.width, height: p.ends[end] + 0.6 * u)
            fill(ctx, edge, alpha: 0.30 + 0.15 * p.strength)
        }
        // 兩長邊：輪廓內的淡露紙帶，分段變化透明度（成簇、不均勻）
        let edgeBand = maxEdgeInset * u * 0.5 + 0.9 * u
        let segment = 6 * u
        for left in [true, false] {
            var y: CGFloat = 0
            while y < size.height {
                let length = uniform(segment...(3 * segment))
                let alpha = uniform(0.04...(0.12 + 0.2 * p.strength))
                let x = left ? 0 : size.width - edgeBand - p.edgeAmplitude
                fill(ctx, CGRect(x: x, y: y, width: edgeBand + p.edgeAmplitude, height: length), alpha: alpha)
                y += length
            }
        }
        // 沿邊成簇的短擦痕（與邊平行）
        let clusters = 2 + Int(4 * p.strength)
        ctx.setLineCap(.round)
        for _ in 0..<clusters {
            let left = rng.next() % 2 == 0, center = uniform(0.05...0.95) * size.height
            for _ in 0..<(3 + Int(rng.next() % 5)) {
                let y = center + uniform(-10...10) * u, length = uniform(2...7) * u
                let inset = uniform(0.3...1.5) * u + p.edgeAmplitude * 0.5
                let x = left ? inset : size.width - inset
                stroke(ctx, from: CGPoint(x: x, y: y), to: CGPoint(x: x + uniform(-0.3...0.3) * u, y: y + length),
                       width: uniform(0.35...0.7) * u, alpha: uniform(0.2...0.5))
            }
        }
        // 角落扇形擦痕：自角向內
        let corners = [(CGPoint.zero, 0.0), (CGPoint(x: size.width, y: 0), Double.pi / 2),
                       (CGPoint(x: 0, y: size.height), -Double.pi / 2), (CGPoint(x: size.width, y: size.height), Double.pi)]
        for (corner, base) in corners {
            for _ in 0..<(3 + Int(rng.next() % 4)) {
                let angle = base + Double(uniform(0.1...1.45)), length = uniform(1.5...5) * u * (0.6 + 0.4 * p.strength)
                let start = CGPoint(x: corner.x + (corner.x == 0 ? 1 : -1) * p.cornerRadius * 0.4,
                                    y: corner.y + (corner.y == 0 ? 1 : -1) * p.cornerRadius * 0.4)
                let dx = CGFloat(cos(angle)) * length * (corner.x == 0 ? 1 : -1)
                let dy = CGFloat(sin(abs(angle.truncatingRemainder(dividingBy: .pi)))) * length * (corner.y == 0 ? 1 : -1)
                stroke(ctx, from: start, to: CGPoint(x: start.x + dx, y: start.y + dy), width: uniform(0.3...0.6) * u,
                       alpha: uniform(0.25...0.45))
            }
        }
        // 極淡 screen 微亮纖維（只作輔助）
        TextureDrawing.tile(ctx, PaperFiber.edgeLightImage, in: rect, alpha: 0.03 + 0.05 * p.strength, blend: .screen)
    }

    private static func fill(_ ctx: CGContext, _ rect: CGRect, alpha: CGFloat) {
        ctx.setFillColor(red: paper.red, green: paper.green, blue: paper.blue, alpha: alpha)
        ctx.fill(rect)
    }

    private static func stroke(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat, alpha: CGFloat) {
        ctx.setStrokeColor(red: paper.red, green: paper.green, blue: paper.blue, alpha: alpha)
        ctx.setLineWidth(width)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }
}
