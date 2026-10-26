import Testing
@testable import SpikeCore

struct StratifiedSamplerTests {
    private let library: [(id: String, kind: String)] =
        (0..<500).map { ("F\($0)", "file") } + [("R1", "remote"), ("R2", "remote"), ("U1", "url")]

    @Test func everyKindIsRepresentedAtLeastOnce() {
        let picked = StratifiedSampler.sample(library, count: 20, seed: 7)
        let kinds = Set(picked.compactMap { id in library.first { $0.id == id }?.kind })
        #expect(kinds == ["file", "remote", "url"])
        #expect(picked.count == 20)
    }

    @Test func theSameSeedGivesTheSameSample() {
        #expect(StratifiedSampler.sample(library, count: 20, seed: 7) == StratifiedSampler.sample(library, count: 20, seed: 7))
        #expect(StratifiedSampler.sample(library, count: 20, seed: 7) != StratifiedSampler.sample(library, count: 20, seed: 8))
    }

    @Test func noTrackIsPickedTwice() {
        let picked = StratifiedSampler.sample(library, count: 20, seed: 1)
        #expect(Set(picked).count == picked.count)
    }

    @Test func aSmallLibraryYieldsEverything() {
        let small = [(id: "A", kind: "file"), (id: "B", kind: "file")]
        #expect(Set(StratifiedSampler.sample(small, count: 20, seed: 1)) == ["A", "B"])
    }
}
