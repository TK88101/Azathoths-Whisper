import Testing
@testable import SpikeCore

struct B1VerdictTests {
    private func good(_ id: String) -> PlayCheck {
        PlayCheck(expectedID: id, readID: id, state: .playing)
    }

    private func twentyGood() -> [PlayCheck] {
        (0..<20).map { good("ID\($0)") }
    }

    @Test func twentyCorrectPlayingTracksPass() {
        #expect(B1Verdict.judge(twentyGood()) == .pass)
    }

    @Test func theRightTrackButPausedFails() {
        var checks = twentyGood()
        checks[7] = PlayCheck(expectedID: "ID7", readID: "ID7", state: .paused)
        #expect(B1Verdict.judge(checks) == .fail)
    }

    @Test func aWrongTrackFails() {
        var checks = twentyGood()
        checks[0] = PlayCheck(expectedID: "ID0", readID: "OTHER", state: .playing)
        #expect(B1Verdict.judge(checks) == .fail)
    }

    @Test func aMissingReadFails() {
        var checks = twentyGood()
        checks[3] = PlayCheck(expectedID: "ID3", readID: nil, state: nil)
        #expect(B1Verdict.judge(checks) == .fail)
    }

    @Test func fewerThanTwentySamplesIsUndetermined() {
        #expect(B1Verdict.judge(Array(twentyGood().prefix(19))) == .undetermined)
    }
}

struct B3VerdictTests {
    private func playing(target: Double, readBack: Double, elapsed: Double) -> SeekCheck {
        SeekCheck(target: target, readBack: readBack, sentAt: 100, readAt: 100 + elapsed,
                  wasPlaying: true, trackChanged: false)
    }

    @Test func playingReadBackAtTheUpperEdgeOfTheWindowPasses() {
        // 上緣＝目標 + 經過時間 + 1 s
        #expect(playing(target: 30, readBack: 31.5, elapsed: 0.5).isWithinTolerance)
    }

    @Test func playingReadBackJustAboveTheUpperEdgeFails() {
        #expect(!playing(target: 30, readBack: 31.51, elapsed: 0.5).isWithinTolerance)
    }

    @Test func playingReadBackAtTheLowerEdgePasses() {
        #expect(playing(target: 30, readBack: 29, elapsed: 0.5).isWithinTolerance)
    }

    @Test func playingReadBackJustBelowTheLowerEdgeFails() {
        #expect(!playing(target: 30, readBack: 28.99, elapsed: 0.5).isWithinTolerance)
    }

    @Test func zeroTargetAcceptsTheSmallForwardDrift() {
        #expect(playing(target: 0, readBack: 0.4, elapsed: 0.3).isWithinTolerance)
    }

    @Test func pausedUsesASymmetricOneSecondWindow() {
        let inside = SeekCheck(target: 50, readBack: 51, sentAt: 0, readAt: 5, wasPlaying: false, trackChanged: false)
        let outside = SeekCheck(target: 50, readBack: 51.01, sentAt: 0, readAt: 5, wasPlaying: false, trackChanged: false)
        #expect(inside.isWithinTolerance)
        #expect(!outside.isWithinTolerance)
    }

    @Test func aTrackChangeNearTheEndIsAFailure() {
        let check = SeekCheck(target: 175, readBack: 0.2, sentAt: 0, readAt: 0.3, wasPlaying: true, trackChanged: true)
        #expect(!check.isWithinTolerance)
    }

    @Test func missingReadBackFails() {
        let check = SeekCheck(target: 10, readBack: nil, sentAt: 0, readAt: 0.3, wasPlaying: true, trackChanged: false)
        #expect(!check.isWithinTolerance)
    }

    @Test func verdictNeedsTwentyGoodSamples() {
        let good = (0..<20).map { _ in playing(target: 30, readBack: 30.2, elapsed: 0.2) }
        #expect(B3Verdict.judge(good) == .pass)
        #expect(B3Verdict.judge(Array(good.prefix(19))) == .undetermined)
        var bad = good
        bad[19] = playing(target: 30, readBack: 40, elapsed: 0.2)
        #expect(B3Verdict.judge(bad) == .fail)
    }
}

struct B5VerdictTests {
    private func samples(_ ms: [Double]) -> [TimedSample] {
        ms.map { TimedSample(milliseconds: $0, errorCode: nil) }
    }

    @Test func p95AtExactlyThreeHundredPasses() {
        // 50 筆：第 48 小＝300
        let ms = Array(repeating: 100.0, count: 47) + [300, 900, 900]
        #expect(B5Verdict.judge(samples(ms)) == .pass)
    }

    @Test func p95JustAboveThreeHundredFails() {
        let ms = Array(repeating: 100.0, count: 47) + [300.1, 900, 900]
        #expect(B5Verdict.judge(samples(ms)) == .fail)
    }

    @Test func anErrorSampleFailsEvenWhenTheRestIsFast() {
        var all = samples(Array(repeating: 50.0, count: 50))
        all[10] = TimedSample(milliseconds: nil, errorCode: -1712)
        #expect(B5Verdict.judge(all) == .fail)
    }

    @Test func fewerThanFiftySamplesIsUndetermined() {
        #expect(B5Verdict.judge(samples(Array(repeating: 50.0, count: 49))) == .undetermined)
    }
}
