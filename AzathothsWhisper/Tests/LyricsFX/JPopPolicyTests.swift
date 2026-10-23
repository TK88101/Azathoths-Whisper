import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥a J-Pop 計劃 §4.2、§6.2：三變體、選變體、由配色推回變體、變體鎖定目錄
@Suite("J-Pop policy")
struct JPopPolicyTests {
    @Test func eachVariantCarriesExactlyItsOwnPrivateTagAndAllTenAxes() {
        for variant in JPopVariant.allCases {
            #expect(variant.profile.tags == [variant.tag], "\(variant)")
            #expect(Set(variant.profile.axes.keys) == Set(FXAxis.allCases), "\(variant)")
            #expect(variant.profile.axes.values.allSatisfy { (0...1).contains($0) }, "\(variant)")
        }
        #expect(Set(JPopVariant.allCases.map(\.tag)) == FXTag.jpopFamily)
    }

    @Test func withoutAPreviousVariantEveryVariantShowsUpAndTheChoiceIsDeterministic() {
        let picks = (0..<1_000 as Range<UInt64>).map { JPopPolicy.variant(seed: FXHash.fnv1a64("s\($0)"), previous: nil) }
        #expect(Set(picks) == Set(JPopVariant.allCases))
        #expect(JPopPolicy.variant(seed: 42, previous: nil) == JPopPolicy.variant(seed: 42, previous: nil))
    }

    @Test(arguments: JPopVariant.allCases)
    func theSameVariantNeverComesTwiceInARow(previous: JPopVariant) {
        let picks = Set((0..<300 as Range<UInt64>).map { JPopPolicy.variant(seed: FXHash.fnv1a64("s\($0)"), previous: previous) })
        #expect(!picks.contains(previous))
        #expect(picks.count == 2)
    }

    @Test func everyJPopPaletteBelongsToExactlyOneVariant() {
        for variant in JPopVariant.allCases {
            let palettes = JPopPolicy.catalog(variant).filter { $0.slot == .palette }
            #expect(!palettes.isEmpty, "\(variant)")
            for palette in palettes { #expect(JPopVariant(paletteID: palette.id) == variant, "\(palette.id)") }
        }
        #expect(JPopVariant(paletteID: "britRed") == nil)
        #expect(JPopVariant(paletteID: "no-such-palette") == nil)
        #expect(JPopVariant(paletteID: "") == nil)
    }

    @Test func theVariantCatalogsAreDisjointApartFromNoneAndNeverContainVoid() {
        let catalogs = JPopVariant.allCases.map { Set(JPopPolicy.catalog($0).map(\.id)) }
        for i in catalogs.indices {
            #expect(!catalogs[i].contains("void"))
            for j in catalogs.indices where j > i { #expect(catalogs[i].intersection(catalogs[j]) == [FXEffect.none.rawValue]) }
        }
    }

    @Test(arguments: JPopVariant.allCases)
    func eachVariantCatalogIsValidAndAlwaysComposes(variant: JPopVariant) {
        let catalog = JPopPolicy.catalog(variant)
        #expect(CatalogValidator.problems(in: catalog).isEmpty, "\(CatalogValidator.problems(in: catalog))")
        #expect(PlayableSpace.of(variant.profile, catalog: catalog) != nil)
        for seed in 1...200 as ClosedRange<UInt64> {
            guard case .composed(let recipe) = Composer.compose(profile: variant.profile, seed: seed, catalog: catalog) else {
                Issue.record("\(variant) seed \(seed) 退成 mono"); return
            }
            #expect(JPopVariant(paletteID: recipe.palette) == variant)
        }
    }

    /// 既有 profile 用整份目錄：J-Pop 元件只帶私有標籤，對它們不合格
    @Test func jpopComponentsNeverFitAnExistingProfile() {
        let jpop = LyricsFXCatalog.all.filter { !$0.tags.isDisjoint(with: FXTag.jpopFamily) }
        #expect(!jpop.isEmpty)
        for (name, profile) in RecipeGoldenTests.existingProfiles {
            for component in jpop { #expect(Composer.fit(component, profile) == 0, "\(component.id) 合 \(name)") }
        }
    }

    /// ballad 只有 none 效果：停留走既有的低 aggression 權重（計劃 §4.3、ACCEPTANCE I-65）
    @Test func theBalladHoldsWithTheExistingCalmWeights() {
        let ballad = JPopPolicy.catalog(.ballad)
        #expect(ballad.filter { $0.slot == .fx }.map(\.id) == [FXEffect.none.rawValue])
        for seed in 1...20 as ClosedRange<UInt64> {
            guard case .composed(let recipe) = Composer.compose(profile: JPopVariant.ballad.profile, seed: seed, catalog: ballad),
                  let style = ResolvedStyle(recipe) else { Issue.record("seed \(seed) 沒有 ballad 配方"); return }
            #expect(style.personality.hold.map { "\($0.0):\($0.1)" } == ["still:3.0", "drift:1.0", "float:1.0"])
        }
    }
}
