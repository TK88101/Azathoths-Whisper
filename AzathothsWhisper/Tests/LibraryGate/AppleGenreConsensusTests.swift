import Foundation
import Testing

@testable import AzathothsWhisper

// 增補計劃 §4.2（B）：同歌手 Apple 曲風共識。歌手名自編
@Suite("Apple genre consensus")
struct AppleGenreConsensusTests {
    private typealias Evidence = AppleGenreConsensus.Evidence

    private func evidence(_ family: String, _ tier: AppleGenreConsensus.Tier, _ ids: [String], times: Int) -> [Evidence] {
        Array(repeating: Evidence(familyKey: family, tier: tier, rowIDs: ids), count: times)
    }

    @Test func aStrictMajorityWins() throws {
        let table = AppleGenreConsensus.table(evidence("paper harbour", .genreRows, ["hardrock"], times: 3) + evidence("paper harbour", .genreRows, ["gothic"], times: 2))
        let vote = try #require(table["paper harbour"]?.genreRows)
        #expect(vote == .init(rowIDs: ["hardrock"], votes: 3, evidence: 5))
        #expect(table["paper harbour"]?.genericRows == nil)
    }

    @Test func halfIsNotAMajority() {
        let table = AppleGenreConsensus.table(evidence("paper harbour", .genreRows, ["hardrock"], times: 2) + evidence("paper harbour", .genreRows, ["gothic"], times: 2))
        #expect(table["paper harbour"] == nil)
    }

    @Test func aSingleSongIsNotEnoughEvidence() {
        #expect(AppleGenreConsensus.table(evidence("paper harbour", .genreRows, ["hardrock"], times: 1)).isEmpty)
    }

    @Test func aRowCombinationCountsAsOneChoice() throws {
        let table = AppleGenreConsensus.table(evidence("paper harbour", .genreRows, ["death", "melodeath"], times: 2) + evidence("paper harbour", .genreRows, ["death"], times: 1))
        #expect(try #require(table["paper harbour"]?.genreRows).rowIDs == ["death", "melodeath"])
    }

    @Test func eachTierAndEachFamilyIsCountedSeparately() throws {
        let table = AppleGenreConsensus.table(
            evidence("paper harbour", .genreRows, ["hardrock"], times: 2) + evidence("paper harbour", .genericRows, ["pop"], times: 3)
                + evidence("velvet lanterns", .genericRows, ["folk"], times: 2)
        )
        #expect(table["paper harbour"]?.genreRows?.rowIDs == ["hardrock"])
        #expect(table["paper harbour"]?.genericRows == .init(rowIDs: ["pop"], votes: 3, evidence: 3))
        #expect(table["velvet lanterns"]?.genreRows == nil)
        #expect(table["velvet lanterns"]?.genericRows?.rowIDs == ["folk"])
    }

    @Test(arguments: [
        (ProfileExplanation.Key.rows(.appleGenre, ["hardrock"]), AppleGenreConsensus.Tier.genreRows as AppleGenreConsensus.Tier?),
        (.rows(.genericApple, ["pop"]), .genericRows),
        (.rows(.mbGenre, ["hardrock"]), nil),
        (.rows(.genericMB, ["pop"]), nil),
        (.rows(.userStyle, ["punk"]), nil),
        (.rows(.appleConsensus, ["hardrock"]), nil),
        (.rows(.genericAppleConsensus, ["pop"]), nil),
        (.jpop, nil), (.signed("Mayhem"), nil), (.none, nil), (.pending, nil),
    ] as [(ProfileExplanation.Key, AppleGenreConsensus.Tier?)])
    func onlyTheSongsOwnAppleLayersAreEvidence(key: ProfileExplanation.Key, tier: AppleGenreConsensus.Tier?) {
        #expect(AppleGenreConsensus.evidenceTier(of: key) == tier, "共識結果本身不得再當證據（R3-2）；J-Pop、署名、使用者樣式、MB 也不算（R3-4）")
    }
}
