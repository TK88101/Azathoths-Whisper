import Foundation

// canvas-confetti 1.9.2 的物理與參數 1:1 移植（原版 py:884-899 透過 CDN 載入該庫）。
// 保真點：randomPhysics 的取樣範圍、updateFetti 的每幀更新式、alpha=1-progress、
// 以及 py:895-899 的五連發參數（spread/startVelocity/decay/scalar、count 200、origin.y 0.7）。
// 純值型別，無 UI 依賴 —— 可被單測逐幀驅動。

enum ConfettiShape: Sendable {
    case square
    case circle
}

struct ConfettiParticle: Sendable {
    var x: Double
    var y: Double
    var wobble: Double
    var wobbleSpeed: Double
    var velocity: Double
    var angle2D: Double
    var tiltAngle: Double
    var color: ConfettiColor
    var shape: ConfettiShape
    var tick: Int
    var totalTicks: Int
    var decay: Double
    var drift: Double
    var gravity: Double
    var scalar: Double
    var random: Double
    var tiltSin: Double = 0
    var tiltCos: Double = 0
    var wobbleX: Double = 0
    var wobbleY: Double = 0
    let ovalScalar: Double = 0.6

    var isAlive: Bool { tick < totalTicks }
    /// 繪製用透明度：canvas-confetti 的 1 - progress
    var alpha: Double { max(0, 1 - Double(tick) / Double(totalTicks)) }

    /// updateFetti 的單幀推進（不含繪製）
    mutating func step<G: RandomNumberGenerator>(using generator: inout G) {
        x += cos(angle2D) * velocity + drift
        y += sin(angle2D) * velocity + gravity
        velocity *= decay

        wobble += wobbleSpeed
        wobbleX = x + (10 * scalar) * cos(wobble)
        wobbleY = y + (10 * scalar) * sin(wobble)
        tiltAngle += 0.1
        tiltSin = sin(tiltAngle)
        tiltCos = cos(tiltAngle)
        random = Double.random(in: 0..<1, using: &generator) + 2

        tick += 1
    }

    /// 方形碎片的四個頂點（canvas-confetti 的 moveTo/lineTo 序列）
    var quad: [CGPoint] {
        let x1 = x + random * tiltCos
        let y1 = y + random * tiltSin
        let x2 = wobbleX + random * tiltCos
        let y2 = wobbleY + random * tiltSin
        return [
            CGPoint(x: x.rounded(.down), y: y.rounded(.down)),
            CGPoint(x: wobbleX.rounded(.down), y: y1.rounded(.down)),
            CGPoint(x: x2.rounded(.down), y: y2.rounded(.down)),
            CGPoint(x: x1.rounded(.down), y: wobbleY.rounded(.down)),
        ]
    }

    /// 圓形碎片的橢圓幾何
    var oval: (center: CGPoint, radii: CGSize, rotation: Double) {
        let x1 = x + random * tiltCos
        let y1 = y + random * tiltSin
        let x2 = wobbleX + random * tiltCos
        let y2 = wobbleY + random * tiltSin
        return (
            CGPoint(x: x, y: y),
            CGSize(width: abs(x2 - x1) * ovalScalar, height: abs(y2 - y1) * ovalScalar),
            Double.pi / 10 * wobble
        )
    }
}

struct ConfettiColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// canvas-confetti 預設色盤
    static let palette: [ConfettiColor] = [
        ConfettiColor(hex: 0x26CCFF),
        ConfettiColor(hex: 0xA25AFD),
        ConfettiColor(hex: 0xFF5E7E),
        ConfettiColor(hex: 0x88FF5A),
        ConfettiColor(hex: 0xFCFF42),
        ConfettiColor(hex: 0xFFA62D),
        ConfettiColor(hex: 0xFF36FF),
    ]
}

/// 彩帶的時間常數（單一來源）：`ConfettiView` 的步進與「寫入成功後幾秒升回 Cover Flow」都由此推導（計劃 D5）
enum ConfettiTiming {
    /// 每步間隔（≈ requestAnimationFrame）
    static let frameInterval: Duration = .milliseconds(16)
    /// 單發粒子壽命（canvas-confetti 預設 200 幀）
    static let ticks = 200
    /// 名義壽命 ≈ 3.2s（實際略長：`Task.sleep` 不與螢幕刷新同步）
    static let lifetime: Duration = frameInterval * ticks
}

/// 單次 confetti() 呼叫的參數（未指定者取 canvas-confetti 預設）
struct ConfettiBurst: Sendable {
    var particleCount: Int
    var angle: Double = 90
    var spread: Double = 45
    var startVelocity: Double = 45
    var decay: Double = 0.9
    var gravity: Double = 1
    var drift: Double = 0
    var ticks: Int = ConfettiTiming.ticks
    var scalar: Double = 1
    var originX: Double = 0.5
    var originY: Double = 0.5

    /// py:884-899 的五連發：count 200 按比例分配、origin.y 0.7
    static let saveCelebration: [ConfettiBurst] = {
        let count = 200.0
        let originY = 0.7
        func burst(_ ratio: Double, spread: Double, startVelocity: Double = 45,
                   decay: Double = 0.9, scalar: Double = 1) -> ConfettiBurst {
            ConfettiBurst(
                particleCount: Int((count * ratio).rounded(.down)),
                spread: spread,
                startVelocity: startVelocity,
                decay: decay,
                scalar: scalar,
                originY: originY
            )
        }
        return [
            burst(0.25, spread: 26, startVelocity: 55),
            burst(0.20, spread: 60),
            burst(0.35, spread: 100, decay: 0.91, scalar: 0.8),
            burst(0.10, spread: 120, startVelocity: 25, decay: 0.92, scalar: 1.2),
            burst(0.10, spread: 120, startVelocity: 45),
        ]
    }()
}

enum ConfettiFactory {
    /// randomPhysics：逐項對應 canvas-confetti 的取樣式
    static func makeParticles<G: RandomNumberGenerator>(
        burst: ConfettiBurst,
        canvasSize: CGSize,
        using generator: inout G
    ) -> [ConfettiParticle] {
        let radAngle = burst.angle * .pi / 180
        let radSpread = burst.spread * .pi / 180
        let startX = burst.originX * canvasSize.width
        let startY = burst.originY * canvasSize.height
        let shapes: [ConfettiShape] = [.square, .circle]

        return (0..<burst.particleCount).map { index in
            ConfettiParticle(
                x: startX,
                y: startY,
                wobble: Double.random(in: 0..<1, using: &generator) * 10,
                wobbleSpeed: min(0.11, Double.random(in: 0..<1, using: &generator) * 0.1 + 0.05),
                velocity: burst.startVelocity * 0.5 + Double.random(in: 0..<1, using: &generator) * burst.startVelocity,
                angle2D: -radAngle + (0.5 * radSpread - Double.random(in: 0..<1, using: &generator) * radSpread),
                tiltAngle: (Double.random(in: 0..<1, using: &generator) * 0.5 + 0.25) * .pi,
                // canvas-confetti 以 temp-- 倒序取色，此處以 index 取模，分佈等價
                color: ConfettiColor.palette[index % ConfettiColor.palette.count],
                shape: shapes[min(shapes.count - 1, Int(Double.random(in: 0..<1, using: &generator) * Double(shapes.count)))],
                tick: 0,
                totalTicks: burst.ticks,
                decay: burst.decay,
                drift: burst.drift,
                gravity: burst.gravity * 3,
                scalar: burst.scalar,
                random: Double.random(in: 0..<1, using: &generator) + 2
            )
        }
    }
}
