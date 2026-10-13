import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 2 計劃 §4.2、V4：加新一批的元件時，既有樂團抽得到的東西只准在使用者簽過的地方變

@Suite("Playable space")
struct PlayableSpaceTests {
    private static let seedsPerBand: UInt64 = 2_000

    /// 列舉有沒有漏：實抽（含「排除上一次」的連抽）的每個元件都要落在列舉的空間裡
    @Test func everythingComposeDrawsIsInsideTheEnumeratedSpace() {
        for band in SongProfileResolver.bandTable {
            let space = PlayableSpace.of(band.profile)
            var previous: ComposedRecipe?
            for seed in 1...Self.seedsPerBand {
                guard case .composed(let recipe) = Composer.compose(profile: band.profile, seed: seed, avoiding: previous) else {
                    #expect(space == nil, "\(band.name) 抽到 mono，列舉卻說可組合")
                    break
                }
                guard let space else { Issue.record("\(band.name) 抽到組合風格，列舉卻說是 mono"); break }
                let inside = space.font.contains(recipe.font) && space.backdrop.contains(recipe.backdrop) && space.enter.contains(recipe.enter)
                    && space.exit.contains(recipe.exit) && space.fx1.contains(recipe.fx1) && space.fx2.contains(recipe.fx2)
                    && (space.paletteByBackdrop[recipe.backdrop] ?? []).contains(recipe.palette)
                if !inside { Issue.record("\(band.name) seed \(seed)：\(recipe.componentIDs.sorted()) 不在列舉內"); break }
                previous = recipe
            }
        }
    }

    /// 「排除上一次」的實際範圍：必選五槽與第一效果避開上一次的同槽元件（還有別的可抽時）；
    /// 第二效果只避開當次的第一效果，不避上一次的第二效果
    @Test func avoidingThePreviousRecipeIsPerSlotAndSkipsTheSecondEffect() {
        var secondEffectRepeated = false
        for band in SongProfileResolver.bandTable {
            guard let space = PlayableSpace.of(band.profile) else { continue }
            var previous: ComposedRecipe?
            for seed in 1...200 as ClosedRange<UInt64> {
                guard case .composed(let recipe) = Composer.compose(profile: band.profile, seed: seed, avoiding: previous) else { break }
                if let previous {
                    if space.font.count > 1 { #expect(recipe.font != previous.font, "\(band.name) font") }
                    if space.backdrop.count > 1 { #expect(recipe.backdrop != previous.backdrop, "\(band.name) backdrop") }
                    if space.enter.count > 1 { #expect(recipe.enter != previous.enter, "\(band.name) enter") }
                    if space.exit.count > 1 { #expect(recipe.exit != previous.exit, "\(band.name) exit") }
                    if space.fx1.count > 1 { #expect(recipe.fx1 != previous.fx1, "\(band.name) fx1") }
                    if (space.paletteByBackdrop[recipe.backdrop] ?? []).count > 1 { #expect(recipe.palette != previous.palette, "\(band.name) palette") }
                    if recipe.fx2 == previous.fx2, space.fx2.count > 1 { secondEffectRepeated = true }
                }
                if recipe.fx2 != FXEffect.none.rawValue { #expect(recipe.fx2 != recipe.fx1, "\(band.name) 兩個效果相同") }
                previous = recipe
            }
        }
        #expect(secondEffectRepeated, "第二效果不避上一次的第二效果（現行為）；若改成會避，連同 F3b 的描述一起改")
    }
}

@Suite("Existing band candidates")
struct ExistingBandCandidatesTests {
    /// 重產基線：`TEST_RUNNER_AZW_PRINT_FX_BASELINE=<commit> xcodebuild test -only-testing:…/printTheBaseline()`，
    /// 從輸出取兩個標記之間的那一行存成 `Tests/Fixtures/LyricsFX/band-candidates-baseline.json`（app 宿主測試寫不了專案目錄）
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AZW_PRINT_FX_BASELINE"] != nil))
    func printTheBaseline() throws {
        let baseline = BandCandidatesBaseline(
            schema: 1, sourceRevision: ProcessInfo.processInfo.environment["AZW_PRINT_FX_BASELINE"] ?? "",
            generatedBy: "ExistingBandCandidatesTests/printTheBaseline()",
            bands: SongProfileResolver.bandTable.map(BandCandidatesBaseline.current(of:))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print("<<<FXBASELINE\n\(String(decoding: try encoder.encode(baseline), as: UTF8.self))\nFXBASELINE>>>")
    }

    @Test func theBaselineCoversEveryBandThatWasInTheTableWhenItWasTaken() throws {
        let baseline = try BandCandidatesBaseline.load()
        #expect(baseline.schema == 1)
        // B2 批 4 計劃 §2.7：基線在批 3 合併後的 main（c6e0a53）重產
        #expect(baseline.sourceRevision == "c6e0a53")
        #expect(Set(baseline.bands.map(\.name)) == Set((SongProfileResolver.batchOne + SongProfileResolver.batchTwo + SongProfileResolver.batchThree + SongProfileResolver.batchFour).map(\.name)))
    }

    /// 合格集合或可抽空間與基線不同的既有團，必須正好是各批對照檔裡簽了「新版」或「單色」的連帶團，而且變成的樣子就是簽的那個樣子；
    /// 簽「現狀」的與其他團一樣要零差異
    @Test func existingBandsOnlyChangeWhereTheUserSignedIt() throws {
        let baseline = try BandCandidatesBaseline.load()
        let linked = Dictionary(uniqueKeysWithValues: try SignedBatchFile.linkedBands(batches: Self.batchesAfterTheBaseline).map { ($0.name, $0) })
        var changed: Set<String> = []
        for before in baseline.bands {
            guard let band = SongProfileResolver.bandTable.first(where: { $0.name == before.name }) else {
                Issue.record("\(before.name) 從覆寫表消失"); continue
            }
            let now = BandCandidatesBaseline.current(of: band)
            guard now != before else { continue }
            changed.insert(before.name)
            let detail = switch (now.playable, before.playable) {
            case (let space?, let was?): space.differences(from: was).joined(separator: "；")
            case (nil, nil): "仍是 mono，但合格集合變了"
            case (nil, _): "變成 mono"
            case (_, nil): "由 mono 變成組合風格"
            }
            guard let signed = linked[before.name], signed.decision != .current else { Issue.record("\(before.name) 沒簽過卻變了：\(detail)"); continue }
            #expect(now.playable == signed.playable, "\(before.name) 抽得到的東西與簽字的不同：\(detail)")
            if signed.decision == .new { #expect(now.eligible == signed.eligible, "\(before.name) 的合格集合與簽字的不同") }
        }
        let expected = Set(linked.values.filter { $0.decision != .current }.map(\.name))
        #expect(changed == expected, "簽了要變卻沒變的團：\(expected.subtracting(changed).sorted())")
    }

    /// 基線之後才簽的批次（基線已含批 3 的結果，B2 批 4 計劃 §2.7）
    static let batchesAfterTheBaseline = [4]

    /// 批 1–3 的新團是使用者在真視窗簽過的，後面的批次不得把它們列為連帶
    @Test func theBandsSignedInEarlierBatchesAreNeverLinked() throws {
        let linked = Set(try SignedBatchFile.linkedBands(batches: Self.batchesAfterTheBaseline).map(\.name))
        #expect(linked.isDisjoint(with: (SongProfileResolver.batchTwo + SongProfileResolver.batchThree + SongProfileResolver.batchFour).map(\.name)))
    }

    /// 連帶團必須是基線裡就有的既有團；本批的新團不得冒充連帶（B2 批 3 計劃 §4.3、附錄 A.1 #2）
    @Test func linkedBandsAreExistingBandsAndNeverThisBatchsNewBands() throws {
        let baseline = Set(try BandCandidatesBaseline.load().bands.map(\.name))
        let linked = try SignedBatchFile.linkedBands(batches: Self.batchesAfterTheBaseline).map(\.name)
        #expect(Set(linked).isSubset(of: baseline), "不在基線的連帶團：\(Set(linked).subtracting(baseline).sorted())")
        #expect(Set(linked).isDisjoint(with: SongProfileResolver.batchFive.map(\.name)))
    }
}
