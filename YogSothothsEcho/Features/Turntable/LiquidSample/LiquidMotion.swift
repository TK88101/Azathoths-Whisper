#if LIQUID_SAMPLE
import Foundation

// CR-038 液態黑膠小樣（yse-liquid-vinyl-sample.md v0.4 §4.2）：只在 Debug 建置（LIQUID_SAMPLE）。
// 角度單位一律是度；半徑以盤半徑＝1 正規化。

/// 流動強度（推測值，使用者看小樣後定）：T＝彈簧週期，flingGain＝外甩倍率
enum LiquidPreset: String, CaseIterable, Identifiable {
    case subtle, liquid, dramatic

    var id: Self { self }

    var period: Double {
        switch self {
        case .subtle: 0.6
        case .liquid: 1.0
        case .dramatic: 1.6
        }
    }

    var flingGain: Double {
        switch self {
        case .subtle: 0.5
        case .liquid: 1
        case .dramatic: 1.6
        }
    }
}

/// 一幀要交給著色器的液體狀態
struct LiquidFrame: Equatable {
    /// 盤角（連續角，度）
    var discAngle: Double
    /// s＝Θd − Θf（度）：外圈落後量
    var lag: Double
    /// c：外甩量，[0, 1.5]
    var fling: Double
    /// preset 的外甩倍率
    var flingGain: Double
}

/// 可追蹤的染料團：核心半徑隨外甩往外移，高斯寬度向內外各 halfWidth
struct LiquidBlob: Equatable {
    static let halfWidth = 0.05
    static let flingReach = 0.12
    static let radiusRange = 0.51...0.90

    /// 固定種子（不取封面色、不隨機）：8 顆，核心半徑 0.55–0.80
    static let seeds: [LiquidBlob] = [
        LiquidBlob(baseRadius: 0.58, angle: 12, angularSpread: 14, strength: 1.0),
        LiquidBlob(baseRadius: 0.72, angle: 61, angularSpread: 20, strength: 0.85),
        LiquidBlob(baseRadius: 0.64, angle: 105, angularSpread: 11, strength: 0.9),
        LiquidBlob(baseRadius: 0.79, angle: 152, angularSpread: 18, strength: 0.75),
        LiquidBlob(baseRadius: 0.56, angle: 198, angularSpread: 16, strength: 0.95),
        LiquidBlob(baseRadius: 0.69, angle: 243, angularSpread: 12, strength: 0.8),
        LiquidBlob(baseRadius: 0.76, angle: 287, angularSpread: 22, strength: 0.7),
        LiquidBlob(baseRadius: 0.61, angle: 331, angularSpread: 13, strength: 0.9),
    ]

    var baseRadius: Double
    /// 在液體座標中的角位置（度）
    var angle: Double
    /// 角向高斯寬度（度）
    var angularSpread: Double
    var strength: Double

    func radius(fling: Double, gain: Double) -> Double {
        let r = baseRadius + Self.flingReach * fling * gain
        return min(max(r, Self.radiusRange.lowerBound), Self.radiusRange.upperBound)
    }
}

/// 液體角 Θf 以二階彈簧追隨盤角 Θd：Θf'' = ωn²(Θd − Θf) − 2ζωn·Θf'；外甩 c' = (ωf²/ω0² − c)/τc
struct LiquidMotion: Equatable {
    /// ζ：欠阻尼，起轉落後、停轉衝過頭再回 1–2 次
    static let damping = 0.35
    static let referenceSpeed = RecordSpin.degreesPerSecond
    static let flingTimeConstant = 1.5
    static let maxFling = 1.5
    /// 每個積分子步不超過 1/120 s
    static let maxSubstep = 1.0 / 120
    /// 兩次取樣間隔超過這個值（回前景、長卡頓）就不猜，直接重設液體基準
    static let resetGap = 1.0
    /// 收斂判定（之後才允許 TimelineView 暫停）
    static let settledLag = 0.05
    static let settledVelocity = 0.05
    static let settledFling = 0.01

    let preset: LiquidPreset
    private(set) var discAngle: Double
    private(set) var fluidAngle: Double
    private(set) var fluidVelocity = 0.0
    private(set) var fling = 0.0
    private var lastTime: Double

    init(preset: LiquidPreset, discAngle: Double, at now: Double) {
        self.preset = preset
        self.discAngle = discAngle
        fluidAngle = discAngle
        lastTime = now
    }

    var lag: Double { discAngle - fluidAngle }

    var isSettled: Bool {
        abs(lag) < Self.settledLag && abs(fluidVelocity) < Self.settledVelocity && fling < Self.settledFling
    }

    /// 推進到 now 時的盤角（連續角）。時間不前進就忽略；間隔過長就重設基準
    mutating func advance(to newDisc: Double, at now: Double) {
        let elapsed = now - lastTime
        guard elapsed > 0 else { return }
        lastTime = now
        guard elapsed <= Self.resetGap else {
            discAngle = newDisc
            fluidAngle = newDisc
            fluidVelocity = 0
            return
        }
        // 減一點容差：浮點的 2.0000000001 不該變成 3 步（否則 1/60 與 1/120 的子步長不同）
        let steps = max(1, Int((elapsed / Self.maxSubstep - 1e-9).rounded(.up)))
        let h = elapsed / Double(steps)
        let startDisc = discAngle
        for i in 1...steps {
            integrate(h)
            // 盤角在一幀內線性內插；在積分之後推進，子步結束時盤角與液體角是同一時刻
            discAngle = startDisc + (newDisc - startDisc) * Double(i) / Double(steps)
        }
    }

    /// 半隱式 Euler：以子步起點的盤角求加速度，先速度、後位置；外甩用更新後的速度
    private mutating func integrate(_ h: Double) {
        let omegaN = 2 * Double.pi / preset.period
        let acceleration = omegaN * omegaN * (discAngle - fluidAngle) - 2 * Self.damping * omegaN * fluidVelocity
        fluidVelocity += acceleration * h
        fluidAngle += fluidVelocity * h
        let ratio = fluidVelocity / Self.referenceSpeed
        fling += (ratio * ratio - fling) / Self.flingTimeConstant * h
        fling = min(max(fling, 0), Self.maxFling)
    }

    /// Reduce Motion 預覽：液體完全跟盤、不外甩（候選行為，不是無障礙承諾）
    func frame(reduceMotion: Bool) -> LiquidFrame {
        reduceMotion
            ? LiquidFrame(discAngle: discAngle, lag: 0, fling: 0, flingGain: preset.flingGain)
            : LiquidFrame(discAngle: discAngle, lag: lag, fling: fling, flingGain: preset.flingGain)
    }
}

/// 把每 360° 回繞的盤角以最短角差累加成連續角
struct AngleUnwrapper: Equatable {
    private(set) var continuous: Double?
    private var lastRaw = 0.0

    mutating func unwrap(_ raw: Double) -> Double {
        guard let current = continuous else {
            continuous = raw
            lastRaw = raw
            return raw
        }
        var delta = (raw - lastRaw).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta <= -180 { delta += 360 }
        let next = current + delta
        continuous = next
        lastRaw = raw
        return next
    }
}
#endif
