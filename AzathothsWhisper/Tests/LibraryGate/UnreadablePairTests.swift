import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.6（/thecure 2026-10-28 改）：G1 對比不及格的「背景×配色」硬禁止——組合保留、只排除那幾格
@Suite("Unreadable backdrop palette pairs")
struct UnreadablePairTests {
    private static var auditableProfiles: [(name: String, profile: SongProfile)] {
        ReadabilityAudit.profiles.filter { Composer.isComposable($0.profile) }
    }

    @Test func theBannedPairsAreTheTwelveMeasuredFailuresAndThePolicyIsVersionTwo() {
        #expect(ReadabilityPolicy.version == 2)
        #expect(ReadabilityPolicy.unreadablePairs.count == 12)
        let ids = Set(LyricsFXCatalog.all.map(\.id))
        for pair in ReadabilityPolicy.unreadablePairs {
            #expect(ids.contains(pair.backdrop) && ids.contains(pair.palette), "\(pair)")
        }
    }

    @Test func aBannedPaletteIsNeverOfferedEvenWhenNothingElseFits() {
        let lonely = SongProfile(axes: [:], tags: [.jpopKira])
        for pair in ReadabilityPolicy.unreadablePairs {
            let offered = Composer.compatiblePalettes(LyricsFXCatalog.all, backdrop: pair.backdrop, profile: lonely).map(\.id)
            #expect(!offered.contains(pair.palette), "沒有合格配色時的退路也不得放回被禁配對：\(pair)")
        }
    }

    /// 硬不可達：每個可稽核的 profile 連播 64 次（每次排除上一次），實抽配方都不含被禁配對
    @Test(arguments: auditableProfiles.map(\.name))
    func noRecipeEverDrawsABannedPair(name: String) throws {
        let profile = try #require(Self.auditableProfiles.first { $0.name == name }?.profile)
        var previous: ComposedRecipe?
        for seed in 0..<UInt64(64) {
            guard case .composed(let recipe) = Composer.compose(profile: profile, seed: FXHash.fnv1a64(name) ^ seed, avoiding: previous) else {
                Issue.record("\(name) seed \(seed)：組不出")
                continue
            }
            #expect(!ReadabilityPolicy.isUnreadable(backdrop: recipe.backdrop, palette: recipe.palette), "\(name)：\(recipe.backdrop)＋\(recipe.palette)")
            previous = recipe
        }
    }

    /// 禁止後每個抽得到的背景仍有配色；被禁止波及的背景至少留兩種，「每次換一套」不失真
    @Test(arguments: auditableProfiles.map(\.name))
    func everyReachableBackdropKeepsPalettes(name: String) throws {
        let profile = try #require(Self.auditableProfiles.first { $0.name == name }?.profile)
        let space = try #require(PlayableSpace.of(profile), "\(name)：禁止後變成組不出")
        let shortlist = Set(Composer.candidates(LyricsFXCatalog.all.filter { $0.slot == .palette }, profile).map(\.id))
        for (backdrop, palettes) in space.paletteByBackdrop {
            #expect(!palettes.isEmpty, "\(name)：\(backdrop) 沒有配色")
            let banned = Set(ReadabilityPolicy.unreadablePairs.filter { $0.backdrop == backdrop }.map(\.palette))
            if !banned.isDisjoint(with: shortlist) {
                #expect(palettes.count >= 2, "\(name)：\(backdrop) 禁止後只剩 \(palettes)")
            }
        }
    }
}
