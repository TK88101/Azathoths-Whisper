import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 3 計劃 V1、V3：第三批樂團（Nu-metal）的簽字對照

@Suite("B2 batch 3 signed fixture")
struct B2BatchThreeSignedFixtureTests {
    @Test func everySignedBandAndAliasResolvesToItsSignedProfile() throws {
        SignedBatchChecks.everyBandAndAliasResolvesToItsSignedProfile(try SignedBatchFile.load(batch: 3))
    }

    @Test func everySignedBandIsInTheFourthTableBatch() throws {
        #expect(Set(SongProfileResolver.batchFour.map(\.name)) == Set(try SignedBatchFile.load(batch: 3).bands.map(\.name)))
    }

    @Test func theAppOffersExactlyTheSignedCandidatesInEverySlot() throws {
        SignedBatchChecks.theAppOffersExactlyTheSignedCandidatesInEverySlot(try SignedBatchFile.load(batch: 3))
    }

    /// 合作寫法明列「不歸任何一團」的，就真的不能命中覆寫表
    @Test func unassignedSpellingsStayOutOfTheOverrideTable() throws {
        for entry in try SignedBatchFile.load(batch: 3).unassigned ?? [] {
            #expect(SongProfileResolver.overrides[SongProfileResolver.normalizedArtist(entry.spelling)] == nil, "\(entry.spelling)")
        }
    }

    /// 簽字對象＝新團＋連帶團，名稱不重複、合計不超過 12 個（B2 批 3 計劃 §4.3）
    @Test func theBatchSignsAtMostTwelveDistinctSubjects() throws {
        let file = try SignedBatchFile.load(batch: 3)
        let names = file.bands.map(\.name) + (file.linked ?? []).map(\.name)
        #expect(Set(names).count == names.count, "重複的簽字對象")
        #expect(names.count <= 12)
    }
}

// B2 批 3 計劃 §2.4 N1／附錄 B P10：工業金屬與 Nu 系不共用任何元件
@Suite("B2 batch 3 industrial boundary")
struct B2BatchThreeIndustrialBoundaryTests {
    @Test func noBandOfTheBatchIsEligibleForAnIndustrialComponent() {
        for band in SongProfileResolver.batchFour {
            let industrial = LyricsFXCatalog.all.filter { $0.tags.contains(.industrial) && Composer.fit($0, band.profile) > 0 }
            #expect(industrial.isEmpty, "\(band.name) 抽得到工業元件：\(industrial.map(\.id))")
        }
    }

    /// N1 的機械保證（計劃 §2.4 第 2 條）：把連帶團的標籤從整份目錄拿掉（它們選「現狀」或「單色」時最多就是這樣），
    /// 本批新團每槽的合格集合一個都不變；拿掉後變成沒有標籤的元件視同移除（否則會變成人人可抽）
    @Test func takingTheLinkedBandsTagsOutOfTheCatalogLeavesTheNewBandsUntouched() throws {
        let linkedTags = Set(try SignedBatchFile.load(batch: 3).linked?.compactMap { linked in
            SongProfileResolver.bandTable.first { $0.name == linked.name }?.profile.tags
        }.flatMap { $0 } ?? [])
        #expect(linkedTags == [.nu, .hardcore])
        let stripped = LyricsFXCatalog.all.compactMap { component -> FXComponent? in
            let tags = component.tags.subtracting(linkedTags)
            if tags.isEmpty, !component.tags.isEmpty { return nil }
            return FXComponent(id: component.id, slot: component.slot, vector: component.vector, tags: tags, req: component.req, forbid: component.forbid, payload: component.payload)
        }
        for band in SongProfileResolver.batchFour {
            for slot in FXSlot.allCases {
                let before = Set(LyricsFXCatalog.all.filter { $0.slot == slot && Composer.fit($0, band.profile) > 0 }.map(\.id))
                let after = Set(stripped.filter { $0.slot == slot && Composer.fit($0, band.profile) > 0 }.map(\.id))
                #expect(before == after, "\(band.name) \(slot)")
            }
        }
    }

    @Test func theBatchsNewBandsCarryNoTagSharedWithTheLinkedNuBands() {
        for band in SongProfileResolver.batchFour {
            #expect(band.profile.tags.isDisjoint(with: [.nu, .hardcore]), "\(band.name)")
        }
    }
}

// B2 批 3 計劃 T6：對照組——性格相反的團不會抽到對方的東西；P15 的修正
@Suite("B2 batch 3 contrasts")
struct B2BatchThreeContrastTests {
    /// 同一團連抽 400 次（帶「排除上一次」）用到的所有元件
    private func drawn(_ artist: String) -> Set<String> {
        guard case .profile(let profile) = SongProfileResolver.resolve(artist: artist, genre: nil) else {
            Issue.record("\(artist) 不在覆寫表"); return []
        }
        var ids: Set<String> = []
        var previous: ComposedRecipe?
        for seed in 1...400 as ClosedRange<UInt64> {
            guard case .composed(let recipe) = Composer.compose(profile: profile, seed: seed, avoiding: previous) else {
                Issue.record("\(artist) 抽到 mono"); break
            }
            ids.formUnion(recipe.componentIDs)
            previous = recipe
        }
        return ids
    }

    @Test func theDigitalBandAndTheMaskedBandShareNoSignatureComponents() {
        let linkinPark = drawn("Linkin Park"), slipknot = drawn("Slipknot")
        #expect(linkinPark.isSuperset(of: ["SpaceMono", "scan", "rgbsplit", "hybridGrey"]))
        #expect(linkinPark.isDisjoint(with: ["Elite", "slam", "film", "xerox", "rust", "ashGrey", "misreg"]))
        #expect(slipknot.isSuperset(of: ["Elite", "rust", "ashGrey"]))
        #expect(slipknot.isDisjoint(with: ["SpaceMono", "Grotesk", "scan", "grid", "type", "flip", "rgbsplit", "terminal", "hybridGrey"]))
    }

    @Test func theStreetBandAndTheGothicBandShareNothingButTheEmptyDefaults() {
        let limpBizkit = drawn("Limp Bizkit"), evanescence = drawn("Evanescence")
        #expect(limpBizkit.isSuperset(of: ["Bangers", "kick", "hazard"]))
        #expect(evanescence.isSuperset(of: ["Mirage", "Cinzel", "shafts", "rise"]))
        #expect(limpBizkit.intersection(evanescence).isSubset(of: ["none", "void"]))
    }

    /// P15：黑金屬已經在用的元件不借給 Slipknot
    @Test func slipknotDoesNotBorrowTheBlackMetalComponents() {
        #expect(drawn("Slipknot").isDisjoint(with: ["Catacombs", "negative"]))
    }

    /// P15：Ill Niño 是拉丁風格，字與停留效果不與其他另類金屬團共用
    @Test func illNinoKeepsItsLatinLettering() {
        let illNino = drawn("Ill Niño")
        #expect(illNino.isSuperset(of: ["Barrio", "AlfaSlab", "sangre", "flicker"]))
        #expect(illNino.isDisjoint(with: ["Anton", "Oswald", "Bebas", "shake"]))
    }
}
