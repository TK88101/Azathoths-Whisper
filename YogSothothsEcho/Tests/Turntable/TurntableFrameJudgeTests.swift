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
