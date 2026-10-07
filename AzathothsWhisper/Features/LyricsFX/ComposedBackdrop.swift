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
        case .void, .film:
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
            return [.linearGradient(top: RGB(hex: 0x0E1733), bottom: RGB(hex: 0x3A0F1F)), .lightShafts(xs: xs, width: 0.08, color: gold, opacity: 0.1)]
                + drift(seed: 7, count: 70, color: RGB(hex: 0xF0D47A), size: 1.4, velocity: (3, -14), alpha: 0.35, canvas: size, time: time)
        }
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
        case .void, .snow, .ash:
            return [.vignette(strength: 0.7), .grain(opacity: 0.05, frame: grainFrame, overlay: false)]
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
