import Foundation
import Testing

@testable import AzathothsWhisper

// 增補計劃 §4.2（B）：判定的兩個共識 tier——MB 之後取代逐曲 Apple；失敗一律退回同 tier 逐曲。歌手名自編
@Suite("Apple consensus resolution")
struct AppleConsensusResolutionTests {
    private static let artist = "Paper Harbour"
    private static let hardRock = AppleGenreConsensus(genreRows: .init(rowIDs: ["hardrock"], votes: 3, evidence: 4), genericRows: nil)
    private static let electronic = AppleGenreConsensus(genreRows: nil, genericRows: .init(rowIDs: ["electronic"], votes: 2, evidence: 3))

    private func explain(
        artist: String = Self.artist, genre: String?, japanese: Bool = false, mb: ArtistGenres = .unresolved, decision: ArtistDecision.Choice? = nil,
        consensus: AppleGenreConsensus?, rejected: Set<ProfileExplanation.AuditKey> = []
    ) -> ProfileExplanation {
        SongProfileResolver.explain(
            artist: artist, genre: genre, lyrics: .text(isJapanese: japanese), artistGenres: mb, decision: decision, consensus: consensus, rejected: rejected
        )
    }

    private func rows(_ ids: String...) -> SongProfile? {
        SongProfileResolver.compose(rows: (SongProfileResolver.keywordRows + SongProfileResolver.genericRows).filter { ids.contains($0.id) })
    }

    @Test func theArtistMajorityReplacesTheSongsOwnAppleGenre() {
        let e = explain(genre: "Gothic", consensus: Self.hardRock)
        #expect(e.key == .rows(.appleConsensus, ["hardrock"]))
        #expect(e.resolution == .genreRow(rows("hardrock")!))
    }

    @Test func aSongThatWouldBeMonoGetsTheArtistMajority() {
        #expect(explain(genre: "Rock", consensus: nil).key == .none)
        #expect(explain(genre: "Rock", consensus: Self.hardRock).key == .rows(.appleConsensus, ["hardrock"]))
    }

    @Test func earlierLayersStillWin() {
        #expect(explain(genre: "Rock", mb: .verified(["black metal"]), consensus: Self.hardRock).key == .rows(.mbGenre, ["black"]), "MB 是歌手層級資料，排在共識前")
        #expect(explain(genre: "Rock", decision: .style(rowID: "punk"), consensus: Self.hardRock).key == .rows(.userStyle, ["punk"]))
        #expect(explain(genre: "Rock", japanese: true, consensus: Self.hardRock).key == .jpop)
        #expect(explain(artist: "Mayhem", genre: "Rock", consensus: Self.hardRock).key == .signed("Mayhem"))
        #expect(explain(genre: nil, consensus: Self.hardRock).key == .pending, "genre 還沒讀到照舊等")
    }

    /// U3 真曲庫實測（2026-10-28）：MB 給得出歌手層級樣式（含通用列）時不得被 Apple 多數蓋掉——
    /// 某位 MB 判為 electronic＋experimental＋pop 的歌手，96 首曾被 27 首 Apple「Indie Rock」的多數改成 altindie
    @Test func anArtistStyledByMBGenericRowsKeepsMBAndPerSongApple() {
        let indie = AppleGenreConsensus(genreRows: .init(rowIDs: ["altindie"], votes: 27, evidence: 27), genericRows: nil)
        let overridden = explain(genre: "Alternative", mb: .verified(["electronic"]), consensus: indie)
        #expect(overridden.key == .rows(.genericMB, ["electronic"]))
        #expect(overridden.trace.contains(.init(layer: .appleConsensus, rowIDs: ["altindie"], outcome: .overriddenByMB)), "MB 曲風列的無命中排在前面")
        #expect(explain(genre: "Indie Rock", mb: .verified(["electronic"]), consensus: indie).key == .rows(.appleGenre, ["altindie"]), "逐曲判定照舊")
        #expect(explain(genre: "Pop", mb: .verified(["electronic"]), consensus: Self.electronic).key == .rows(.genericMB, ["electronic"]))
    }

    @Test func theGenericTierComesAfterGenericMB() {
        #expect(explain(genre: "Pop", mb: .verified(["industrial"]), consensus: Self.electronic).key == .rows(.genericMB, ["industrial"]))
        let e = explain(genre: "Pop", consensus: Self.electronic)
        #expect(e.key == .rows(.genericAppleConsensus, ["electronic"]))
        #expect(e.resolution == .genericRow(rows("electronic")!))
    }

    @Test func aGenericMajorityDoesNotOverrideTheSongsOwnGenreRow() {
        #expect(explain(genre: "Gothic", consensus: Self.electronic).key == .rows(.appleGenre, ["gothic"]))
    }

    @Test func anUnknownRowFallsBackToTheSongsOwnGenre() {
        let stale = AppleGenreConsensus(genreRows: .init(rowIDs: ["retired"], votes: 2, evidence: 2), genericRows: nil)
        let e = explain(genre: "Gothic", consensus: stale)
        #expect(e.key == .rows(.appleGenre, ["gothic"]))
        #expect(e.trace.first == .init(layer: .appleConsensus, rowIDs: ["retired"], outcome: .noHit))
    }

    @Test func aRejectedMajorityFallsBackToTheSongsOwnGenre() {
        let e = explain(genre: "Gothic", consensus: Self.hardRock, rejected: [.rows(["hardrock"])])
        #expect(e.key == .rows(.appleGenre, ["gothic"]))
        #expect(e.trace.first == .init(layer: .appleConsensus, rowIDs: ["hardrock"], outcome: .rejectedByReadability))
    }

    @Test func withoutConsensusNothingChanges() {
        for genre in ["Gothic", "Rock", "Pop", "Hard Rock"] {
            #expect(explain(genre: genre, consensus: nil) == SongProfileResolver.explain(
                artist: Self.artist, genre: genre, lyrics: .text(isJapanese: false), artistGenres: .unresolved, rejected: []
            ))
        }
    }

    @Test func consensusIsAnAppleSourceForTheSession() {
        #expect(explain(genre: "Rock", consensus: Self.hardRock).resolution.source == .genreRow)
        #expect(explain(genre: "Rock", consensus: Self.electronic).resolution.source == .generic)
    }
}
