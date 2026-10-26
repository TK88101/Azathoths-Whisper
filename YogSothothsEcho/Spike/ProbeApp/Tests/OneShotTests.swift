import Testing
@testable import ProbeShared

@Suite struct OneShotTests {
    @Test func firstResumeWinsAndLaterOnesAreIgnored() async {
        let value: Int = await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            once.resume(1)
            once.resume(2)
        }
        #expect(value == 1)
    }

    @Test func raceReturnsWorkResultWhenFasterThanTimeout() async {
        let result = await raceTimeout(2) { 42 }
        #expect(result == 42)
    }

    @Test func raceReturnsNilWhenWorkOutlastsTimeout() async {
        let result: Int? = await raceTimeout(0.1) {
            try? await Task.sleep(for: .seconds(5))
            return 1
        }
        #expect(result == nil)
    }
}
