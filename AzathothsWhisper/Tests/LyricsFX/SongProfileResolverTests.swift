import Foundation
import Testing

@testable import AzathothsWhisper

// B1 計劃 §3.5：歌曲目標值。樂團覆寫表 → genre 關鍵字合成 → pending／mono
@Suite("Song profile resolver")
struct SongProfileResolverTests {
    private func profile(_ resolution: ProfileResolution) throws -> SongProfile {
        guard case .profile(let profile) = resolution else {
            Issue.record("期望 profile，實得 \(resolution)")
            throw CancellationError()
        }
        return profile
    }

    @Test func aKnownBandNeedsNoGenre() throws {
        let mayhem = try profile(SongProfileResolver.resolve(artist: "Mayhem", genre: nil))
        #expect(mayhem.tags == [.black])
        #expect(mayhem.axes[.aggression] == 0.9 && mayhem.axes[.raw] == 0.95)
        #expect(mayhem.axes[.bounce] == nil, "原型沒宣告的軸＝未知")
    }

    @Test func theOverrideWinsOverTheGenre() throws {
        let cradle = try profile(SongProfileResolver.resolve(artist: "Cradle of Filth", genre: "Pop"))
        #expect(cradle.tags == [.black, .gothic, .symphonic] && cradle.axes[.aggression] == 0.88)
    }

    @Test func anUnknownBandWithoutAGenreIsPending() {
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: nil) == .pending)
    }

    @Test func anUnknownGenreIsSettledAsMono() {
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Experimental Foo") == .mono)
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "") == .mono)
    }

    @Test(arguments: ["Black Metal", "black metal ", "Death Metal/Black Metal", "Pagan Black", "Depressive"])
    func blackGenresResolveToTheBlackTag(genre: String) throws {
        let resolved = try profile(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: genre))
        #expect(resolved.tags.contains(.black))
        #expect((resolved.axes[.aggression] ?? 0) >= 0.65)
    }

    @Test(arguments: ["Symphonic Metal", "Symphony Metal", "Neoclassic", "Soundtrack"])
    func symphonicGenresResolveToTheSymphonicTag(genre: String) throws {
        let resolved = try profile(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: genre))
        #expect(resolved.tags == [.symphonic])
        #expect((resolved.axes[.aggression] ?? 1) < 0.65)
    }

    /// P11：交響不得把黑金屬的侵略性稀釋到溫柔元件的門檻之下
    @Test func symphonicBlackKeepsTheAggressionAndAveragesTheSoftAxes() throws {
        let resolved = try profile(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Symphony Black Metal"))
        #expect(resolved.tags == [.black, .symphonic])
        let black = try profile(SongProfileResolver.resolve(artist: "x", genre: "Black Metal"))
        let symphonic = try profile(SongProfileResolver.resolve(artist: "x", genre: "Symphonic Metal"))
        #expect(resolved.axes[.aggression] == max(black.axes[.aggression]!, symphonic.axes[.aggression]!))
        #expect(resolved.axes[.theatrical] == max(black.axes[.theatrical]!, symphonic.axes[.theatrical]!))
        #expect(abs(resolved.axes[.elegance]! - (black.axes[.elegance]! + symphonic.axes[.elegance]!) / 2) < 1e-12)
        #expect(resolved.axes[.aggression]! >= 0.65)
    }

    @Test func genericKeywordsOnlyCountWithoutASpecificOne() {
        let rows: [SongProfileResolver.KeywordRow] = [
            .init(keywords: ["metal"], tags: [.heavy], axes: [.aggression: 0.5, .bright: 0.9], isGeneric: true),
            .init(keywords: ["black"], tags: [.black], axes: [.aggression: 0.9], isGeneric: false),
        ]
        #expect(SongProfileResolver.compose(genre: "Black Metal", rows: rows) == SongProfile(axes: [.aggression: 0.9], tags: [.black]))
        #expect(SongProfileResolver.compose(genre: "Metal", rows: rows) == SongProfile(axes: [.aggression: 0.5, .bright: 0.9], tags: [.heavy]))
        #expect(SongProfileResolver.compose(genre: "Polka", rows: rows) == nil)
    }

    @Test func everyOverrideHasValuesWithinRange() {
        for (_, profile) in SongProfileResolver.overrides {
            #expect(profile.axes.values.allSatisfy { (0...1).contains($0) } && !profile.tags.isEmpty)
        }
    }
}

@Suite("Artist normalization")
struct ArtistNormalizationTests {
    @Test(arguments: [
        ("The Offspring", "offspring"), ("Blink‐182", "blink182"), ("blink-182", "blink182"),
        ("Motörhead", "motorhead"), ("  Cradle of Filth ", "cradleoffilth"), ("THEATRE OF TRAGEDY", "theatreoftragedy"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(SongProfileResolver.normalizedArtist(input) == expected)
    }

    @Test func normalizingTwiceChangesNothing() {
        for name in ["The Offspring", "Motörhead", "Dimmu Borgir", "İstanbul Ensemble"] {
            let once = SongProfileResolver.normalizedArtist(name)
            #expect(SongProfileResolver.normalizedArtist(once) == once)
        }
    }

    @Test func turkishDottedIDoesNotDependOnTheSystemLocale() {
        #expect(SongProfileResolver.normalizedArtist("İstanbul") == "istanbul")
    }
}
