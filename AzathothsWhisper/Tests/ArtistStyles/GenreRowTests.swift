import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥b 計劃 §4.7（R3-1〜R3-6）：曲風列擴充。軸值＝代表團平均、標籤＝代表團聯集扣私有家族；既有兩列為不變基線
@Suite("Genre rows")
struct GenreRowTests {
    static let expected: [String: (representatives: [String], tags: Set<FXTag>)] = [
        "melodeath": (["Arch Enemy"], [.death, .melodeath, .thrash]),
        "death": (["Cannibal Corpse", "Fleshgod Apocalypse"], [.death, .grind, .symphonic, .thrash]),
        "gothic": (["Type O Negative", "Cradle of Filth"], [.black, .doom, .gothic, .symphonic]),
        "doom": (["Type O Negative", "Burzum"], [.black, .doom, .gothic]),
        "thrash": (["Slayer", "Arch Enemy"], [.death, .melodeath, .thrash]),
        "hardrock": (["AC/DC", "Guns N' Roses"], [.glam, .hardrock]),
        "classicrock": (["The Beatles", "Pink Floyd", "Queen"], [.arena, .britpop, .classicrock, .glam, .psych]),
        "altindie": (["Blur", "Weezer", "Oasis"], [.britpop, .indie, .powerpop]),
        "arena": (["Coldplay", "The Killers"], [.arena]),
        "poppunk": (["Blink-182", "Green Day", "Sum 41", "Fall Out Boy", "Good Charlotte"], [.arena, .poppunk, .poprock, .punk, .rock, .skatepunk]),
        "punk": (["Ramones", "Sex Pistols", "The Offspring", "NOFX"], [.punk, .punk77, .rock, .skatepunk]),
        "ska": (["The Interrupters"], [.punk, .ska]),
        "metalcore": (["Hatebreed"], [.hardcore, .nu]),
        "nu": (["Korn"], [.nu]),
        "metal": (["Iron Maiden", "Slayer"], [.death, .heavy, .power, .thrash]),
    ]

    /// 使用者 2026-10-24 真機逐列看過、整列拿掉的列（不調軸值；計劃附錄 E）
    static let removedRows: [String: String] = [
        "heavypower": "Iron Maiden＋Nightwish 抽到哥德／交響元件，不像重金屬；這類歌改走 metal*",
        "rock": "generic rock 套在 folk rock 上不像；只命中它的歌回到 Apple 曲風",
    ]

    @Test func theRemovedRowsStayRemoved() {
        for id in Self.removedRows.keys { #expect(!SongProfileResolver.keywordRows.contains { $0.id == id }, "\(id)") }
        #expect(SongProfileResolver.compose(genres: ["power metal"]) == SongProfileResolver.compose(genres: ["metal"]), "power metal 改走 metal*")
        #expect(SongProfileResolver.compose(genres: ["folk rock"]) == nil)
    }

    /// 曲庫出現過的列組合（2026-10-24 探查：驗證者的 MB 前 3 曲風，以同一套關鍵字規則換算；只存列 id）＋R3-3 的固定代表組合；
    /// ⑧ 2026-10-28 曲庫重掃補上漏掉的三組（hardrock＋thrash、metalcore＋nu、metalcore＋poppunk＋punk）。
    /// 與 ⑦ 的通用組合一起構成 `ReadabilityPolicy.combinations`（`ReadabilityPolicyTests` 斷言一致），G1–G3 也走同一份
    static let libraryCombinations: [[String]] = [
        ["hardrock", "thrash"], ["metalcore", "nu"], ["metalcore", "poppunk", "punk"],
        ["altindie", "arena"], ["altindie", "classicrock"], ["altindie", "gothic"], ["altindie", "nu"], ["altindie", "punk"], ["altindie", "symphonic"], ["arena", "classicrock"], ["black", "death"], ["black", "death", "melodeath"], ["black", "death", "symphonic"], ["black", "death", "thrash"], ["black", "doom"], ["black", "gothic"], ["black", "gothic", "symphonic"], ["black", "symphonic"], ["black", "thrash"], ["classicrock", "death"], ["classicrock", "doom"], ["classicrock", "hardrock"], ["classicrock", "punk"], ["death", "doom"], ["death", "doom", "melodeath"], ["death", "melodeath"], ["death", "melodeath", "metalcore"], ["death", "melodeath", "symphonic"], ["death", "metalcore"], ["doom", "gothic"], ["doom", "metalcore"], ["gothic", "hardrock", "nu"], ["gothic", "nu"], ["gothic", "punk"], ["gothic", "symphonic"], ["hardrock", "nu"], ["metalcore", "thrash"], ["symphonic", "death"], ["metal"],
    ]

    private func row(_ id: String) throws -> SongProfileResolver.KeywordRow {
        try #require(SongProfileResolver.keywordRows.first { $0.id == id }, "缺列 \(id)")
    }

    private func mean(_ names: [String]) -> [FXAxis: Double] {
        let profiles = names.compactMap { name in SongProfileResolver.bandTable.first { $0.name == name }?.profile }
        var axes: [FXAxis: Double] = [:]
        for axis in FXAxis.allCases {
            let values = profiles.compactMap { $0.axes[axis] }
            if !values.isEmpty { axes[axis] = values.reduce(0, +) / Double(values.count) }
        }
        return axes
    }

    /// R3-5：代表團都在樂團表、各算一次；軸值與標籤逐列釘住
    @Test(arguments: expected.keys.sorted())
    func eachNewRowIsTheMeanOfItsRepresentatives(id: String) throws {
        let row = try row(id)
        let spec = try #require(Self.expected[id])
        #expect(row.representatives == spec.representatives)
        #expect(Set(row.representatives).count == row.representatives.count)
        for name in row.representatives { #expect(SongProfileResolver.bandTable.filter { $0.name == name }.count == 1, "\(name)") }
        #expect(row.tags == spec.tags)
        #expect(row.axes == mean(spec.representatives))
        #expect(row.tags.isDisjoint(with: SongProfileResolver.genreRowPrivateTags))
    }

    /// R3-1：`.nu` 不在私有清單；批 3 子標籤、emo、J-Pop 在
    @Test func thePrivateTagsKeepNuButDropBatchThreeEmoAndJPop() {
        let blocked = SongProfileResolver.genreRowPrivateTags
        #expect(!blocked.contains(.nu))
        #expect(FXTag.emoFamily.isSubset(of: blocked) && FXTag.jpopFamily.isSubset(of: blocked))
        #expect(FXTag.nuFamily.subtracting([.nu]).isSubset(of: blocked))
    }

    /// R3-6：既有兩列逐位元不變
    @Test func theTwoOriginalRowsAreUnchanged() throws {
        let black = try row("black")
        #expect(black.keywords == ["black", "pagan", "depressive", "heathen"] && black.tags == [.black])
        #expect(black.axes == mean(["Mayhem", "Immortal", "Darkthrone"]))
        let symphonic = try row("symphonic")
        #expect(symphonic.keywords == ["symphon", "neoclassic", "classical", "religious", "soundtrack", "score"] && symphonic.tags == [.symphonic])
        #expect(symphonic.axes == mean(["Nightwish", "Epica"]))
        #expect(SongProfileResolver.compose(genres: ["Black Metal"]) == SongProfile(axes: black.axes, tags: [.black]))
    }

    @Test func everyRowIsPlayableOnItsOwn() throws {
        for row in SongProfileResolver.keywordRows {
            let profile = try #require(SongProfileResolver.compose(rows: [row]))
            #expect(Composer.isComposable(profile), "\(row.id)")
            #expect(PlayableSpace.of(profile) != nil, "\(row.id)")
        }
    }

    /// R3-3：曲庫出現過的組合都要組得出來（對比與 G2／G3 經 `ReadabilityPolicy.combinations` 納入 `ReadabilityAudit.profiles`，⑧）
    @Test(arguments: libraryCombinations)
    func libraryCombinationsArePlayable(ids: [String]) throws {
        let rows = try ids.map(row)
        let profile = try #require(SongProfileResolver.compose(rows: rows))
        #expect(Composer.isComposable(profile))
        #expect(PlayableSpace.of(profile) != nil)
    }

    /// 同一個語義只有一處定義：`isComposable` 與 `PlayableSpace` 對所有樂團與列給出同樣結論
    @Test func isComposableAgreesWithThePlayableSpace() {
        let profiles = SongProfileResolver.bandTable.map(\.profile) + SongProfileResolver.keywordRows.compactMap { SongProfileResolver.compose(rows: [$0]) }
        for profile in profiles { #expect(Composer.isComposable(profile) == (PlayableSpace.of(profile) != nil)) }
        #expect(!Composer.isComposable(SongProfile(axes: [:], tags: [.frenchhouse])))
    }

    // MARK: 合成（R3-2）

    @Test func orderAndDuplicatesDoNotMatter() {
        let one = SongProfileResolver.compose(genres: ["death metal", "black metal"])
        #expect(one == SongProfileResolver.compose(genres: ["black metal", "death metal", "Death Metal"]))
        #expect(one != nil)
    }

    @Test func aGenericRowOnlyCountsWithoutASpecificHit() throws {
        #expect(SongProfileResolver.compose(genres: ["rock", "black metal"]) == SongProfileResolver.compose(genres: ["black metal"]))
        let metal = try row("metal")
        #expect(SongProfileResolver.compose(genres: ["metal"]) == SongProfileResolver.compose(rows: [metal]))
    }

    @Test func oneGenreCanHitSeveralRows() throws {
        let both = try SongProfileResolver.compose(rows: [row("melodeath"), row("death")])
        #expect(SongProfileResolver.compose(genres: ["melodic death metal"]) == both)
    }

    @Test func noHitIsNil() {
        #expect(SongProfileResolver.compose(genres: ["experimental", "ambient"]) == nil)
        #expect(SongProfileResolver.compose(genres: []) == nil)
    }

    @Test func theAppleSingleGenreEntryPointIsTheSameRule() {
        #expect(SongProfileResolver.compose(genre: "Death Metal / Black Metal", rows: SongProfileResolver.keywordRows)
            == SongProfileResolver.compose(genres: ["Death Metal / Black Metal"]))
    }
}
