import Testing

@testable import AzathothsWhisper

// ⑦ 通用零件（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.2、§4.5-4）：通用家族的標籤只屬於通用元件與通用列，
// 署名團與既有曲風列一個都不帶；通用元件只帶恰一個通用標籤
@Suite("Generic families")
struct GenericFamilyTests {
    private func fx(_ id: String, tags: Set<FXTag>) -> FXComponent {
        FXComponent(id: id, slot: .fx, vector: [:], tags: tags, req: [:], forbid: [:], payload: .fx(.none))
    }

    @Test func thereAreNineGenericFamilies() {
        #expect(FXTag.genericFamily == [.genExperimental, .genElectronic, .genPop, .genFolk, .genIndustrial, .genAmbient, .genSacred, .genDarkwave, .genHipHop])
    }

    @Test func signedBandsCarryNoGenericTag() {
        for band in SongProfileResolver.bandTable {
            #expect(band.profile.tags.isDisjoint(with: FXTag.genericFamily), "\(band.name)")
        }
    }

    @Test func existingGenreRowsCarryNoGenericTag() {
        for row in SongProfileResolver.keywordRows {
            #expect(row.tags.isDisjoint(with: FXTag.genericFamily), "\(row.id)")
        }
    }

    @Test func aGenericComponentWithOneGenericTagIsAccepted() {
        #expect(CatalogValidator.problems(in: LyricsFXCatalog.all + [fx("genSolo", tags: [.genIndustrial])]) == [])
    }

    @Test func aGenericTagMixedWithAnotherTagIsRejected() {
        #expect(!CatalogValidator.problems(in: LyricsFXCatalog.all + [fx("genMixed", tags: [.genIndustrial, .black])]).isEmpty)
    }

    @Test func twoGenericTagsOnOneComponentAreRejected() {
        #expect(!CatalogValidator.problems(in: LyricsFXCatalog.all + [fx("genTwo", tags: [.genIndustrial, .genElectronic])]).isEmpty)
    }
}
