import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 2 計劃 V1、V3：第二批樂團的簽字對照

@Suite("B2 batch 2 signed fixture")
struct B2BatchTwoSignedFixtureTests {
    @Test func everySignedBandAndAliasResolvesToItsSignedProfile() throws {
        let file = try SignedBatchFile.load(batch: 2)
        #expect(file.bands.count == 7)
        SignedBatchChecks.everyBandAndAliasResolvesToItsSignedProfile(file)
    }

    @Test func everySignedBandIsInTheThirdTableBatch() throws {
        #expect(Set(SongProfileResolver.batchThree.map(\.name)) == Set(try SignedBatchFile.load(batch: 2).bands.map(\.name)))
    }

    @Test func theAppOffersExactlyTheSignedCandidatesInEverySlot() throws {
        SignedBatchChecks.theAppOffersExactlyTheSignedCandidatesInEverySlot(try SignedBatchFile.load(batch: 2))
    }

    /// 合作寫法明列「不歸任何一團」的，就真的不能命中覆寫表
    @Test func unassignedSpellingsStayOutOfTheOverrideTable() throws {
        for entry in try SignedBatchFile.load(batch: 2).unassigned ?? [] {
            #expect(SongProfileResolver.overrides[SongProfileResolver.normalizedArtist(entry.spelling)] == nil, "\(entry.spelling)")
        }
    }
}

// B2 批 2 計劃 T6：對照組——性格相反的團不會抽到對方的東西；勒索信只給簽字時點名的團（P14）
@Suite("B2 batch 2 contrasts")
struct B2BatchTwoContrastTests {
    /// 同一團連抽 400 次（帶「排除上一次」）用到的所有元件
    private func drawn(_ artist: String) throws -> Set<String> {
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

    @Test func theAngryBandAndTheTenderBandShareNoSignatureComponents() throws {
        let riseAgainst = try drawn("Rise Against"), maydayParade = try drawn("Mayday Parade")
        #expect(riseAgainst.isSuperset(of: ["SairaStencil", "gigRed", "rip"]))
        #expect(riseAgainst.isDisjoint(with: ["Gochi", "bokeh", "daydream", "polaroid", "bob", "drift"]))
        #expect(maydayParade.isSuperset(of: ["Gochi", "bokeh", "polaroid"]))
        #expect(maydayParade.isDisjoint(with: ["SairaStencil", "gigRed", "rip", "xerox", "jitter", "shake"]))
    }

    @Test func skaAndPowerPopKeepTheirOwnLook() throws {
        let interrupters = try drawn("The Interrupters"), weezer = try drawn("Weezer")
        #expect(interrupters.isSuperset(of: ["checker", "skank", "twoTone"]))
        #expect(weezer.isSuperset(of: ["weezBlue", "Rubik"]))
        #expect(weezer.isDisjoint(with: ["checker", "skank", "twoTone", "twoToneLight", "gig", "xerox"]))
        #expect(interrupters.isDisjoint(with: ["weezBlue", "chalk", "skyGrad"]))
    }

    @Test(arguments: ["Blink-182", "Sum 41", "Green Day", "Ramones"])
    func theRansomNoteReachesTheBandsTheUserNamed(artist: String) throws {
        #expect(!(try drawn(artist)).isDisjoint(with: ["ransom", "ransomPop"]), "\(artist)")
    }

    @Test(arguments: ["The Offspring", "Good Charlotte", "Fall Out Boy", "Mayday Parade", "NOFX", "Rise Against", "The Interrupters", "Weezer"])
    func theRansomNoteStaysAwayFromEveryoneElse(artist: String) throws {
        #expect((try drawn(artist)).isDisjoint(with: ["ransom", "ransomPop"]), "\(artist)")
    }
}
