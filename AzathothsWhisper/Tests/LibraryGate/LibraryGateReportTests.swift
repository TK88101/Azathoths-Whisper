import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.1：逐首四項判定＋計數。歌手名、曲名自編
@Suite("Library gate report")
struct LibraryGateReportTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    /// 樂團表裡組不出六槽的團（⑦ §2.1 已核：缺 palette）
    static let unfinishedBand = "Aphex Twin"

    private func track(
        _ id: String, artist: String, album: String = "Paper Boats", genre: String = "Glimmerwave Foo", lyrics: Bool = true, japanese: Bool = false
    ) -> ScannedTrack {
        ScannedTrack(persistentID: id, name: "Song \(id)", artist: artist, album: album, genre: genre, hasLyrics: lyrics, isJapanese: japanese)
    }

    private func mb(_ entries: [(String, ArtistStyleBook.Lookup)]) -> ArtistStyleBook {
        entries.reduce(ArtistStyleBook()) { $0.recording($1.1, forSpelling: $1.0, at: Self.base) }
    }

    private static let blackMetal = ArtistStyleBook.Lookup.verified(id: "mb-1", matchedReleaseGroups: ["rg-1"], genres: [.init(name: "black metal", count: 3)])

    private func report(_ tracks: [ScannedTrack], mb: ArtistStyleBook = ArtistStyleBook(), decisions: ArtistDecisionBook = ArtistDecisionBook(),
                        audited: Set<ProfileExplanation.AuditKey> = ReadabilityPolicy.audited) -> LibraryGateReport {
        LibraryGateReport(tracks: tracks, artistStyles: mb, decisions: decisions, audited: audited)
    }

    @Test func anUnresolvedArtistFailsIdentityUntilTheUserDecides() throws {
        let tracks = [track("1", artist: "Paper Harbour", genre: "Black Metal"), track("2", artist: "Paper Harbour", lyrics: false)]
        let books = mb([("Paper Harbour", .unresolved(.noAlbumMatch))])
        let before = report(tracks, mb: books)
        #expect(before.identity == .init(songs: 2, artists: 1))
        #expect(before.identityWithLyrics == .init(songs: 1, artists: 1))
        let decided = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base)
        #expect(report(tracks, mb: books, decisions: decided).identity == .zero)
    }

    @Test func anArtistNotYetLookedUpAlsoFailsIdentity() {
        #expect(report([track("1", artist: "Paper Harbour", genre: "Black Metal")]).identity == .init(songs: 1, artists: 1))
    }

    @Test func signedBandsAndJapaneseSongsNeedNoIdentity() {
        let r = report([track("1", artist: "Mayhem"), track("2", artist: "Paper Harbour", japanese: true)])
        #expect(r.identity == .zero)
        #expect(r.rows.allSatisfy { $0.mbStatus == .notApplicable })
    }

    @Test func monoSongsFailComposedAndAChosenStyleFixesThem() throws {
        let tracks = [track("1", artist: "Paper Harbour", genre: "Rock")]
        let books = mb([("Paper Harbour", .unresolved(.notFound))])
        #expect(report(tracks, mb: books).composed == .init(songs: 1, artists: 1))
        let decided = try ArtistDecisionBook().deciding(.style(rowID: "punk"), forArtists: ["Paper Harbour"], at: Self.base)
        let after = report(tracks, mb: books, decisions: decided)
        #expect(after.composed == .zero && after.identity == .zero && after.readability == .zero)
        #expect(after.passed)
    }

    @Test func anUnfinishedSignedBandIsCountedAsMonoAndBlocksTheGate() throws {
        let r = report([track("1", artist: Self.unfinishedBand)])
        #expect(r.composed == .init(songs: 1, artists: 1))
        #expect(r.signedPending == .init(songs: 1, artists: 1))
        #expect(r.rows[0].noStyleReason == .signedBandMissingParts)
        #expect(!r.passed, "署名待補元件照樣擋住閘門（§10-1）")
    }

    @Test func aComposedStyleOutsideTheAuditedSetFailsReadability() {
        let tracks = [track("1", artist: "Paper Harbour", genre: "Black Metal")]
        let books = mb([("Paper Harbour", Self.blackMetal)])
        #expect(report(tracks, mb: books).readability == .zero)
        #expect(report(tracks, mb: books, audited: []).readability == .init(songs: 1, artists: 1))
    }

    @Test func noMatchCarriesAReadableReason() {
        let books = mb([("Paper Harbour", .unresolved(.ambiguous))])
        let row = report([track("1", artist: "Paper Harbour", genre: "Rock")], mb: books).rows[0]
        #expect(row.explanation.key == .none)
        #expect(row.noStyleReason == .noRowMatched)
        #expect(row.mbStatus == .unresolved(.ambiguous))
        #expect(row.passesSource)
    }

    @Test func everyScannedTrackHasExactlyOneRowAndASource() {
        let tracks = [track("1", artist: "Mayhem"), track("2", artist: "Paper Harbour", japanese: true), track("3", artist: "Paper Harbour", genre: "Rock")]
        let r = report(tracks)
        #expect(r.rows.map(\.track.persistentID) == ["1", "2", "3"])
        #expect(r.source == .zero)
    }

    @Test func artistsAreListedBySpellingFamilyWithTheirIssues() throws {
        let tracks = [
            track("1", artist: "Paper Harbour", album: "A", genre: "Rock"), track("2", artist: "PAPER HARBOUR", album: "B", genre: "Rock"),
            track("3", artist: "AC/DX", genre: "Black Metal"), track("4", artist: "ACDX", genre: "Black Metal"),
        ]
        let r = report(tracks)
        let harbour = try #require(r.artists.first { $0.key == ArtistDecisionBook.key("Paper Harbour") })
        #expect(harbour.songs == 2 && harbour.albums == 2)
        #expect(harbour.issues == [.identity, .composed])
        let acdx = try #require(r.artists.first { $0.key == ArtistDecisionBook.key("AC/DX") })
        #expect(acdx.sameNormalizedName == [ArtistDecisionBook.key("ACDX")], "同 normalizedArtist 的其他家族並排（R4 A-1）")
    }

    @Test func keepFallbackInBulkIsOfferedOnlyWhenEverySongIsComposed() throws {
        let tracks = [
            track("1", artist: "Paper Harbour", genre: "Black Metal"),
            track("2", artist: "Velvet Lanterns", genre: "Black Metal"), track("3", artist: "Velvet Lanterns", genre: "Rock"),
        ]
        let r = report(tracks)
        #expect(try #require(r.artists.first { $0.key == ArtistDecisionBook.key("Paper Harbour") }).canKeepFallbackInBulk)
        #expect(try #require(r.artists.first { $0.key == ArtistDecisionBook.key("Velvet Lanterns") }).canKeepFallbackInBulk == false)
    }

    /// 計劃 R1-6：決定後沒有問題的歌手也要留在清單，才改得了、清得掉（codex review R1）
    @Test func aDecidedArtistStaysListedSoTheDecisionCanBeChanged() throws {
        let decided = try ArtistDecisionBook().deciding(.style(rowID: "punk"), forArtists: ["Paper Harbour"], at: Self.base)
        let r = report([track("1", artist: "Paper Harbour", genre: "Rock")], decisions: decided)
        let artist = try #require(r.artists.first)
        #expect(artist.issues.isEmpty)
        #expect(artist.decision?.choice == .style(rowID: "punk"))
    }

    @Test func anArtistWithoutIssuesIsNotListed() {
        #expect(report([track("1", artist: "Mayhem")]).artists.isEmpty)
    }

    @Test func anEmptyLibraryPassesNothingFalsely() {
        let r = report([])
        #expect(r.passed == false, "空掃描不能當成達標（R3-4）")
    }
}
