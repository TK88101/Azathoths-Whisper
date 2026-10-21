import Testing

@testable import AzathothsWhisper

// 候選排序計劃 §3.2–§3.3：只看中繼資料排出前 3 名；只在對齊通過者之間挑。名稱全為編造
@Suite("CandidateRanking")
struct CandidateRankingTests {
    static let query = TimingQuery(artist: "Lantern Band", title: "Paper Boats", duration: 200)

    static func candidate(_ id: String, artist: String = "Lantern Band", title: String = "Paper Boats", duration: Double? = 200) -> TimingCandidate {
        TimingCandidate(track: MatchedTrack(artist: artist, title: title, duration: duration), id: id)
    }

    private func ranked(_ candidates: [TimingCandidate]) -> [String] {
        TimingCandidate.ranked(candidates, for: Self.query).map(\.id)
    }

    // MARK: rankCandidates

    @Test func anExactMatchBeatsAOneLetterTitleDifference() {
        #expect(ranked([Self.candidate("near", title: "Paper Boat"), Self.candidate("exact")]) == ["exact", "near"])
    }

    @Test func aFoldedSpellingIsNotExact() {
        // 正規化後相等（距離 0），但大小寫與標點不同：完全一致者優先
        #expect(ranked([Self.candidate("folded", artist: "LANTERN-BAND"), Self.candidate("exact")]) == ["exact", "folded"])
    }

    @Test func extraWhitespaceStillCountsAsExact() {
        #expect(ranked([Self.candidate("folded", artist: "Lantern-Band"), Self.candidate("spaced", artist: " Lantern  Band ")]) == ["spaced", "folded"])
    }

    @Test func titleDistanceComesBeforeArtistDistance() {
        let titleOff = Self.candidate("titleOff", title: "Paper Boat")
        let artistOff = Self.candidate("artistOff", artist: "Lanterns Band")
        #expect(ranked([titleOff, artistOff]) == ["artistOff", "titleOff"])
    }

    @Test func artistDistanceComesBeforeDuration() {
        let artistOff = Self.candidate("artistOff", artist: "Lanterns Band", title: "Paper-Boats", duration: 200)
        let farther = Self.candidate("farther", title: "Paper-Boats", duration: 202.5)
        #expect(ranked([artistOff, farther]) == ["farther", "artistOff"])
    }

    @Test func aCloserDurationWins() {
        let far = Self.candidate("far", title: "PAPER BOATS", duration: 202)
        let close = Self.candidate("close", title: "PAPER BOATS", duration: 200.5)
        #expect(ranked([far, close]) == ["close", "far"])
    }

    @Test func tiesKeepTheSourceOrder() {
        #expect(ranked([Self.candidate("b"), Self.candidate("a"), Self.candidate("c")]) == ["b", "a", "c"])
    }

    @Test func aCollaborationCountsTheClosestSingleArtist() {
        // 整串差很多、拆開後有一位完全相同：歌手距離取兩者較小＝0
        let collaboration = Self.candidate("collab", artist: "Lantern Band, Someone Else", title: "Paper Boat")
        let artistOff = Self.candidate("artistOff", artist: "Lanterns Band", title: "Paper Boat")
        #expect(ranked([artistOff, collaboration]) == ["collab", "artistOff"])
    }

    @Test func onlyTheTopThreeAreKept() {
        let ids = ["a", "b", "c", "d"]
        #expect(ranked(ids.map { Self.candidate($0) }) == ["a", "b", "c"])
    }

    @Test func nonMatchingCandidatesAreDropped() {
        let wrongSong = Self.candidate("wrong", title: "Other Song")
        let noDuration = Self.candidate("noDuration", duration: nil)
        let tooLong = Self.candidate("tooLong", duration: 204)
        #expect(ranked([wrongSong, noDuration, tooLong, Self.candidate("ok")]) == ["ok"])
    }

    @Test func duplicatesAreRemovedBeforeTheFirstTenAreTaken() {
        // 前 10 筆全是同一個 id：去重後第 11 筆的唯一候選仍會被看
        let repeated = (0..<10).map { _ in Self.candidate("dup", title: "Other Song") }
        #expect(ranked(repeated + [Self.candidate("eleventh")]) == ["eleventh"])
    }

    @Test func onlyTheFirstTenUniqueCandidatesAreConsidered() {
        let misses = (0..<10).map { Self.candidate("miss\($0)", title: "Other Song") }
        #expect(ranked(misses + [Self.candidate("eleventh")]).isEmpty)
    }

    @Test func aDuplicateIDKeepsItsFirstOccurrence() {
        let first = Self.candidate("same", duration: 202)
        let second = Self.candidate("same", duration: 200)
        let ranking = TimingCandidate.ranked([first, second], for: Self.query)
        #expect(ranking.map(\.track.duration) == [202])
    }

    // MARK: pickAccepted

    static func alignment(music: Double, lrc: Double) -> LRCAligner.Alignment {
        LRCAligner.Alignment(anchors: [1, 2, 3], musicRate: music, lrcCoverage: lrc)
    }

    @Test func theHigherMusicRateWins() {
        let accepted = [
            RankedAlignment(rank: 0, alignment: Self.alignment(music: 0.8, lrc: 1)),
            RankedAlignment(rank: 1, alignment: Self.alignment(music: 0.9, lrc: 0.6)),
        ]
        #expect(RankedAlignment.best(of: accepted)?.rank == 1)
    }

    @Test func coverageBreaksAMusicRateTie() {
        let accepted = [
            RankedAlignment(rank: 0, alignment: Self.alignment(music: 0.9, lrc: 0.7)),
            RankedAlignment(rank: 2, alignment: Self.alignment(music: 0.9, lrc: 0.8)),
        ]
        #expect(RankedAlignment.best(of: accepted)?.rank == 2)
    }

    @Test func theBetterRankBreaksAFullTie() {
        let accepted = [
            RankedAlignment(rank: 2, alignment: Self.alignment(music: 0.9, lrc: 0.8)),
            RankedAlignment(rank: 1, alignment: Self.alignment(music: 0.9, lrc: 0.8)),
        ]
        #expect(RankedAlignment.best(of: accepted)?.rank == 1)
    }

    @Test func nothingAcceptedPicksNothing() {
        #expect(RankedAlignment.best(of: []) == nil)
    }

    @Test func onlyAFullAlignmentIsPerfect() {
        #expect(RankedAlignment(rank: 0, alignment: Self.alignment(music: 1, lrc: 1)).isPerfect)
        #expect(!RankedAlignment(rank: 0, alignment: Self.alignment(music: 1, lrc: 0.99)).isPerfect)
    }
}
