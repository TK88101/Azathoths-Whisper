#if LIQUID_SAMPLE
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-038 L-T1（yse-liquid-vinyl-sample.md v0.4 §4.2）：二階彈簧液體角＋外甩低通＋盤角展開器

struct LiquidMotionTests {
    private static let step = 1.0 / 120
    private static let omega = RecordSpin.degreesPerSecond

    /// 以固定 dt 跑一段等速（或靜止）盤角，回傳最後狀態；每步呼叫 inspect
    private static func run(
        _ motion: inout LiquidMotion, disc: inout Double, now: inout Double,
        speed: Double, seconds: Double, dt: Double = step, inspect: (LiquidMotion) -> Void = { _ in }
    ) {
        let steps = Int((seconds / dt).rounded())
        for _ in 0..<steps {
            now += dt
            disc += speed * dt
            motion.advance(to: disc, at: now)
            inspect(motion)
        }
    }

    @Test(arguments: LiquidPreset.allCases)
    func stillDiscStaysAtRest(preset: LiquidPreset) {
        var motion = LiquidMotion(preset: preset, discAngle: 42, at: 0)
        var disc = 42.0, now = 0.0
        Self.run(&motion, disc: &disc, now: &now, speed: 0, seconds: 3)
        #expect(motion.lag == 0)
        #expect(motion.fluidVelocity == 0)
        #expect(motion.fling == 0)
    }

    /// 斜坡輸入的二階系統穩態落後＝ζωT/π
    @Test(arguments: LiquidPreset.allCases)
    func steadySpinLagMatchesClosedForm(preset: LiquidPreset) {
        var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
        var disc = 0.0, now = 0.0
        Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 5 * preset.period)
        let expected = LiquidMotion.damping * Self.omega * preset.period / .pi
        #expect(abs(motion.lag - expected) < 0.1, "lag \(motion.lag) expected \(expected)")
    }

    /// 停轉：液體衝過頭（s 過零）、6 s 內回到 |s| < 0.5°；c 單調降、全程 [0, 1.5]
    @Test(arguments: LiquidPreset.allCases)
    func stopOvershootsThenSettles(preset: LiquidPreset) {
        var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
        var disc = 0.0, now = 0.0
        var flingInRange = true
        Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 20) {
            flingInRange = flingInRange && (0...LiquidMotion.maxFling).contains($0.fling)
        }
        let lagAtStop = motion.lag
        #expect(lagAtStop > 0)
        var crossedZero = false
        var flingMonotone = true
        var previousFling = motion.fling
        var frame = 0
        // 停轉前 c 從下方逼近 1（差 e^(−t/τc)）；停轉後第一幀的加速度仍取自穩態、目標仍是 1，
        // 允許這一幀上升不到 1e-6，其後每幀必須不升
        Self.run(&motion, disc: &disc, now: &now, speed: 0, seconds: 6) {
            frame += 1
            if $0.lag < 0 { crossedZero = true }
            let rise = $0.fling - previousFling
            if frame == 1 ? rise >= 1e-6 : rise > 0 { flingMonotone = false }
            previousFling = $0.fling
            flingInRange = flingInRange && (0...LiquidMotion.maxFling).contains($0.fling)
        }
        #expect(crossedZero)
        #expect(abs(motion.lag) < 0.5)
        #expect(flingMonotone)
        #expect(flingInRange)
    }

    /// 染料團（核心 ± 0.05）任何時刻都在 [0.46, 0.95]，即環帶 [0.452, 0.97] 內
    @Test(arguments: LiquidPreset.allCases)
    func blobsStayInsideRing(preset: LiquidPreset) {
        var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
        var disc = 0.0, now = 0.0
        var inside = true
        let check: (LiquidMotion) -> Void = { m in
            for blob in LiquidBlob.seeds {
                let core = blob.radius(fling: m.fling, gain: preset.flingGain)
                inside = inside && core - LiquidBlob.halfWidth >= 0.46 - 1e-9 && core + LiquidBlob.halfWidth <= 0.95 + 1e-9
            }
        }
        Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 20, inspect: check)
        Self.run(&motion, disc: &disc, now: &now, speed: 0, seconds: 10, inspect: check)
        #expect(inside)
        // 極端值：c 夾到 1.5 時也在環帶內
        for blob in LiquidBlob.seeds {
            for fling in [0.0, LiquidMotion.maxFling] {
                let core = blob.radius(fling: fling, gain: LiquidPreset.dramatic.flingGain)
                #expect(core - LiquidBlob.halfWidth >= 0.46 - 1e-9)
                #expect(core + LiquidBlob.halfWidth <= 0.95 + 1e-9)
            }
        }
        #expect(LiquidBlob.seeds.count == 8)
        #expect(LiquidBlob.seeds.allSatisfy { (0.55...0.80).contains($0.baseRadius) })
    }

    /// dt＝1/60 與 1/120 的軌跡差 < 最大 |s| 的 1%
    @Test(arguments: LiquidPreset.allCases)
    func trajectoryIndependentOfFrameRate(preset: LiquidPreset) {
        func trajectory(dt: Double) -> [Double] {
            var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
            var disc = 0.0, now = 0.0
            var samples: [Double] = []
            // 每 1/60 s 取樣一次（dt＝1/120 時隔一步取一次）
            let stride = Int((1.0 / 60 / dt).rounded())
            var count = 0
            let take: (LiquidMotion) -> Void = { m in
                count += 1
                if count % stride == 0 { samples.append(m.lag) }
            }
            Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 6, dt: dt, inspect: take)
            Self.run(&motion, disc: &disc, now: &now, speed: 0, seconds: 6, dt: dt, inspect: take)
            return samples
        }
        let fine = trajectory(dt: 1.0 / 120)
        let coarse = trajectory(dt: 1.0 / 60)
        #expect(fine.count == coarse.count)
        let peak = fine.map(abs).max() ?? 0
        let worst = zip(fine, coarse).map { abs($0 - $1) }.max() ?? 0
        #expect(peak > 0)
        #expect(worst < 0.01 * peak, "worst \(worst) peak \(peak)")
    }

    /// 0.2 s 一幀（卡頓）自動分步，不發散
    @Test(arguments: LiquidPreset.allCases)
    func largeFrameStepsDoNotDiverge(preset: LiquidPreset) {
        var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
        var disc = 0.0, now = 0.0
        var bounded = true
        let limit = LiquidMotion.damping * Self.omega * preset.period / .pi * 3
        Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 10, dt: 0.2) {
            bounded = bounded && abs($0.lag) <= limit && $0.lag.isFinite
        }
        Self.run(&motion, disc: &disc, now: &now, speed: 0, seconds: 10, dt: 0.2) {
            bounded = bounded && abs($0.lag) <= limit && $0.lag.isFinite
        }
        #expect(bounded)
        #expect(abs(motion.lag) < 0.5)
    }

    /// 兩次取樣間隔 > 1 s：不猜圈數，液體基準重設到目前盤角、速度 0
    @Test func longGapResetsFluidToDisc() {
        var motion = LiquidMotion(preset: .liquid, discAngle: 0, at: 0)
        var disc = 0.0, now = 0.0
        Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 3)
        #expect(motion.lag > 0)
        motion.advance(to: disc + 400, at: now + 1.5)
        #expect(motion.lag == 0)
        #expect(motion.fluidVelocity == 0)
    }

    /// 同一時間戳或時間倒退：不積分
    @Test func nonAdvancingTimeIsIgnored() {
        var motion = LiquidMotion(preset: .liquid, discAngle: 0, at: 1)
        motion.advance(to: 10, at: 1)
        motion.advance(to: 10, at: 0.5)
        #expect(motion.lag == 0)
        #expect(motion.fluidVelocity == 0)
    }

    @Test(arguments: LiquidPreset.allCases)
    func reduceMotionFrameHasNoLagOrFling(preset: LiquidPreset) {
        var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
        var disc = 0.0, now = 0.0
        Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 3)
        let normal = motion.frame(reduceMotion: false)
        let reduced = motion.frame(reduceMotion: true)
        #expect(normal.lag != 0)
        #expect(normal.fling != 0)
        #expect(reduced.lag == 0)
        #expect(reduced.fling == 0)
        #expect(reduced.discAngle == normal.discAngle)
    }

    /// 停後在有限時間內判定收斂（|s| < 0.05°、|Θf'| < 0.05°/s、c < 0.01），TimelineView 才能再暫停
    @Test(arguments: LiquidPreset.allCases)
    func settlesInFiniteTimeAfterStop(preset: LiquidPreset) {
        var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
        var disc = 0.0, now = 0.0
        Self.run(&motion, disc: &disc, now: &now, speed: Self.omega, seconds: 10)
        #expect(!motion.isSettled)
        var settledStep: Int?
        var step = 0
        Self.run(&motion, disc: &disc, now: &now, speed: 0, seconds: 20) {
            step += 1
            if settledStep == nil, $0.isSettled { settledStep = step }
        }
        #expect(settledStep != nil)
        #expect(motion.isSettled)
    }

    @Test func presetsMatchPlan() {
        #expect(LiquidPreset.subtle.period == 0.6)
        #expect(LiquidPreset.liquid.period == 1.0)
        #expect(LiquidPreset.dramatic.period == 1.6)
        #expect(LiquidPreset.subtle.flingGain == 0.5)
        #expect(LiquidPreset.liquid.flingGain == 1)
        #expect(LiquidPreset.dramatic.flingGain == 1.6)
    }
}

struct AngleUnwrapperTests {
    @Test func firstSampleIsPassedThrough() {
        var unwrapper = AngleUnwrapper()
        #expect(unwrapper.unwrap(123) == 123)
    }

    @Test func forwardWrapDoesNotJump() {
        var unwrapper = AngleUnwrapper()
        _ = unwrapper.unwrap(358)
        #expect(abs(unwrapper.unwrap(359.5) - 359.5) < 1e-9)
        #expect(abs(unwrapper.unwrap(0.5) - 360.5) < 1e-9)
        #expect(abs(unwrapper.unwrap(2) - 362) < 1e-9)
    }

    @Test func backwardWrapDoesNotJump() {
        var unwrapper = AngleUnwrapper()
        _ = unwrapper.unwrap(1)
        #expect(abs(unwrapper.unwrap(0) - 0) < 1e-9)
        #expect(abs(unwrapper.unwrap(359) - -1) < 1e-9)
    }

    @Test func manyTurnsAccumulate() {
        var unwrapper = AngleUnwrapper()
        var last = 0.0
        for i in 0...720 { last = unwrapper.unwrap(Double(i * 5).truncatingRemainder(dividingBy: 360)) }
        #expect(abs(last - 3600) < 1e-9)
    }
}
#endif
