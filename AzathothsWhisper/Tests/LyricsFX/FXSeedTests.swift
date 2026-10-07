import Testing

@testable import AzathothsWhisper

// B1 計劃 §3.4：決定論種子（fnv1a64＋SplitMix64；不用 `Hasher`，它每次啟動換種子）
@Suite("FX 種子")
struct FXSeedTests {
    @Test func fnv1a64MatchesKnownVectors() {
        #expect(FXHash.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(FXHash.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(FXHash.fnv1a64("灯") == 0x278e_8c1b_6ce8_c59e, "以 UTF-8 位元組計")
    }

    @Test func splitMix64MatchesTheReferenceSequenceForSeedZero() {
        var random = SplitMix64(seed: 0)
        #expect(random.next() == 0xe220_a839_7b1d_cdaf)
        #expect(random.next() == 0x6e78_9e6a_a1b9_65f4)
        #expect(random.next() == 0x06c4_5d18_8009_454f)
    }

    @Test func theSameSeedRepeatsTheSameSequence() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        #expect((0..<16).map { _ in first.next() } == (0..<16).map { _ in second.next() })
    }

    @Test func unitStaysInsideTheHalfOpenInterval() {
        var random = SplitMix64(seed: 7)
        for _ in 0..<10_000 {
            let value = random.unit()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test func rangeMapsTheUnitIntoTheBounds() {
        var random = SplitMix64(seed: 9)
        for _ in 0..<1000 {
            let value = random.uniform(in: -2...3)
            #expect(value >= -2 && value <= 3)
        }
    }
}
