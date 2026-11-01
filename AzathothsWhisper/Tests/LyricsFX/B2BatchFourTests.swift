import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 4 計劃 V1、V3：第四批樂團（emo 群）的簽字對照

@Suite("B2 batch 4 signed fixture")
struct B2BatchFourSignedFixtureTests {
    @Test func everySignedBandAndAliasResolvesToItsSignedProfile() throws {
        SignedBatchChecks.everyBandAndAliasResolvesToItsSignedProfile(try SignedBatchFile.load(batch: 4))
    }

    @Test func everySignedBandIsInTheFifthTableBatch() throws {
        #expect(Set(SongProfileResolver.batchFive.map(\.name)) == Set(try SignedBatchFile.load(batch: 4).bands.map(\.name)))
    }

    @Test func theAppOffersExactlyTheSignedCandidatesInEverySlot() throws {
        SignedBatchChecks.theAppOffersExactlyTheSignedCandidatesInEverySlot(try SignedBatchFile.load(batch: 4))
    }

    /// 合作寫法明列「不歸任何一團」的，就真的不能命中覆寫表
    @Test func unassignedSpellingsStayOutOfTheOverrideTable() throws {
        for entry in try SignedBatchFile.load(batch: 4).unassigned ?? [] {
            #expect(SongProfileResolver.overrides[SongProfileResolver.normalizedArtist(entry.spelling)] == nil, "\(entry.spelling)")
        }
    }

    /// 簽字對象＝新團＋連帶團，名稱不重複、合計不超過 12 個；本批不連帶任何舊團（B2 批 4 計劃 §2.1）
    @Test func theBatchSignsAtMostTwelveDistinctSubjectsAndLinksNoExistingBand() throws {
        let file = try SignedBatchFile.load(batch: 4)
        let names = file.bands.map(\.name) + (file.linked ?? []).map(\.name)
        #expect(Set(names).count == names.count, "重複的簽字對象")
        #expect(names.count <= 12)
        #expect((file.linked ?? []).isEmpty, "本批不該有連帶團：\((file.linked ?? []).map(\.name))")
    }
}

// B2 批 4 計劃 §2.2 E1、§2.7：本批新團只帶本批私有標籤，新元件只帶私有標籤——既有團不被連帶
@Suite("B2 batch 4 isolation")
struct B2BatchFourIsolationTests {
    private static let earlierBatches = SongProfileResolver.batchOne + SongProfileResolver.batchTwo + SongProfileResolver.batchThree + SongProfileResolver.batchFour

    @Test func theBatchsBandsCarryOnlyTheBatchsPrivateTags() {
        for band in SongProfileResolver.batchFive {
            #expect(!band.profile.tags.isEmpty && band.profile.tags.isSubset(of: FXTag.emoFamily), "\(band.name)")
        }
    }

    @Test func noEarlierBandCarriesAPrivateTagOfThisBatch() {
        for band in Self.earlierBatches {
            #expect(band.profile.tags.isDisjoint(with: FXTag.emoFamily), "\(band.name)")
        }
    }

    /// P14：勒索信只給 77 龐克與指定的流行龐克團；本批各團也抽不到任何帶 industrial 標籤的元件
    @Test func noBandOfTheBatchIsEligibleForRansomOrAnIndustrialComponent() {
        for band in SongProfileResolver.batchFive {
            let eligible = LyricsFXCatalog.all.filter { Composer.fit($0, band.profile) > 0 }
            #expect(Set(eligible.map(\.id)).isDisjoint(with: ["ransom", "ransomPop"]), "\(band.name) 抽得到勒索信")
            #expect(eligible.allSatisfy { !$0.tags.contains(.industrial) }, "\(band.name) 抽得到工業元件")
        }
    }

    /// 「本批新元件」＝c6e0a53 基線 54 團合格集合聯集之外的元件。B2 批 5 重產基線後聯集會吞掉它們，
    /// 所以凍結成 `b2-batch4-new-components.json`（批 5 計劃 T1②；由 c6e0a53 基線算出一次，不再重算）
    private func newComponents() throws -> [FXComponent] {
        struct Frozen: Decodable { let components: [String] }
        let url = try GoldenFixtures.fixturesRoot().appendingPathComponent("LyricsFX/b2-batch4-new-components.json")
        let frozen = try JSONDecoder().decode(Frozen.self, from: Data(contentsOf: url)).components
        let new = LyricsFXCatalog.all.filter { frozen.contains("\($0.slot.rawValue):\($0.id)") }
        #expect(new.count == frozen.count, "凍結清單裡有元件已從目錄消失")
        return new
    }

    /// 基線之後加的元件分屬三批：批 4（emo 群私有標籤）、⑥a J-Pop（恰一個變體私有標籤；docs/plans/2026-10-23-lyrics-fx-jpop.md）、
    /// ⑦ 通用零件（恰一個通用家族標籤；docs/plans/2026-10-25-lyrics-fx-generic-parts.md）
    private func jpopVariant(of component: FXComponent) -> JPopVariant? {
        JPopVariant.allCases.first { component.tags == [$0.tag] }
    }

    private func genericRow(of component: FXComponent) -> SongProfileResolver.KeywordRow? {
        SongProfileResolver.genericRows.first { component.tags == $0.tags }
    }

    /// 新元件沒標籤＝人人可抽、帶舊標籤＝舊團被連帶；兩者都不准（計劃評審 R1 #1）
    @Test func everyNewComponentCarriesOnlyTheBatchsPrivateTags() throws {
        for component in try newComponents() {
            let isEmo = !component.tags.isEmpty && component.tags.isSubset(of: FXTag.emoFamily)
            #expect(isEmo || jpopVariant(of: component) != nil || genericRow(of: component) != nil,
                    "\(component.slot.rawValue):\(component.id) 的標籤 \(component.tags.map(\.rawValue).sorted())")
        }
    }

    /// 不留抽不到的死元件（計劃評審 R2 #9）：emo 群的元件要有本批的團抽得到，J-Pop 的元件要在它那個變體的目錄裡抽得到，通用元件要它那條通用列抽得到
    @Test func everyNewComponentIsReachableByABandOfTheBatch() throws {
        for component in try newComponents() {
            let reachable = if let variant = jpopVariant(of: component) {
                Composer.fit(component, variant.profile) > 0 && JPopPolicy.catalog(variant).contains { $0.id == component.id }
            } else if let row = genericRow(of: component) {
                SongProfileResolver.compose(rows: [row]).map { Composer.fit(component, $0) > 0 } ?? false
            } else {
                SongProfileResolver.batchFive.contains { Composer.fit(component, $0.profile) > 0 }
            }
            #expect(reachable, "\(component.slot.rawValue):\(component.id) 沒有任何本批的團抽得到")
        }
    }
}
