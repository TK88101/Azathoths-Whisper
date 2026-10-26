import Testing
@testable import SpikeCore

struct N3ResultTests {
    private func result(seconds: Double, megabytes: Double) -> N3Result {
        N3Result(seconds: seconds, footprintDeltaMB: megabytes, songCount: 12_234, albumCount: 900,
                 locationKinds: ["file": 12_234])
    }

    @Test func tenSecondsAndThreeHundredMegabytesMeetTheExpectation() {
        #expect(result(seconds: 10, megabytes: 300).meetsExpectation)
    }

    @Test func slightlySlowerMissesTheExpectation() {
        #expect(!result(seconds: 10.01, megabytes: 100).meetsExpectation)
    }

    @Test func slightlyLargerMissesTheExpectation() {
        #expect(!result(seconds: 3, megabytes: 300.1).meetsExpectation)
    }
}
