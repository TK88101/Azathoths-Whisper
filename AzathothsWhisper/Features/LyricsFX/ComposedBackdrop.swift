import CoreGraphics
import Foundation

/// 背景元件 → 背景層（移植原型組合模式的 draw，html:1004-1031；顆粒改以平鋪噪點近似原型的逐點白噪）
enum ComposedBackdrop {
    /// 原型 TONE.density 0.5 推得的粒子數倍率
    static let density = 0.9
    private static let gold = RGB(hex: 0xC9A227)

    /// 字之下
    static func back(_ backdrop: BackdropKind, palette: FXPalette, size: CGSize, time: Double) -> [LayerDraw] {
        switch backdrop {
        case .void, .film, .flat:
            return []
        case .snow:
            return drift(seed: 11, count: 160, color: RGB(hex: 0xC9D1D9), size: 1.3, velocity: (-10, 22), alpha: 0.35, canvas: size, time: time)
        case .ash:
            return drift(seed: 5, count: 90, color: palette.dim, size: 1.6, velocity: (6, 10), alpha: 0.45, canvas: size, time: time)
        case .crimsonFog:
            let glow = LayerDraw.radialGlow(center: CGPoint(x: 0.5, y: 0.6), radius: 0.75, stops: [
                GlowStop(location: 0, color: RGB(hex: 0x780012), opacity: 0.35),
                GlowStop(location: 0.6, color: RGB(hex: 0x3C000A), opacity: 0.25),
                GlowStop(location: 1, color: RGB(hex: 0x000000), opacity: 0),
            ])
            return [glow] + drift(seed: 13, count: 60, color: RGB(hex: 0x5A0A14), size: 3, velocity: (6, -4), alpha: 0.35, canvas: size, time: time)
        case .shafts:
            let xs = (0..<4).map { CGFloat((Double($0) * 0.27 + time * 0.015).truncatingRemainder(dividingBy: 1)) }
            return [vertical(top: 0x0E1733, bottom: 0x3A0F1F), .lightShafts(xs: xs, width: 0.08, color: gold, opacity: 0.1)]
                + drift(seed: 7, count: 70, color: RGB(hex: 0xF0D47A), size: 1.4, velocity: (3, -14), alpha: 0.35, canvas: size, time: time)
        // B2 批 1（原型組合模式 draw 的 B2 段；只用光與質感，不畫結構性裝飾，P5）
        case .ampGlow:
            return [glow(0.5, -0.15, radius: 1.15 * aspect(size), 0xFFB05A, 0.26), band(CGPoint(x: 0.5, y: 0.7), CGPoint(x: 0.5, y: 1), 0xC82814, from: 0, to: 0.16)]
        case .spot:
            return [glow(0.5 + CGFloat(0.06 * sin(time * 0.35)), 0.46, radius: 0.75 * aspect(size), 0xFFFFFF, 0.16, mid: (0.55, 0.04))]
        case .smokeHaze:
            return (0..<3).map { index in
                let i = Double(index)
                return glow(CGFloat(0.25 + 0.25 * i + 0.05 * sin(time * 0.12 + i * 2.1)), CGFloat(0.55 + 0.1 * cos(time * 0.09 + i)), radius: 0.42, 0xD2A05F, 0.12)
            }
        case .prism:
            let hues: [UInt32] = [0xF04251, 0xF0C442, 0x42F07C, 0x42A7F0, 0x9942F0]
            return hues.enumerated().map { index, hue in
                let x = CGFloat((Double(index) * 0.21 + time * 0.008).truncatingRemainder(dividingBy: 1.05) - 0.05)
                return band(CGPoint(x: x, y: 0), CGPoint(x: x + 0.16, y: 1), hue, from: 0, to: 0, mid: 0.11)
            }
        case .stars:
            return [band(CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1), 0x3C468C, from: 0.22, to: 0)]
                + drift(seed: 31, count: 110, color: RGB(hex: 0xFFFFFF), size: 1.6, velocity: (1.5, 0), alpha: 0.7, canvas: size, time: time)
        case .halftone:
            return [.halftone(step: halftoneStep, color: palette.dim, opacity: 0.22)]
        case .tapeLeak:
            let k = 0.7 + 0.3 * sin(time * 0.5)
            return [band(CGPoint(x: 0, y: 0.5), CGPoint(x: 0.38, y: 0.5), 0xFF7828, from: 0.3 * k, to: 0),
                    band(CGPoint(x: 1, y: 0.5), CGPoint(x: 0.8, y: 0.5), 0xFF3C5A, from: 0.14 * k, to: 0)]
        case .embers:
            return [band(CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.5, y: 1), 0xFF781E, from: 0, to: 0.25)] + embers(size: size, time: time)
        case .haze:
            return [glow(0.5, 0.5, radius: 0.6, 0xFFB7C5, 0.18)]
                + drift(seed: 4, count: 50, color: palette.fg, size: 2, velocity: (4, -4), alpha: 0.25, canvas: size, time: time)
        case .paper:
            return [.hairlines(spacing: 6, color: RGB(hex: 0x000000), opacity: 0.05)]
        case .sunset:
            return [band(CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1), 0xFFD9A8, from: 0.9, to: 0.9, endColor: 0xFF9A7A)]
        // B2 批 2（原型組合模式 draw 的 B2 批 2 段；同樣只用光與質感）
        case .xerox:
            return [xeroxStreaks(size: size, color: palette.fg)]
        case .gig:
            return [glow(0.5, 1.15, radius: 1.0 * aspect(size), 0xE11E19, 0.34), glow(0.5, -0.2, radius: 0.9 * aspect(size), 0xFFFFFF, 0.07)]
        case .checker:
            return [.rects(checkerSquares(size: size), palette.dim, opacity: 0.5)]
        case .bokeh:
            return bokeh(size: size, color: palette.acc, time: time)
        case .skyGrad:
            return [band(CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1), 0xFFFFFF, from: 0.14, to: 0.14, endColor: 0x000000)]
        }
    }

    /// 影印的碳粉橫紋：16 道滿寬細條、位置固定（原型每道透明度 0.03–0.07，這裡取中間值一次填）
    static func xeroxStreaks(size: CGSize, color: RGB) -> LayerDraw {
        var random = SplitMix64(seed: 7)
        let streaks = (0..<16).map { _ in
            let y = CGFloat(random.unit()) * size.height
            return CGRect(x: 0, y: y, width: size.width, height: 1 + CGFloat(random.unit()) * 3)
        }
        return .rects(streaks, color, opacity: 0.05)
    }

    /// 底緣兩列黑白格：格邊＝畫布高的 5%，兩列錯開
    static func checkerSquares(size: CGSize) -> [CGRect] {
        let side = size.height * 0.05
        guard side > 0 else { return [] }
        let columns = Int((size.width / side).rounded(.up))
        return (0..<2).flatMap { row in
            (0..<columns).filter { column in (column + row).isMultiple(of: 2) }.map { column in
                CGRect(x: CGFloat(column) * side, y: size.height - CGFloat(row + 1) * side, width: side, height: side)
            }
        }
    }

    /// 失焦光斑：14 個配色強調色的柔光圓，緩慢右移
    static func bokeh(size: CGSize, color: RGB, time: Double) -> [LayerDraw] {
        var random = SplitMix64(seed: 41)
        return (0..<14).map { _ in
            let start = random.unit(), speed = 3 + random.unit() * 5
            let y = CGFloat(random.unit()), radius = CGFloat(0.05 + random.unit() * 0.08) * aspect(size)
            let opacity = 0.07 + random.unit() * 0.07
            let travelled = size.width > 0 ? time * speed / Double(size.width) : 0
            let x = CGFloat((start + travelled).truncatingRemainder(dividingBy: 1.1) - 0.05)
            return .radialGlow(center: CGPoint(x: x, y: y), radius: radius, stops: [
                GlowStop(location: 0, color: color, opacity: opacity), GlowStop(location: 1, color: RGB(hex: 0x000000), opacity: 0),
            ])
        }
    }

    private static func aspect(_ size: CGSize) -> CGFloat { size.width > 0 ? size.height / size.width : 0.6 }

    /// 由上到下的不透明兩色漸層
    private static func vertical(top: UInt32, bottom: UInt32) -> LayerDraw {
        band(CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1), top, from: 1, to: 1, endColor: bottom)
    }

    /// 徑向光暈：中心色漸淡到透明（座標與半徑以畫布寬為單位）
    private static func glow(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, _ color: UInt32, _ opacity: Double, mid: (CGFloat, Double)? = nil) -> LayerDraw {
        var stops = [GlowStop(location: 0, color: RGB(hex: color), opacity: opacity)]
        if let mid { stops.append(GlowStop(location: mid.0, color: RGB(hex: color), opacity: mid.1)) }
        stops.append(GlowStop(location: 1, color: RGB(hex: 0x000000), opacity: 0))
        return .radialGlow(center: CGPoint(x: x, y: y), radius: radius, stops: stops)
    }

    /// 沿 start→end 的漸層帶；`endColor` 省略＝同色只變透明度
    private static func band(
        _ start: CGPoint, _ end: CGPoint, _ color: UInt32, from: Double, to: Double, mid: Double? = nil, endColor: UInt32? = nil
    ) -> LayerDraw {
        let first = RGB(hex: color), last = RGB(hex: endColor ?? color)
        var stops = [GlowStop(location: 0, color: first, opacity: from)]
        if let mid { stops.append(GlowStop(location: 0.5, color: first, opacity: mid)) }
        stops.append(GlowStop(location: 1, color: last, opacity: to))
        return .axialGlow(start: start, end: end, stops: stops)
    }

    /// 半調網點的格距（點）
    static let halftoneStep: CGFloat = 14

    /// 半調網點：14 點一格、奇偶列錯開，越往下越大（原型 halftone）
    static func halftoneDots(size: CGSize, step: CGFloat = halftoneStep) -> [Particle] {
        var dots: [Particle] = []
        for (row, y) in stride(from: step / 2, to: size.height, by: step).enumerated() {
            let k = min(max(y / max(size.height, 1) * 1.15 - 0.25, 0), 1)
            guard k > 0 else { continue }
            for x in stride(from: (row.isMultiple(of: 2) ? 0 : step / 2) + step / 2, to: size.width, by: step) {
                dots.append(Particle(x: x, y: y, size: step * 0.42 * k))
            }
        }
        return dots
    }

    /// 火星（原型 `embers`）：往上飄、左右擺，明滅；單一暖橘色、依透明度分桶
    static func embers(size: CGSize, time: Double) -> [LayerDraw] {
        var random = SplitMix64(seed: 21)
        let particles: [(Particle, Double)] = (0..<70).map { index in
            let x = CGFloat(random.unit()) * size.width + CGFloat(sin(time * 0.7 + random.unit() * 6) * 20)
            let y = wrap(CGFloat(random.unit()) * size.height - CGFloat(time) * CGFloat(15 + random.unit() * 30), size.height)
            let side = CGFloat(1 + random.unit() * 2)
            let alpha = (0.3 + 0.7 * random.unit()) * (0.4 + 0.6 * sin(time * 3 + Double(index)))
            return (Particle(x: x, y: y, size: side), max(alpha, 0))
        }
        return particleLayers(particles, color: RGB(hex: 0xFFA028))
    }

    /// 字之上：暈影、顆粒、底片刮痕與閃爍
    static func front(_ backdrop: BackdropKind, size: CGSize, time: Double) -> [LayerDraw] {
        let grainFrame = Int(time * 12)
        switch backdrop {
        case .shafts:
            return []
        case .film:
            return [.vignette(strength: 0.95), .grain(opacity: 0.42, frame: Int(time * 18), overlay: true)] + filmArtefacts(size: size, time: time)
        case .crimsonFog:
            return [.vignette(strength: 0.95), .grain(opacity: 0.05, frame: grainFrame, overlay: false)]
        case .void, .snow, .ash, .ampGlow, .spot, .smokeHaze, .prism, .stars, .gig, .bokeh:
            return [.vignette(strength: 0.7), .grain(opacity: 0.05, frame: grainFrame, overlay: false)]
        case .paper:
            return [.grain(opacity: 0.1, frame: grainFrame, overlay: false)]
        case .embers, .haze, .tapeLeak:
            return [.grain(opacity: 0.05, frame: grainFrame, overlay: false)]
        case .xerox:
            return [.grain(opacity: 0.16, frame: grainFrame, overlay: false)]
        case .halftone, .sunset, .flat, .checker, .skyGrad:
            return []
        }
    }

    /// 漂浮粒子（原型 `drift`，html:344-347）：每顆有自己的速度與明滅相位；依透明度分桶成層
    static func drift(
        seed: UInt64, count: Int, color: RGB, size: CGFloat, velocity: (CGFloat, CGFloat), alpha: Double, canvas: CGSize, time: Double
    ) -> [LayerDraw] {
        var random = SplitMix64(seed: seed)
        let total = Int((Double(count) * density).rounded())
        var particles: [(Particle, Double)] = []
        particles.reserveCapacity(total)
        for _ in 0..<total {
            let originX = CGFloat(random.unit()) * canvas.width
            let originY = CGFloat(random.unit()) * canvas.height
            let phase = random.unit() * 2 * .pi
            let side = size * CGFloat(0.5 + random.unit())
            let x = wrap(originX + CGFloat(time) * velocity.0 * CGFloat(0.6 + random.unit() * 0.8), canvas.width)
            let y = wrap(originY + CGFloat(time) * velocity.1 * CGFloat(0.6 + random.unit() * 0.8), canvas.height)
            particles.append((Particle(x: x, y: y, size: side), alpha * (0.5 + 0.5 * sin(time * 1.3 + phase))))
        }
        return particleLayers(particles, color: color)
    }

    /// 粒子依量化透明度分桶，一桶一層（一次填色）；量化為 0 的不畫。冰屑與漂浮粒子共用
    static func particleLayers(_ particles: some Sequence<(Particle, Double)>, color: RGB) -> [LayerDraw] {
        let buckets = Dictionary(grouping: particles) { LyricsFXCanvas.opacityLevel($0.1) }
        return buckets.keys.sorted().filter { $0 > 0 }.map { level in
            .particles(buckets[level]!.map(\.0), color, opacity: LyricsFXCanvas.opacity(ofLevel: level))
        }
    }

    /// 底片瑕疵（原型 `filmArtefacts`，html:355-358）：每 1/12 s 一組，35% 機率 1–2 道刮痕；8% 機率的毛髮不畫；亮度閃爍只變暗
    static func filmArtefacts(size: CGSize, time: Double) -> [LayerDraw] {
        let group = UInt64(max(time * 12, 0))
        var random = SplitMix64(seed: group &* 131 &+ 17)
        var layers: [LayerDraw] = []
        if random.unit() < 0.35 {
            let count = 1 + Int(random.unit() * 2)
            layers.append(.scratches(xs: (0..<count).map { _ in CGFloat(random.unit()) * size.width }, opacity: 0.22))
        }
        let flicker = (random.unit() - 0.5) * 0.08
        if flicker > 0 { layers.append(.fill(RGB(hex: 0x000000), opacity: flicker)) }
        return layers
    }

    private static func wrap(_ value: CGFloat, _ length: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: length)
        return remainder < 0 ? remainder + length : remainder
    }
}
