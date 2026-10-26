import Testing
@testable import SpikeCore

struct StatsTests {
    @Test func nearestRankP95OfTwentyIsTheNineteenthSmallest() {
        let values = (1...20).map(Double.init).shuffled()
        #expect(Stats.percentile(values, 0.95) == 19)
    }

    @Test func nearestRankP95OfFiftyIsTheFortyEighthSmallest() {
        let values = Array((1...50).map(Double.init).reversed())
        #expect(Stats.percentile(values, 0.95) == 48)
    }

    @Test func emptyInputHasNoPercentile() {
        #expect(Stats.percentile([], 0.95) == nil)
    }

    @Test func infinityIsKeptSoATimeoutCanDominate() {
        let values = Array(repeating: 10.0, count: 19) + [.infinity]
        #expect(Stats.percentile(values, 0.95) == 10)
        #expect(Stats.percentile(values, 1.0) == .infinity)
    }
}
