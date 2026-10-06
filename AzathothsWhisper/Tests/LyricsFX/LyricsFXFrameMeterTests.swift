import Testing

@testable import AzathothsWhisper

// A2 計劃 §3.7：每幀耗時的純記帳（環形緩衝＋百分位）
@Suite("LyricsFXFrameMeter")
struct LyricsFXFrameMeterTests {
    @Test func anEmptyMeterHasNoSummary() {
        #expect(LyricsFXFrameSamples(capacity: 4).summary == nil)
    }

    @Test func summarisesPercentilesAndGlyphs() throws {
        var samples = LyricsFXFrameSamples(capacity: 100)
        for micros in 1...100 { samples.record(micros: micros, glyphs: 200) }
        let summary = try #require(samples.summary)
        #expect(summary.frames == 100)
        #expect(summary.p50 == 50)
        #expect(summary.p95 == 95)
        #expect(summary.max == 100)
        #expect(summary.minGlyphs == 200 && summary.maxGlyphs == 200)
    }

    @Test func theOldestSamplesAreOverwritten() throws {
        var samples = LyricsFXFrameSamples(capacity: 3)
        [900, 1, 2, 3].forEach { samples.record(micros: $0, glyphs: $0) }
        let summary = try #require(samples.summary)
        #expect(summary.frames == 3)
        #expect(summary.max == 3)
        #expect(summary.minGlyphs == 1)
    }
}
