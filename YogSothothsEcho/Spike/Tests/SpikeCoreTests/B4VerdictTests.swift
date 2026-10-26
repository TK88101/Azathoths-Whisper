import Testing
@testable import SpikeCore

struct B4VerdictTests {
    private func mouse(_ latency: Double?) -> B4Event {
        B4Event(start: 10, detectedAt: latency.map { 10 + $0 }, startSource: .mouseDown, trigger: .notification)
    }

    private func enter(_ latency: Double?) -> B4Event {
        B4Event(start: 10, detectedAt: latency.map { 10 + $0 }, startSource: .enterKey, trigger: .poll)
    }

    @Test func twentyMouseTimedEventsWithinTwoSecondsPass() {
        let events = Array(repeating: mouse(2.0), count: 20)
        #expect(B4Verdict.judge(events) == .pass)
    }

    @Test func aMouseTimedEventJustOverTwoSecondsFails() {
        var events = Array(repeating: mouse(0.3), count: 20)
        events[5] = mouse(2.001)
        #expect(B4Verdict.judge(events) == .fail)
    }

    @Test func aMouseTimedEventThatIsNeverDetectedFails() {
        var events = Array(repeating: mouse(0.3), count: 20)
        events[0] = mouse(nil)
        #expect(B4Verdict.judge(events) == .fail)
    }

    @Test func passingFallbackEventsCountTowardTheTwenty() {
        let events = Array(repeating: mouse(0.3), count: 10) + Array(repeating: enter(1.9), count: 10)
        #expect(B4Verdict.judge(events) == .pass)
    }

    @Test func aSlowFallbackEventMakesTheWholeItemUndetermined() {
        // Enter 起點含人的移動時間，只會偏大：不過不能歸責系統
        var events = Array(repeating: mouse(0.3), count: 20)
        events[3] = enter(2.5)
        #expect(B4Verdict.judge(events) == .undetermined)
    }

    @Test func anUndetectedFallbackEventIsAlsoUndetermined() {
        var events = Array(repeating: mouse(0.3), count: 20)
        events[3] = enter(nil)
        #expect(B4Verdict.judge(events) == .undetermined)
    }

    @Test func aRealMouseFailureOutranksAnUndeterminedFallback() {
        var events = Array(repeating: mouse(0.3), count: 20)
        events[1] = enter(2.5)
        events[2] = mouse(3)
        #expect(B4Verdict.judge(events) == .fail)
    }

    @Test func fewerThanTwentyEventsIsUndetermined() {
        #expect(B4Verdict.judge(Array(repeating: mouse(0.3), count: 19)) == .undetermined)
    }
}
