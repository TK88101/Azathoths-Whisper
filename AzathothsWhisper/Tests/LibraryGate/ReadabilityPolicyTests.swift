import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.6：production 只放版本化的組合清單與拒絕清單；測試端由 fixture 生成並斷言一致
@Suite("Readability policy")
struct ReadabilityPolicyTests {
    private static func key(_ ids: [String]) -> ProfileExplanation.AuditKey { .rows(ids.sorted()) }

    /// 兩份既有 fixture（⑥b 曲風列組合、⑦ 通用家族組合）的多列組合＝production 的組合清單
    @Test func theCombinationsAreExactlyTheFixtures() {
        let fixtures = (GenreRowTests.libraryCombinations + GenericLayerTests.libraryCombinations).filter { $0.count > 1 }.map { $0.sorted() }
        #expect(Set(fixtures) == Set(ReadabilityPolicy.combinations))
        #expect(ReadabilityPolicy.combinations.allSatisfy { $0 == $0.sorted() && $0.count > 1 })
        #expect(Set(ReadabilityPolicy.combinations).count == ReadabilityPolicy.combinations.count)
    }

    @Test func everyCombinationComposes() throws {
        let rows = SongProfileResolver.keywordRows + SongProfileResolver.genericRows
        for ids in ReadabilityPolicy.combinations {
            let chosen = rows.filter { ids.contains($0.id) }
            try #require(chosen.count == ids.count, "\(ids)：有列不存在")
            #expect(SongProfileResolver.compose(rows: chosen).map { Composer.isComposable($0) } == true, "\(ids)")
        }
    }

    @Test func acceptedAndRejectedNeverOverlapAndCoverEverythingAuditable() {
        #expect(ReadabilityPolicy.audited.isDisjoint(with: ReadabilityPolicy.rejected))
        #expect(ReadabilityPolicy.audited.union(ReadabilityPolicy.rejected) == ReadabilityPolicy.auditable)
    }

    @Test func singlesJPopAndComposableBandsAreAuditable() {
        let auditable = ReadabilityPolicy.auditable
        #expect(auditable.contains(.jpop))
        for row in SongProfileResolver.keywordRows + SongProfileResolver.genericRows { #expect(auditable.contains(.rows([row.id])), "\(row.id)") }
        for band in SongProfileResolver.bandTable {
            #expect(auditable.contains(.signed(band.name)) == Composer.isComposable(band.profile), "\(band.name)：組不出的團不能算稽核過")
        }
        for ids in ReadabilityPolicy.combinations { #expect(auditable.contains(Self.key(ids))) }
    }

    @Test func aRejectedCombinationFallsToTheNextLayerAndSaysWhy() {
        let rejected: Set<ProfileExplanation.AuditKey> = [.rows(["black"])]
        let explanation = SongProfileResolver.explain(
            artist: "Velvet Lanterns", genre: "Black Metal", lyrics: .text(isJapanese: false), artistGenres: .verified(["black metal"]), rejected: rejected
        )
        #expect(explanation.trace.first == .init(layer: .mbGenre, rowIDs: ["black"], outcome: .rejectedByReadability))
        #expect(explanation.trace.dropFirst().first == .init(layer: .appleGenre, rowIDs: ["black"], outcome: .rejectedByReadability))
        #expect(explanation.key == .none)
    }

    @Test func theVersionIsPositive() {
        #expect(ReadabilityPolicy.version >= 1)
    }
}
