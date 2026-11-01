import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 5（docs/plans/2026-11-01-lyrics-fx-signed-bands-components.md）V1–V3：工業／電子 5 個署名團補元件

enum B2BatchFive {
    static let bands = ["Rammstein", "The Chemical Brothers", "Fatboy Slim", "Daft Punk", "Aphex Twin"]
    /// 隔離集合 X：只出現在這 5 團目標值的標籤（計劃 F3）
    static let isolation: Set<FXTag> = [.industrial, .bigbeat, .electro, .techno, .house, .frenchhouse, .idm, .ambient]
    /// 本批新做的元件（`need.js --batch 5`，P17 後）
    static let newComponents: Set<String> = [
        "backdrop:steel", "backdrop:neon", "enter:march", "enter:forge", "exit:burnout", "exit:shutdown",
        "font:OswaldInd", "font:FrakturInd", "fx:stomp", "fx:heat", "palette:steelFire", "palette:blackRed", "palette:neonPink",
    ]

    static func entries() -> [SongProfileResolver.BandEntry] {
        bands.compactMap { name in SongProfileResolver.bandTable.first { $0.name == name } }
    }

    static func key(_ component: FXComponent) -> String { "\(component.slot.rawValue):\(component.id)" }
}

@Suite("B2 batch 5 signed fixture")
struct B2BatchFiveSignedFixtureTests {
    /// 既有署名團補件＝linked＋new（同批 2 對 B1 龐克團的模型，計劃 V2）
    @Test func theFixtureSignsExactlyTheFiveBandsAsNewLinkedVersions() throws {
        let file = try SignedBatchFile.load(batch: 5)
        let linked = file.linked ?? []
        #expect(file.bands.isEmpty)
        #expect(Set(linked.map(\.name)) == Set(B2BatchFive.bands))
        #expect(linked.allSatisfy { $0.decision == .new })
        #expect(Set(linked.map(\.name)).isSubset(of: SongProfileResolver.batchOne.map(\.name)))
    }

    @Test func theAppOffersTheSignedEligibleAndPlayableSpace() throws {
        for signed in try SignedBatchFile.load(batch: 5).linked ?? [] {
            guard let band = SongProfileResolver.bandTable.first(where: { $0.name == signed.name }) else {
                Issue.record("\(signed.name) 不在樂團表"); continue
            }
            let now = BandCandidatesBaseline.current(of: band)
            #expect(now.eligible == signed.eligible, "\(signed.name) 合格集合與簽字不同")
            #expect(signed.playable != nil && now.playable == signed.playable, "\(signed.name) 可抽空間與簽字不同")
        }
    }
}

@Suite("B2 batch 5 isolation")
struct B2BatchFiveIsolationTests {
    /// 其他團與所有曲風列、通用列都不帶 X，所以新元件與同掛只動得到這 5 團（計劃 F3、V3）
    @Test func noOtherProfileCarriesAnIsolationTag() {
        for band in SongProfileResolver.bandTable where !B2BatchFive.bands.contains(band.name) {
            #expect(band.profile.tags.isDisjoint(with: B2BatchFive.isolation), "\(band.name)")
        }
        for row in SongProfileResolver.keywordRows + SongProfileResolver.genericRows {
            #expect(row.tags.isDisjoint(with: B2BatchFive.isolation), "列 \(row.id)")
        }
    }

    @Test func everyNewComponentCarriesOnlyIsolationTags() {
        let found = LyricsFXCatalog.all.filter { B2BatchFive.newComponents.contains(B2BatchFive.key($0)) }
        #expect(Set(found.map(B2BatchFive.key)) == B2BatchFive.newComponents, "目錄缺本批元件")
        for component in found {
            #expect(!component.tags.isEmpty && component.tags.isSubset(of: B2BatchFive.isolation), "\(B2BatchFive.key(component))")
        }
    }

    /// 歸屬白名單（R2-6、P10、P15）：Rammstein 只抽得到本批新元件與無標籤的通用元件，不借 Nu 系或黑金屬的東西
    @Test func rammsteinOnlyDrawsItsOwnComponents() throws {
        let rammstein = try #require(SongProfileResolver.bandTable.first { $0.name == "Rammstein" })
        for component in LyricsFXCatalog.all where Composer.fit(component, rammstein.profile) > 0 {
            #expect(component.tags.isEmpty || B2BatchFive.newComponents.contains(B2BatchFive.key(component)), "\(B2BatchFive.key(component))")
            #expect(component.tags.isDisjoint(with: FXTag.nuFamily) && !["Catacombs", "negative"].contains(component.id))
        }
    }
}

@Suite("B2 batch 5 playable")
struct B2BatchFivePlayableTests {
    /// V1：可播放；必選槽各 ≥ 2；每個可抽背景都有 ≥ 2 個可讀配色
    @Test func everyBandHasARealPlayableSpace() {
        #expect(B2BatchFive.entries().count == B2BatchFive.bands.count)
        for band in B2BatchFive.entries() {
            guard let space = PlayableSpace.of(band.profile) else { Issue.record("\(band.name) 仍是 mono"); continue }
            for slot in [space.font, space.backdrop, space.enter, space.exit] { #expect(slot.count >= 2, "\(band.name)") }
            for backdrop in space.backdrop { #expect((space.paletteByBackdrop[backdrop] ?? []).count >= 2, "\(band.name) \(backdrop)") }
        }
    }

    /// 端到端：解析出署名結果、組出非 mono（R1-12）
    @Test func resolvingAndComposingGivesAComposedStyle() {
        for band in B2BatchFive.entries() {
            let resolution = SongProfileResolver.resolve(artist: band.name, genre: "Electronic", lyrics: .text(isJapanese: false))
            #expect(resolution == .signedBand(band.profile), "\(band.name)")
            guard case .composed = Composer.compose(profile: band.profile, seed: 7) else { Issue.record("\(band.name) 組出 mono"); continue }
        }
    }
}
