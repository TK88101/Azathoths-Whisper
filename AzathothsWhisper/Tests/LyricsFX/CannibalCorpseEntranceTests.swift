import Foundation
import Testing

@testable import AzathothsWhisper

// Cannibal Corpse 補進場（docs/plans/2026-11-01-cannibal-corpse-entrance.md v0.6 §4c；使用者 2026-11-02 拍板①、探針兩版簽字）：
// 只對 Cannibal 開一次性的目標值凍結例外——加私有標籤 `cannibal`，三個既有進場 drop／stamp／negative 同掛它。
// 標籤以 rawValue 取得，讓「標籤還不存在」是可編譯的行為紅燈（C0）
enum CannibalCorpse {
    static let name = "Cannibal Corpse"
    static let tag = FXTag(rawValue: "cannibal")
    static let entrances: Set<String> = ["drop", "negative", "stamp"]
    /// 改前（cf1c20a）三個進場各自的標籤；同掛只能「加 cannibal」，原標籤一個不少
    static let originalEntranceTags: [String: Set<FXTag>] = [
        "drop": [.horrormetal, .altmetal, .hardcore, .nu],
        "stamp": [.hardrock, .hardcore, .nu, .heavy, .thrash, .rapmetal, .altmetal, .latinmetal, .posthardcore],
        "negative": [.black],
    ]
    /// 目標值：十軸與原有兩個標籤逐位不變（原型 composer.js:244）
    static let axes: [FXAxis: Double] = [.raw: 0.7, .theatrical: 0.1, .cold: 0.1, .aggression: 1, .speed: 0.8, .elegance: 0, .decay: 0.8, .bright: 0]

    static var entry: SongProfileResolver.BandEntry? { SongProfileResolver.bandTable.first { $0.name == name } }
}

@Suite("Cannibal Corpse entrance")
struct CannibalCorpseEntranceTests {
    // MARK: C0

    @Test func thePrivateTagExistsAndNeverFlowsIntoGenreRows() throws {
        let tag = try #require(CannibalCorpse.tag, "還沒有 cannibal 標籤")
        #expect(SongProfileResolver.genreRowPrivateTags.contains(tag))
    }

    // MARK: C2 隔離

    @Test func onlyTheThreeSignedEntrancesCarryTheTagAndKeepTheirOriginalTags() throws {
        let tag = try #require(CannibalCorpse.tag)
        let carriers = LyricsFXCatalog.all.filter { $0.tags.contains(tag) }
        #expect(Set(carriers.map { "\($0.slot.rawValue):\($0.id)" }) == Set(CannibalCorpse.entrances.map { "enter:\($0)" }))
        for component in carriers {
            #expect(component.tags.subtracting([tag]) == CannibalCorpse.originalEntranceTags[component.id], "\(component.id) 的原標籤變了")
        }
    }

    @Test func noOtherProfileCarriesTheTag() throws {
        let tag = try #require(CannibalCorpse.tag)
        for band in SongProfileResolver.bandTable where band.name != CannibalCorpse.name {
            #expect(!band.profile.tags.contains(tag), "\(band.name)")
        }
        for row in SongProfileResolver.keywordRows + SongProfileResolver.genericRows {
            #expect(!row.tags.contains(tag), "\(row.id)")
        }
        for (name, profile) in ReadabilityAudit.profiles where name != CannibalCorpse.name {
            #expect(!profile.tags.contains(tag), "\(name)")
        }
        let death = try #require(SongProfileResolver.keywordRows.first { $0.id == "death" })
        #expect(death.representatives.contains(CannibalCorpse.name) && !death.tags.contains(tag), "death 列以 Cannibal 為代表團，聯集時必須扣掉私有標籤")
    }

    /// 對改前快照（C1，cf1c20a）逐 profile 逐槽比較：只准 Cannibal 的進場改變
    @Test func onlyCannibalsEntranceDiffersFromTheSnapshot() throws {
        let before = Dictionary(uniqueKeysWithValues: try ProfileCandidatesSnapshot.load().profiles.map { ($0.name, $0.candidates) })
        let now = Dictionary(uniqueKeysWithValues: ProfileCandidatesSnapshot.current().map { ($0.name, $0.candidates) })
        #expect(Set(before.keys) == Set(now.keys))
        for (name, candidates) in now {
            guard let was = before[name] else { continue }
            for slot in FXSlot.allCases.map(\.rawValue) where candidates[slot] != was[slot] {
                #expect(name == CannibalCorpse.name && slot == FXSlot.enter.rawValue, "\(name) 的 \(slot) 變了")
            }
        }
        #expect(now[CannibalCorpse.name]?[FXSlot.enter.rawValue] == CannibalCorpse.entrances.sorted())
    }

    @Test func jpopAndGenericCatalogsAreUntouched() throws {
        let tag = try #require(CannibalCorpse.tag)
        for variant in JPopVariant.allCases {
            #expect(JPopPolicy.catalog(variant).allSatisfy { !$0.tags.contains(tag) }, "\(variant)")
        }
        let generic = LyricsFXCatalog.all.filter { $0.tags.contains { $0.rawValue.hasPrefix("gen") } }
        #expect(!generic.isEmpty)
        for component in generic { #expect(component.tags.count == 1, "\(component.id) 的通用標籤不只一個") }
    }

    @Test func theTargetKeepsItsAxesAndOriginalTags() throws {
        let tag = try #require(CannibalCorpse.tag)
        let entry = try #require(CannibalCorpse.entry)
        #expect(entry.profile.axes == CannibalCorpse.axes)
        #expect(entry.profile.tags == [.death, .grind, tag])
        let resolution = SongProfileResolver.resolve(artist: CannibalCorpse.name, genre: nil, lyrics: .text(isJapanese: false))
        #expect(resolution == .signedBand(entry.profile))
    }

    // MARK: C3 可播放

    @Test func cannibalIsComposableWithExactlyTheThreeEntrances() throws {
        let entry = try #require(CannibalCorpse.entry)
        #expect(Composer.isComposable(entry.profile))
        let enter = LyricsFXCatalog.components(in: .enter).filter { Composer.fit($0, entry.profile) > 0 }.map(\.id)
        #expect(Set(enter) == CannibalCorpse.entrances)
    }

    /// V1：可播放；必選槽各 ≥ 2；每個可抽背景都有 ≥ 2 個可讀配色（同批 5）
    @Test func cannibalHasARealPlayableSpace() throws {
        let entry = try #require(CannibalCorpse.entry)
        let space = try #require(PlayableSpace.of(entry.profile), "仍是 mono")
        for slot in [space.font, space.backdrop, space.enter, space.exit] { #expect(slot.count >= 2) }
        for backdrop in space.backdrop { #expect((space.paletteByBackdrop[backdrop] ?? []).count >= 2, "\(backdrop)") }
    }

    // MARK: C8 可讀性

    /// 進場不影響背景／配色：Cannibal 抽得到的每組（背景, 配色）都已在 G1 的 `reachablePairs` 裡（改前就有，C2-③ 證明全部 profile 的背景、配色合格集合不變）
    @MainActor @Test func everyPairCannibalCanDrawIsAlreadyAudited() throws {
        let entry = try #require(CannibalCorpse.entry)
        let space = try #require(PlayableSpace.of(entry.profile))
        let audited = Set(LyricsFXContrastTests.reachablePairs.map { "\($0.backdrop)|\($0.palette)" })
        for (backdrop, palettes) in space.paletteByBackdrop {
            for palette in palettes { #expect(audited.contains("\(backdrop)|\(palette)"), "\(backdrop)＋\(palette)") }
        }
        #expect(ReadabilityPolicy.auditable.contains(.signed(CannibalCorpse.name)), "組得出的署名團自動列入稽核（預期變化）")
    }

    // MARK: C6 簽字對照檔（現有 `SignedBatchChecks` 只查 `bands`，連帶團沒有 tags 欄位，故由這裡負責）

    @Test func theBatchSixFileSignsOnlyCannibalWithWhatTheAppOffers() throws {
        let file = try SignedBatchFile.load(batch: 6)
        #expect(file.bands.isEmpty)
        let linked = try #require(file.linked)
        #expect(linked.map(\.name) == [CannibalCorpse.name])
        let signed = try #require(linked.first)
        #expect(signed.decision == .new)
        let entry = try #require(CannibalCorpse.entry)
        let now = BandCandidatesBaseline.current(of: entry)
        #expect(signed.eligible == now.eligible, "對照檔的合格集合（原型 ∩ app 目錄）與 app 不同")
        #expect(signed.playable == now.playable)
        #expect(signed.eligible?[FXSlot.enter.rawValue] == CannibalCorpse.entrances.sorted())
        // 原型有、app 沒搬的 4 個元件不得出現（export_signed.js --app-catalog）
        for (slot, id) in [("font", "AmazDooM"), ("font", "Butcherman"), ("font", "MetalMania"), ("exit", "split")] {
            #expect(signed.eligible?[slot]?.contains(id) == false, "\(slot):\(id)")
        }
    }

    @Test func resolvingAndComposingGivesAComposedStyle() throws {
        let entry = try #require(CannibalCorpse.entry)
        guard case .signedBand(let profile) = SongProfileResolver.resolve(artist: CannibalCorpse.name, genre: "Death Metal", lyrics: .text(isJapanese: false)) else {
            Issue.record("沒有解析成署名結果"); return
        }
        #expect(profile == entry.profile)
        guard case .composed(let recipe) = Composer.compose(profile: profile, seed: 7) else { Issue.record("組出 mono"); return }
        #expect(CannibalCorpse.entrances.contains(recipe.enter))
    }
}
