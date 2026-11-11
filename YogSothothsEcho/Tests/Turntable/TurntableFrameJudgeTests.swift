import Testing

@testable import YogSothothsEcho

// S5 T12（sprint-5-detail.md §4.8）：N-02「60fps」的量法——每個 1 s 滑動視窗 ≥ 58 幀；間隔 > 25 ms 的幀 ≤ 0.5%；沒有 > 50 ms

private func stamps(fps: Double, seconds: Double, start: Double = 100) -> [Double] {
    (0..<Int(fps * seconds)).map { start + Double($0) / fps }
}

struct TurntableFrameJudgeTests {
    @Test func steady60Passes() {
        let result = TurntableFrameJudge.evaluate(stamps(fps: 60, seconds: 30))
        #expect(result.passes && result.minWindowFrames >= 59 && result.maxInterval < 0.017)
    }

    @Test func steady120PassesToo() {
        #expect(TurntableFrameJudge.evaluate(stamps(fps: 120, seconds: 10)).passes)
    }

    /// 連續 40fps（每幀 25 ms，未超過 25 ms 門檻）仍不過——視窗幀數只有 40
    @Test func steady40Fails() {
        let result = TurntableFrameJudge.evaluate(stamps(fps: 40, seconds: 10))
        #expect(!result.passes && result.minWindowFrames <= 41)
    }

    @Test func singleLongHitchFails() {
        var s = stamps(fps: 60, seconds: 10)
        s = s.map { $0 > 105 ? $0 + 0.06 : $0 }   // 一次 76 ms 的卡頓
        let result = TurntableFrameJudge.evaluate(s)
        #expect(!result.passes && result.maxInterval > 0.05)
    }

    /// 掉幀比例超過 0.5%（每 100 幀有 1 次 33 ms）
    @Test func frequentSmallDropsFail() {
        var s: [Double] = [0]
        for i in 1..<3000 { s.append(s[i - 1] + (i % 100 == 0 ? 0.0334 : 1.0 / 60)) }
        let result = TurntableFrameJudge.evaluate(s)
        #expect(result.droppedRatio > 0.005 && !result.passes)
    }

    @Test func tooFewSamplesCannotPass() {
        #expect(!TurntableFrameJudge.evaluate([]).passes)
        #expect(!TurntableFrameJudge.evaluate(stamps(fps: 60, seconds: 0.5)).passes)
    }

    /// 恰好 58 幀／秒＝過（邊界含等號）。每秒 46 個 1/64 s 與 12 個 3/128 s 間隔（皆 < 25 ms、二進位精確），週期 1 s
    @Test func exactlyFiftyEightFramesPasses() {
        var s: [Double] = [0]
        for second in 0..<10 {
            for k in 0..<58 { s.append(s.last! + (k < 46 ? 1.0 / 64 : 3.0 / 128)) }
            #expect(s.last! == Double(second + 1))
        }
        let result = TurntableFrameJudge.evaluate(s)
        #expect(result.minWindowFrames == 58 && result.droppedRatio == 0 && result.passes)
    }

    /// 只有一次 > 50 ms 的卡頓、視窗幀數與掉幀比例都達標＝仍不過（單獨驗卡頓條件）
    @Test func lonelyHitchFailsOnItsOwn() {
        var s = (0..<384).map { Double($0) / 128 }      // 128 fps、3 s
        s.removeSubrange(200..<206)                      // 一個 7/128 s ≈ 55 ms 的間隔
        let result = TurntableFrameJudge.evaluate(s)
        #expect(result.minWindowFrames >= 58 && result.droppedRatio <= TurntableFrameJudge.maxDroppedRatio)
        #expect(result.maxInterval > TurntableFrameJudge.hitchInterval && !result.passes)
    }
}

// CR-038 L-T4（yse-liquid-vinyl-sample.md v0.4 §4.5）：120 Hz 參數組——每個 1 s 視窗 ≥ 116 幀；間隔 > 12.5 ms 的幀 ≤ 0.5%；沒有 > 50 ms。
// 60 Hz（N-02）維持原值，evaluate 不帶參數＝60 Hz
struct TurntableFrameJudge120Tests {
    private let hz120 = TurntableFrameJudge.Profile.hz120

    @Test func profilesMatchPlan() {
        #expect(TurntableFrameJudge.Profile.hz60 == .init(name: "60Hz", minFramesPerSecond: 58, droppedInterval: 0.025,
                                                          maxDroppedRatio: 0.005, hitchInterval: 0.05))
        #expect(hz120 == .init(name: "120Hz", minFramesPerSecond: 116, droppedInterval: 0.0125, maxDroppedRatio: 0.005, hitchInterval: 0.05))
    }

    @Test func steady120Passes120AndSteady60Fails120() {
        #expect(TurntableFrameJudge.evaluate(stamps(fps: 120, seconds: 10), profile: hz120).passes)
        let at60 = TurntableFrameJudge.evaluate(stamps(fps: 60, seconds: 10), profile: hz120)
        #expect(!at60.passes)
        #expect(at60.droppedRatio == 1)
    }

    /// 邊界：每秒 116 幀＝過、115 幀＝不過（間隔都 < 12.5 ms；1/128 與 3/256 皆二進位精確）
    @Test func windowBoundaryIs116() {
        func paced(framesPerSecond n: Int) -> [Double] {
            // n 個間隔湊滿 1 s：a 個 1/128 s 與 b 個 3/256 s（a + b = n、a/128 + 3b/256 = 1）
            let b = (256 - 2 * n), a = n - b
            var s: [Double] = [0]
            for _ in 0..<5 { for k in 0..<n { s.append(s.last! + (k < a ? 1.0 / 128 : 3.0 / 256)) } }
            return s
        }
        let pass = TurntableFrameJudge.evaluate(paced(framesPerSecond: 116), profile: hz120)
        #expect(pass.minWindowFrames == 116 && pass.droppedRatio == 0 && pass.passes)
        let fail = TurntableFrameJudge.evaluate(paced(framesPerSecond: 115), profile: hz120)
        #expect(fail.minWindowFrames == 115 && !fail.passes)
    }

    /// 掉幀門檻 12.5 ms：11.7 ms（3/256 s，二進位精確）不算掉幀；13.8 ms 算
    @Test func droppedIntervalThresholdIs12_5ms() {
        var under = stamps(fps: 128, seconds: 3)
        under = under.enumerated().map { $0.offset >= 200 ? $0.element + (3.0 / 256 - 1.0 / 128) : $0.element }
        let kept = TurntableFrameJudge.evaluate(under, profile: hz120)
        #expect(kept.maxInterval == 3.0 / 256)
        #expect(kept.droppedRatio == 0)
        var over = stamps(fps: 128, seconds: 3)
        over = over.enumerated().map { $0.offset >= 200 ? $0.element + 0.006 : $0.element }   // 一次 13.8 ms
        #expect(TurntableFrameJudge.evaluate(over, profile: hz120).droppedRatio > 0)
        // 同一個 13.8 ms 在 60 Hz 參數組下不算掉幀
        #expect(TurntableFrameJudge.evaluate(over).droppedRatio == 0)
    }

    /// 卡頓門檻 50 ms 兩組相同：51 ms 不過、恰好 50 ms 不因卡頓不過
    @Test func hitchBoundaryIs50ms() {
        var s = stamps(fps: 128, seconds: 3)
        s = s.enumerated().map { $0.offset >= 200 ? $0.element + 0.051 - 1.0 / 128 : $0.element }
        let result = TurntableFrameJudge.evaluate(s, profile: hz120)
        #expect(result.maxInterval > 0.05 && !result.passes)
    }

    /// 結果帶參數組名稱（寫進量測 JSON）
    @Test func resultRecordsProfileName() {
        #expect(TurntableFrameJudge.evaluate(stamps(fps: 120, seconds: 2), profile: hz120).profile == "120Hz")
        #expect(TurntableFrameJudge.evaluate(stamps(fps: 60, seconds: 2)).profile == "60Hz")
    }

    /// 由平均幀間隔換算實際更新率
    @Test func actualRateFromMeanInterval() {
        #expect(abs(TurntableFrameJudge.evaluate(stamps(fps: 120, seconds: 3), profile: hz120).actualHz - 120) < 0.01)
        #expect(TurntableFrameJudge.evaluate([], profile: hz120).actualHz == 0)
    }
}

// CR-038 §4.5-3：G7 甩動 5 次，每次自甩動起 2 s 分段判定，報每段與最差、中位數（假時間戳）
struct TurntableFrameSegmentTests {
    @Test func eachSwipeIsJudgedOnItsOwnTwoSecondWindow() {
        var s = stamps(fps: 120, seconds: 20)
        // 第 3 次甩動（10 s）後 0.5 s 有一次 60 ms 卡頓
        s = s.map { $0 > 110.5 ? $0 + 0.06 : $0 }
        let starts = [102.0, 106.0, 110.0, 114.0, 117.5]
        let summary = TurntableFrameJudge.segments(s, starts: starts, length: 2, profile: .hz120)
        #expect(summary.segments.count == 5)
        #expect(summary.segments.map(\.passes) == [true, true, false, true, true])
        #expect(summary.worstMaxInterval > 0.05)
        #expect(abs(summary.medianMinWindowFrames - 119) <= 1)
        #expect(!summary.passes)
    }

    @Test func noSwipesCannotPass() {
        #expect(!TurntableFrameJudge.segments(stamps(fps: 120, seconds: 5), starts: [], length: 2, profile: .hz120).passes)
    }
}
