import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.1：逐首四項判定＋計數。歌手名、曲名自編
@Suite("Library gate report")
struct LibraryGateReportTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    /// 樂團表裡組不出六槽的團（⑦ §2.1 已核：缺 palette）
    /// 樂團表裡仍組不出的署名團。B2 批 5 補完 Aphex Twin 等 5 團後，只剩 Cannibal Corpse（批 5 計劃 F6，另案）
    static let unfinishedBand = "Cannibal Corpse"

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

    // MARK: 增補計劃 §4.1（A）：無詞曲依同歌手有詞曲推定日文

    @Test func aSongWithoutLyricsByAMostlyJapaneseArtistIsEstimatedJapanese() throws {
        let tracks = [
            track("1", artist: "Paper Harbour", japanese: true), track("2", artist: "Paper Harbour", japanese: true),
            track("3", artist: "Paper Harbour"), track("4", artist: "Paper Harbour", genre: "Rock", lyrics: false),
        ]
        let r = report(tracks, mb: mb([("Paper Harbour", .unresolved(.notFound))]))
        let estimated = try #require(r.rows.first { $0.track.persistentID == "4" })
        #expect(estimated.explanation.key == .jpop)
        #expect(estimated.japaneseEstimate == .init(lyricsSongs: 3, japaneseSongs: 2))
        #expect(estimated.mbStatus == .notApplicable)
        #expect(estimated.issues.isEmpty)
    }

    @Test func exactlyHalfJapaneseIsNotEnough() throws {
        let tracks = [track("1", artist: "Paper Harbour", japanese: true), track("2", artist: "Paper Harbour"), track("3", artist: "Paper Harbour", genre: "Rock", lyrics: false)]
        let row = try #require(report(tracks).rows.last)
        #expect(row.japaneseEstimate == nil)
        #expect(row.explanation.key == .none)
    }

    @Test func anArtistWithoutAnyLyricsIsNotEstimated() {
        let r = report([track("1", artist: "Paper Harbour", genre: "Rock", lyrics: false)])
        #expect(r.rows[0].japaneseEstimate == nil)
        #expect(r.rows[0].explanation.key == .none)
    }

    @Test func songsWithLyricsKeepTheirOwnJudgement() throws {
        let tracks = [
            track("1", artist: "Paper Harbour", japanese: true), track("2", artist: "Paper Harbour", japanese: true),
            track("3", artist: "Paper Harbour", genre: "Rock"),
        ]
        let english = try #require(report(tracks).rows.last)
        #expect(english.japaneseEstimate == nil)
        #expect(english.explanation.key == .none, "有詞的英文歌照自己的歌詞判，不推定")
    }

    /// R1-8：同歌手同曲風，一首有詞英文歌、一首無詞推定日文——判定不得共用快取
    @Test func aLyricSongAndAnEstimatedSongWithTheSameGenreAreJudgedSeparately() throws {
        let tracks = [
            track("1", artist: "Paper Harbour", japanese: true), track("2", artist: "Paper Harbour", japanese: true),
            track("3", artist: "Paper Harbour", genre: "Rock"), track("4", artist: "Paper Harbour", genre: "Rock", lyrics: false),
        ]
        let r = report(tracks)
        #expect(r.rows.map(\.explanation.key) == [.jpop, .jpop, .none, .jpop])
    }

    @Test func theEstimateFollowsTheSpellingFamily() {
        let tracks = [
            track("1", artist: "Paper Harbour", japanese: true), track("2", artist: "PAPER HARBOUR", genre: "Rock", lyrics: false),
            track("3", artist: "AC/DX", japanese: true), track("4", artist: "ACDX", genre: "Rock", lyrics: false),
        ]
        let r = report(tracks)
        #expect(r.rows[1].japaneseEstimate == .init(lyricsSongs: 1, japaneseSongs: 1), "大小寫寫法同一家族")
        #expect(r.rows[3].japaneseEstimate == nil, "AC/DX 與 ACDX 是不同家族")
    }

    @Test func theWithLyricsCountsIgnoreEstimates() {
        let tracks = [track("1", artist: "Paper Harbour", japanese: true), track("2", artist: "Paper Harbour", genre: "Rock", lyrics: false)]
        let r = report(tracks, mb: mb([("Paper Harbour", .unresolved(.notFound))]))
        #expect(r.identity == .zero && r.composed == .zero)
        #expect(r.identityWithLyrics == .zero && r.composedWithLyrics == .zero)
    }

    // MARK: 增補計劃 §4.2（B）：同歌手 Apple 曲風共識

    @Test func anArtistGetsItsMajorityAppleRowOnEverySong() throws {
        let tracks = [
            track("1", artist: "Paper Harbour", genre: "Hard Rock"), track("2", artist: "Paper Harbour", genre: "Hard Rock"),
            track("3", artist: "Paper Harbour", genre: "Hard Rock"), track("4", artist: "Paper Harbour", genre: "Gothic"),
            track("5", artist: "Paper Harbour", genre: "Rock"), track("6", artist: "Paper Harbour", genre: "Alternative", lyrics: false),
        ]
        let r = report(tracks, mb: mb([("Paper Harbour", .unresolved(.ambiguous))]))
        #expect(r.rows.allSatisfy { $0.explanation.key == .rows(.appleConsensus, ["hardrock"]) })
        let vote = AppleGenreConsensus.Vote(rowIDs: ["hardrock"], votes: 3, evidence: 4)
        #expect(r.consensus[ArtistDecisionBook.key("Paper Harbour")]?.genreRows == vote, "證據只算沒有共識時被 Apple 層採用的 4 首（R3-2）")
        #expect(r.rows.allSatisfy { LibraryCheckPresentation.source(for: $0, consensus: r.consensus[$0.familyKey]).detail == "hardrock · 3/4" })
        #expect(r.composed == .zero)
        #expect(r.identity == .init(songs: 6, artists: 1), "共識不解決身分未定")
    }

    @Test func japaneseAndEstimatedSongsAreNotEvidence() throws {
        let tracks = [
            track("1", artist: "Paper Harbour", genre: "Hard Rock", japanese: true), track("2", artist: "Paper Harbour", genre: "Hard Rock", japanese: true),
            track("3", artist: "Paper Harbour", genre: "Hard Rock", japanese: true), track("4", artist: "Paper Harbour", genre: "Hard Rock"),
            track("5", artist: "Paper Harbour", genre: "Rock"), track("6", artist: "Paper Harbour", genre: "Hard Rock", lyrics: false),
        ]
        let r = report(tracks)
        #expect(r.consensus.isEmpty, "只剩 1 首英文歌是證據，不到 2 首")
        #expect(try #require(r.rows.first { $0.track.persistentID == "5" }).explanation.key == .none)
    }

    @Test func anArtistVerifiedByMBIsNotAffected() {
        let tracks = [track("1", artist: "Paper Harbour", genre: "Hard Rock"), track("2", artist: "Paper Harbour", genre: "Hard Rock"), track("3", artist: "Paper Harbour", genre: "Rock")]
        let r = report(tracks, mb: mb([("Paper Harbour", Self.blackMetal)]))
        #expect(r.rows.allSatisfy { $0.explanation.key == .rows(.mbGenre, ["black"]) })
    }

    @Test func anArtistWithAnMBGenericStyleGetsNoAppleMajority() {
        let electronic = ArtistStyleBook.Lookup.verified(id: "mb-2", matchedReleaseGroups: ["rg-2"], genres: [.init(name: "electronic", count: 3)])
        let tracks = [
            track("1", artist: "Paper Harbour", genre: "Indie Rock"), track("2", artist: "Paper Harbour", genre: "Indie Rock"),
            track("3", artist: "Paper Harbour", genre: "Indie Rock"), track("4", artist: "Paper Harbour", genre: "Alternative"),
        ]
        let r = report(tracks, mb: mb([("Paper Harbour", electronic)]))
        #expect(r.rows.map(\.explanation.key) == [
            .rows(.appleGenre, ["altindie"]), .rows(.appleGenre, ["altindie"]), .rows(.appleGenre, ["altindie"]), .rows(.genericMB, ["electronic"]),
        ])
        #expect(r.rows.allSatisfy { $0.explanation.trace.contains(.init(layer: .appleConsensus, rowIDs: ["altindie"], outcome: .overriddenByMB)) },
                "停用共識也要留 trace，來源欄才說得出原因（simcodex R1 層級）")
    }

    /// `LibraryCheckUITests` 的前提：假曲庫處理前素面 1、身分未定 2（日文歌手的無詞曲推定日文，不計入）
    @Test func theUITestFixtureStartsWithOnePlainSongAndTwoOpenIdentities() {
        let r = report(LibraryCheckUITestFixture.tracks)
        #expect(r.composed.songs == 1)
        #expect(r.identity.songs == 2)
        #expect(r.rows.first { $0.track.persistentID == "LC04" }?.japaneseEstimate == .init(lyricsSongs: 1, japaneseSongs: 1))
    }

    /// codex review R1：同一首（persistentID 相同）出現兩次只算一票
    @Test func aRepeatedTrackIsOneVote() {
        let tracks = [track("1", artist: "Paper Harbour", genre: "Hard Rock"), track("1", artist: "Paper Harbour", genre: "Hard Rock"), track("2", artist: "Paper Harbour")]
        #expect(report(tracks).consensus.isEmpty)
    }

    @Test func aChosenStyleWinsOverTheConsensus() throws {
        let tracks = [track("1", artist: "Paper Harbour", genre: "Hard Rock"), track("2", artist: "Paper Harbour", genre: "Hard Rock"), track("3", artist: "Paper Harbour", genre: "Rock")]
        let decided = try ArtistDecisionBook().deciding(.style(rowID: "gothic"), forArtists: ["Paper Harbour"], at: Self.base)
        #expect(report(tracks, decisions: decided).rows.allSatisfy { $0.explanation.key == .rows(.userStyle, ["gothic"]) })
    }

    @Test func withoutAMajorityEachSongKeepsItsOwnGenre() {
        let tracks = [track("1", artist: "Paper Harbour", genre: "Hard Rock"), track("2", artist: "Paper Harbour", genre: "Gothic"), track("3", artist: "Paper Harbour", genre: "Rock")]
        let r = report(tracks)
        #expect(r.rows.map(\.explanation.key) == [.rows(.appleGenre, ["hardrock"]), .rows(.appleGenre, ["gothic"]), .none])
        #expect(r.consensus.isEmpty)
    }
}
