import Testing

@testable import AzathothsWhisper

// B2 計劃 §3.5、T1：樂團覆寫表的擴充規則——正式名與別名的鍵唯一、別名解析到同一份目標值、
// 每團六槽（字型、背景、進場、退場、第一效果、配色）的候選數

/// 必選的五槽加效果槽，各有幾個 fit > 0 的元件（效果槽的 none 也算一個）
private func candidateCounts(_ profile: SongProfile, catalog: [FXComponent] = LyricsFXCatalog.all) -> [FXSlot: Int] {
    Dictionary(uniqueKeysWithValues: FXSlot.allCases.map { slot in
        (slot, catalog.filter { $0.slot == slot && Composer.fit($0, profile) > 0 }.count)
    })
}

/// 候選不到 2 個的槽：同一首歌下次播放在這一槽換不了（I-27）
private func thinSlots(_ profile: SongProfile, catalog: [FXComponent] = LyricsFXCatalog.all) -> [FXSlot] {
    let counts = candidateCounts(profile, catalog: catalog)
    return FXSlot.allCases.filter { counts[$0, default: 0] < 2 }
}

private func entry(_ name: String, aliases: [String] = [], tags: Set<FXTag> = [.black]) -> SongProfileResolver.BandEntry {
    SongProfileResolver.BandEntry(name: name, aliases: aliases, profile: SongProfile(axes: [.raw: 0.5], tags: tags))
}

@Suite("Artist override table")
struct ArtistOverrideTableTests {
    @Test func everyNameAndAliasNormalizesToAUniqueKey() {
        #expect(SongProfileResolver.duplicateKeys(in: SongProfileResolver.bandTable).isEmpty)
    }

    @Test func duplicateKeysAreReportedAcrossNamesAndAliases() {
        let table = [entry("The Quiet Harbour"), entry("Lantern Field", aliases: ["quiet harbour"]), entry("Lantern-Field")]

        let duplicates = SongProfileResolver.duplicateKeys(in: table)

        #expect(Set(duplicates) == ["quietharbour", "lanternfield"])
    }

    @Test func anAliasResolvesToTheSameProfileAsItsBand() {
        let table = [entry("Lantern Field", aliases: ["Lantern Field & The Quiet Harbour"], tags: [.symphonic])]

        let overrides = SongProfileResolver.overrides(from: table)

        #expect(overrides[SongProfileResolver.normalizedArtist("lantern field & the quiet harbour")] == table[0].profile)
        #expect(overrides[SongProfileResolver.normalizedArtist("LANTERN FIELD")] == table[0].profile)
        #expect(overrides[SongProfileResolver.normalizedArtist("Quiet Harbour")] == nil, "沒列為別名的合作名不猜")
    }

    @Test func slotsWithFewerThanTwoCandidatesAreThin() {
        let font = { (id: String, tags: Set<FXTag>) in
            FXComponent(id: id, slot: .font, vector: [:], tags: tags, req: [:], forbid: [:], payload: .fx(.none))
        }
        let profile = SongProfile(axes: [.raw: 0.5], tags: [.black])

        let thin = thinSlots(profile, catalog: [font("a", [.black]), font("b", [.symphonic])])

        #expect(thin.contains(.font), "只有一個合格字型")
        #expect(!thinSlots(profile, catalog: [font("a", [.black]), font("b", [])]).contains(.font))
    }

    /// B1 的 28 團照原型抄、目錄只有黑金屬＋交響子集，多數團本來就湊不滿（全六槽不足的團在 app 裡是 mono）。
    /// 不為了這條規則回頭改它們；這裡釘住 2026-10-07 的現況，只准變少、不准變多。B2 之後加的團見下一條
    @Test func theB1BandsNeverGainThinSlots() {
        let all = "font,backdrop,enter,exit,fx,palette"
        let pinned: [String: String] = [
            "Arch Enemy": "enter,exit", "Cannibal Corpse": "enter,exit", "Hatebreed": "font,enter,exit,palette", "Nightwish": "exit",
            "Iron Maiden": "exit,palette", "Slayer": "enter,exit", "Rammstein": all, "Korn": "font,backdrop,enter,exit,palette", "Epica": "exit",
            "The Chemical Brothers": all, "Fatboy Slim": all, "Daft Punk": all, "Aphex Twin": all, "The Offspring": all, "Blink-182": all,
            "Green Day": all, "Sum 41": all, "Ramones": all, "Sex Pistols": all,
        ]

        for band in SongProfileResolver.batchOne {
            let allowed = Set((pinned[band.name] ?? "").split(separator: ",").map(String.init))
            let thin = Set(thinSlots(band.profile).map(\.rawValue))
            #expect(thin.isSubset(of: allowed), "\(band.name) 多了候選不足的槽：\(thin.subtracting(allowed).sorted())")
        }
    }

    @Test func bandsAddedFromB2OnHaveAtLeastTwoCandidatesInEverySlot() {
        for band in SongProfileResolver.batchTwo + SongProfileResolver.batchThree {
            #expect(thinSlots(band.profile).isEmpty, "\(band.name) 有候選不足的槽")
        }
    }
}
