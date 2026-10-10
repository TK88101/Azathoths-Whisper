import Foundation

@testable import AzathothsWhisper

// B2 批 2 計劃 F3b、§4.2：一個樂團「畫面上真的會出現」的元件。
// 只呼叫 `Composer.candidates`／`compatiblePalettes`，不另寫一份排名或亮暗規則；
// 有沒有漏由 `PlayableSpaceTests` 拿 `Composer.compose` 的實抽結果對

/// 六槽各自抽得到的元件代號（已排序）。配色依抽到的背景而定；第二效果是拿掉第一效果後重取的前幾名
struct PlayableSpace: Codable, Equatable, Sendable {
    let font: [String]
    let backdrop: [String]
    let enter: [String]
    let exit: [String]
    let fx1: [String]
    let fx2: [String]
    let paletteByBackdrop: [String: [String]]

    /// `nil`＝任一必選槽沒有候選，整份是 mono
    static func of(_ profile: SongProfile, catalog: [FXComponent] = LyricsFXCatalog.all) -> PlayableSpace? {
        let shortlist = { (components: [FXComponent]) in Composer.candidates(components, profile).map(\.id) }
        let slot = { (slot: FXSlot) in shortlist(catalog.filter { $0.slot == slot }) }
        let backdrops = slot(.backdrop)
        let palettes = Dictionary(uniqueKeysWithValues: backdrops.map { backdrop in
            (backdrop, shortlist(Composer.compatiblePalettes(catalog, backdrop: backdrop, profile: profile)).sorted())
        })
        let (font, enter, exit) = (slot(.font), slot(.enter), slot(.exit))
        guard !font.isEmpty, !backdrops.isEmpty, !enter.isEmpty, !exit.isEmpty, palettes.values.allSatisfy({ !$0.isEmpty }) else { return nil }

        let effects = catalog.filter { $0.slot == .fx }
        let none = [FXEffect.none.rawValue]
        let first = slot(.fx).isEmpty ? none : slot(.fx)
        let second = first.flatMap { taken in
            let rest = shortlist(effects.filter { $0.id != taken })
            return rest.isEmpty ? none : rest
        }
        return PlayableSpace(
            font: font.sorted(), backdrop: backdrops.sorted(), enter: enter.sorted(), exit: exit.sorted(),
            fx1: first.sorted(), fx2: Set(second).sorted(), paletteByBackdrop: palettes
        )
    }

    /// 與另一份空間不同的地方（給失敗訊息用）
    func differences(from baseline: PlayableSpace) -> [String] {
        let pairs: [(String, [String], [String])] = [
            ("font", font, baseline.font), ("backdrop", backdrop, baseline.backdrop), ("enter", enter, baseline.enter),
            ("exit", exit, baseline.exit), ("fx1", fx1, baseline.fx1), ("fx2", fx2, baseline.fx2),
        ] + Set(paletteByBackdrop.keys).union(baseline.paletteByBackdrop.keys).sorted().map {
            ("palette@\($0)", paletteByBackdrop[$0] ?? [], baseline.paletteByBackdrop[$0] ?? [])
        }
        return pairs.compactMap { name, now, before in
            let (added, removed) = (Set(now).subtracting(before).sorted(), Set(before).subtracting(now).sorted())
            return added.isEmpty && removed.isEmpty ? nil : "\(name) ＋\(added) －\(removed)"
        }
    }
}

/// 既有樂團的候選基線（`Tests/Fixtures/LyricsFX/band-candidates-baseline.json`）：只有樂團名與元件代號
struct BandCandidatesBaseline: Codable {
    struct Band: Codable, Equatable {
        let name: String
        /// 每槽所有 fit > 0 的元件
        let eligible: [String: [String]]
        /// `nil`＝mono
        let playable: PlayableSpace?
    }

    let schema: Int
    let sourceRevision: String
    let generatedBy: String
    let bands: [Band]

    static let fileName = "LyricsFX/band-candidates-baseline.json"

    static func load() throws -> BandCandidatesBaseline {
        try JSONDecoder().decode(BandCandidatesBaseline.self, from: Data(contentsOf: GoldenFixtures.fixturesRoot().appendingPathComponent(fileName)))
    }

    static func current(of band: SongProfileResolver.BandEntry) -> Band {
        let eligible = Dictionary(uniqueKeysWithValues: FXSlot.allCases.map { slot in
            (slot.rawValue, LyricsFXCatalog.components(in: slot).filter { Composer.fit($0, band.profile) > 0 }.map(\.id).sorted())
        })
        return Band(name: band.name, eligible: eligible, playable: PlayableSpace.of(band.profile))
    }
}
