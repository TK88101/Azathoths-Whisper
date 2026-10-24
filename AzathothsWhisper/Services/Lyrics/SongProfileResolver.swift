import Foundation

/// 十軸特徵（母計劃 §2.10）。值域 0…1；向量是**部分的**：沒宣告的軸＝未知，不是 0
enum FXAxis: String, CaseIterable, Sendable {
    case raw, theatrical, cold, aggression, speed, elegance, decay, bright, bounce, warm
}

/// 曲風標籤（母計劃 §2.10 列表）。與 `StyleFamily` 無關；組合器不讀 family
enum FXTag: String, CaseIterable, Sendable {
    case black, symphonic, gothic, doom, death, melodeath, grind, thrash, heavy, power, hardcore, nu, industrial
    case techno, idm, electro, house, frenchhouse, bigbeat, ambient
    case punk, punk77 = "77punk", poppunk, skatepunk, rock, indie, pop
    /// B2 批 1（rock 系）：既有的 `rock` 是原型替龐克團做的，硬搖滾／英倫等另立標籤（B2 計劃 §7.3）
    case hardrock, classicrock, glam, psych, britpop, arena
    /// B2 批 2（龐克系）：旋律硬核、ska、power pop、抒情流行搖滾
    case melodichc, ska, powerpop, poprock
    /// B2 批 3（Nu-metal）：本批新團的私有子標籤，新團不帶 `nu`／`hardcore`（計劃 §2.4 N1）
    case altmetal, rapmetal, cybermetal, horrormetal, gothmetal, latinmetal
    /// B2 批 4（emo 群）：**本批私有**標籤（計劃 §2.2 E1）。`posthardcore`、`emopop` 看起來像一般曲風名，但不是公共曲風標籤——
    /// 日後的團要重用，得重走連帶預檢、簽字與基線流程
    case emo, posthardcore, indieemo, emopop
    /// ⑥a J-Pop：三變體各一個私有標籤；J-Pop 元件只帶其中一個（計劃 §4.2、§4.3）
    case jpopKira, jpopCity, jpopBallad

    /// Nu 系標籤：任何一個都不得與 `industrial` 掛在同一個元件上（P10；B2 批 3 計劃 §2.4 N1）。新立的 Nu 系子標籤要加進來
    static let nuFamily: Set<FXTag> = [.nu, .altmetal, .rapmetal, .cybermetal, .horrormetal, .gothmetal, .latinmetal]

    /// B2 批 4（emo 群）的私有標籤：本批新團只帶這些、新元件也只帶這些，既有團一個都不帶（B2 批 4 計劃 §2.2 E1）。
    static let emoFamily: Set<FXTag> = [.emo, .posthardcore, .indieemo, .emopop]

    static let jpopFamily: Set<FXTag> = [.jpopKira, .jpopCity, .jpopBallad]
}

/// 歌曲目標值
struct SongProfile: Equatable, Sendable {
    let axes: [FXAxis: Double]
    let tags: Set<FXTag>
}

/// 歌詞這一層的證據（⑥a J-Pop 計劃 §4.1）：`unknown`＝還沒讀到（含讀取失敗）；空白歌詞判不成日文歌，同 `.text(isJapanese: false)`
enum LyricsEvidence: Equatable, Sendable {
    case unknown
    case text(isJapanese: Bool)

    /// 日文＝`LyricsScript.isJapaneseSong`（含假名的行 ≥ 3 成）
    static func of(_ lyrics: String?) -> LyricsEvidence {
        lyrics.map { .text(isJapanese: LyricsScript.isJapaneseSong($0)) } ?? .unknown
    }
}

/// 定論的來源；VM 只在來源改變時重組已定格的配方（⑥a 計劃 §4.4）
enum ProfileSource: Equatable, Sendable {
    /// `verifiedArtistGenre`＝MB 驗證過的歌手曲風命中曲風列（⑥b 計劃 §4.3）；`genreRow`＝Apple 曲風命中
    case signedBand, jpopPolicy, verifiedArtistGenre, genreRow, noMatch

    /// 由歌詞內容決定的來源：寫入或改詞可能讓它出現或消失
    var dependsOnLyrics: Bool { self == .jpopPolicy }
}

/// `pending`＝還在等 genre 或歌詞（會等，沒有來源）；其餘是定論，各自帶來源
enum ProfileResolution: Equatable, Sendable {
    case pending
    case signedBand(SongProfile)
    /// 日文歌一律 J-Pop（使用者 2026-10-22）；變體由 VM 選（`JPopPolicy`）
    case jpop
    /// MB 驗證過的歌手曲風命中曲風列（⑥b）
    case artistGenreRow(SongProfile)
    case genreRow(SongProfile)
    /// 讀到了 genre 但無已知關鍵字：素面
    case noMatch

    var source: ProfileSource? {
        switch self {
        case .pending: nil
        case .signedBand: .signedBand
        case .jpop: .jpopPolicy
        case .artistGenreRow: .verifiedArtistGenre
        case .genreRow: .genreRow
        case .noMatch: .noMatch
        }
    }

    var profile: SongProfile? {
        switch self {
        case .signedBand(let profile), .artistGenreRow(let profile), .genreRow(let profile): profile
        case .pending, .jpop, .noMatch: nil
        }
    }
}

/// 歌曲目標值的來源（B1 計劃 §3.5；⑥a 計劃 §4.1；⑥b 計劃 §4.3）：樂團覆寫表 → 歌詞未知＝pending → 日文詞＝J-Pop →
/// MB 驗證過的歌手曲風 → genre 關鍵字合成。每一層合成後組不出六槽就當沒命中、落下一層
enum SongProfileResolver {
    struct KeywordRow: Sendable {
        let id: String
        let keywords: [String]
        /// 軸值的來源：樂團表裡的代表團（⑥b 計劃 §4.7「列的軸值＝署名代表團平均」）
        let representatives: [String]
        let tags: Set<FXTag>
        let axes: [FXAxis: Double]
        /// generic（metal、rock…）只在沒有任何非 generic 命中時才貢獻
        let isGeneric: Bool
    }

    /// 樂團覆寫表：使用者在探針 P2、P9–P11 給的判據，原樣抄自原型 `composer.js:123-152` 的 TARGETS（等 D 段 Jev 取代）。
    /// 鍵＝`normalizedArtist`
    static let overrides: [String: SongProfile] = overrides(from: bandTable)

    /// 覆寫表的一列：正式名＋曲庫裡實際出現的其他寫法（合作名等；不做模糊比對，沒列到的照舊走曲風）
    struct BandEntry: Sendable {
        let name: String
        var aliases: [String] = []
        let profile: SongProfile

        var keys: [String] { ([name] + aliases).map(SongProfileResolver.normalizedArtist) }
    }

    static let bandTable: [BandEntry] = batchOne + batchTwo + batchThree + batchFour + batchFive

    /// B1：抄自原型的 28 團
    static let batchOne: [BandEntry] = bandTargets.map { BandEntry(name: $0.0, profile: $0.1) }

    /// B2 批 1：使用者 2026-10-07 看原型探針後簽字（P13）；值與 `Tests/Fixtures/LyricsFX/b2-batch1-signed.json` 一致（`B2SignedFixtureTests` 把關）。
    /// Coldplay 的別名是曲庫裡實際出現的合作曲寫法
    static let batchTwo: [BandEntry] = [
        BandEntry(name: "AC/DC", profile: SongProfile(axes: [.raw: 0.6, .theatrical: 0.3, .cold: 0.1, .aggression: 0.65, .speed: 0.6, .elegance: 0.05, .decay: 0.2, .bright: 0.5, .bounce: 0.55, .warm: 0.6], tags: [.hardrock])),
        BandEntry(name: "Guns N' Roses", profile: SongProfile(axes: [.raw: 0.65, .theatrical: 0.55, .cold: 0.15, .aggression: 0.65, .speed: 0.65, .elegance: 0.25, .decay: 0.45, .bright: 0.4, .bounce: 0.35, .warm: 0.5], tags: [.hardrock, .glam])),
        BandEntry(name: "Queen", profile: SongProfile(axes: [.raw: 0.1, .theatrical: 0.95, .cold: 0.15, .aggression: 0.3, .speed: 0.5, .elegance: 0.8, .decay: 0.05, .bright: 0.8, .bounce: 0.5, .warm: 0.6], tags: [.glam, .classicrock, .arena])),
        BandEntry(name: "The Beatles", profile: SongProfile(axes: [.raw: 0.25, .theatrical: 0.35, .cold: 0.1, .aggression: 0.1, .speed: 0.45, .elegance: 0.5, .decay: 0.15, .bright: 0.8, .bounce: 0.6, .warm: 0.8], tags: [.classicrock, .britpop])),
        BandEntry(name: "Pink Floyd", profile: SongProfile(axes: [.raw: 0.15, .theatrical: 0.75, .cold: 0.6, .aggression: 0.15, .speed: 0.1, .elegance: 0.75, .decay: 0.3, .bright: 0.25, .bounce: 0, .warm: 0.25], tags: [.psych, .classicrock])),
        BandEntry(name: "Oasis", profile: SongProfile(axes: [.raw: 0.55, .theatrical: 0.3, .cold: 0.2, .aggression: 0.4, .speed: 0.45, .elegance: 0.2, .decay: 0.3, .bright: 0.5, .bounce: 0.3, .warm: 0.55], tags: [.britpop])),
        BandEntry(name: "Blur", profile: SongProfile(axes: [.raw: 0.35, .theatrical: 0.35, .cold: 0.25, .aggression: 0.25, .speed: 0.55, .elegance: 0.35, .decay: 0.2, .bright: 0.7, .bounce: 0.65, .warm: 0.5], tags: [.britpop, .indie])),
        BandEntry(name: "The Killers", profile: SongProfile(axes: [.raw: 0.15, .theatrical: 0.7, .cold: 0.3, .aggression: 0.3, .speed: 0.6, .elegance: 0.5, .decay: 0.1, .bright: 0.75, .bounce: 0.5, .warm: 0.5], tags: [.arena])),
        BandEntry(name: "Coldplay", aliases: ["Coldplay X BTS", "Coldplay X Selena Gomez", "Coldplay X We Are KING X Jacob Collier"], profile: SongProfile(axes: [.raw: 0.05, .theatrical: 0.55, .cold: 0.3, .aggression: 0.05, .speed: 0.3, .elegance: 0.75, .decay: 0.05, .bright: 0.8, .bounce: 0.25, .warm: 0.65], tags: [.arena])),
    ]

    /// B2 批 2（表內第三段；`batchOne`＝B1、`batchTwo`＝B2 批 1）：使用者 2026-10-09 看原型探針後簽字（P14）；
    /// 值與 `Tests/Fixtures/LyricsFX/b2-batch2-signed.json` 一致（`B2BatchTwoSignedFixtureTests` 把關）。曲庫裡這七團沒有別的寫法
    static let batchThree: [BandEntry] = [
        BandEntry(name: "Fall Out Boy", profile: SongProfile(axes: [.raw: 0.2, .theatrical: 0.7, .cold: 0.2, .aggression: 0.4, .speed: 0.75, .elegance: 0.35, .decay: 0.1, .bright: 0.8, .bounce: 0.7, .warm: 0.5], tags: [.poppunk, .poprock, .arena])),
        BandEntry(name: "Rise Against", profile: SongProfile(axes: [.raw: 0.5, .theatrical: 0.3, .cold: 0.3, .aggression: 0.75, .speed: 0.9, .elegance: 0.15, .decay: 0.3, .bright: 0.4, .bounce: 0.2, .warm: 0.3], tags: [.melodichc, .punk, .skatepunk])),
        BandEntry(name: "NOFX", profile: SongProfile(axes: [.raw: 0.6, .theatrical: 0.2, .cold: 0.1, .aggression: 0.5, .speed: 0.95, .elegance: 0.05, .decay: 0.3, .bright: 0.6, .bounce: 0.55, .warm: 0.5], tags: [.skatepunk, .punk])),
        BandEntry(name: "The Interrupters", profile: SongProfile(axes: [.raw: 0.4, .theatrical: 0.3, .cold: 0.1, .aggression: 0.4, .speed: 0.8, .elegance: 0.1, .decay: 0.2, .bright: 0.7, .bounce: 0.9, .warm: 0.6], tags: [.ska, .punk])),
        BandEntry(name: "Mayday Parade", profile: SongProfile(axes: [.raw: 0.15, .theatrical: 0.55, .cold: 0.2, .aggression: 0.25, .speed: 0.55, .elegance: 0.5, .decay: 0.1, .bright: 0.6, .bounce: 0.35, .warm: 0.65], tags: [.poprock, .poppunk])),
        BandEntry(name: "Good Charlotte", profile: SongProfile(axes: [.raw: 0.3, .theatrical: 0.4, .cold: 0.15, .aggression: 0.45, .speed: 0.75, .elegance: 0.15, .decay: 0.2, .bright: 0.65, .bounce: 0.6, .warm: 0.5], tags: [.poppunk, .skatepunk])),
        BandEntry(name: "Weezer", profile: SongProfile(axes: [.raw: 0.35, .theatrical: 0.2, .cold: 0.25, .aggression: 0.3, .speed: 0.55, .elegance: 0.3, .decay: 0.1, .bright: 0.7, .bounce: 0.5, .warm: 0.5], tags: [.powerpop, .indie])),
    ]

    /// B2 批 3（表內第四段，Nu-metal）：使用者 2026-10-11 看原型探針後簽字（P15）；值與 `Tests/Fixtures/LyricsFX/b2-batch3-signed.json` 一致
    /// （`B2BatchThreeSignedFixtureTests` 把關）。新團不帶 `nu`／`hardcore`（計劃 §2.4 N1）；Linkin Park 的別名是曲庫裡實際出現的合作曲寫法
    static let batchFour: [BandEntry] = [
        BandEntry(name: "Linkin Park", aliases: ["JAY-Z & LINKIN PARK", "LINKIN PARK & Steve Aoki"], profile: SongProfile(axes: [.raw: 0.35, .theatrical: 0.55, .cold: 0.6, .aggression: 0.7, .speed: 0.6, .elegance: 0.35, .decay: 0.3, .bright: 0.3, .bounce: 0.35, .warm: 0.2], tags: [.rapmetal, .cybermetal])),
        BandEntry(name: "Slipknot", profile: SongProfile(axes: [.raw: 0.85, .theatrical: 0.7, .cold: 0.3, .aggression: 0.95, .speed: 0.85, .elegance: 0.05, .decay: 0.8, .bright: 0.05, .bounce: 0.3, .warm: 0.05], tags: [.horrormetal, .altmetal])),
        BandEntry(name: "Stone Sour", profile: SongProfile(axes: [.raw: 0.6, .theatrical: 0.45, .cold: 0.3, .aggression: 0.75, .speed: 0.6, .elegance: 0.2, .decay: 0.5, .bright: 0.25, .bounce: 0.25, .warm: 0.3], tags: [.altmetal, .horrormetal])),
        BandEntry(name: "Flyleaf", profile: SongProfile(axes: [.raw: 0.35, .theatrical: 0.6, .cold: 0.35, .aggression: 0.6, .speed: 0.55, .elegance: 0.5, .decay: 0.3, .bright: 0.3, .bounce: 0.15, .warm: 0.35], tags: [.gothmetal, .altmetal])),
        BandEntry(name: "Limp Bizkit", profile: SongProfile(axes: [.raw: 0.6, .theatrical: 0.4, .cold: 0.15, .aggression: 0.7, .speed: 0.6, .elegance: 0.05, .decay: 0.3, .bright: 0.55, .bounce: 0.85, .warm: 0.45], tags: [.rapmetal])),
        BandEntry(name: "P.O.D.", profile: SongProfile(axes: [.raw: 0.5, .theatrical: 0.45, .cold: 0.15, .aggression: 0.65, .speed: 0.6, .elegance: 0.15, .decay: 0.2, .bright: 0.6, .bounce: 0.7, .warm: 0.65], tags: [.rapmetal])),
        BandEntry(name: "Adema", profile: SongProfile(axes: [.raw: 0.5, .theatrical: 0.45, .cold: 0.35, .aggression: 0.7, .speed: 0.55, .elegance: 0.2, .decay: 0.45, .bright: 0.25, .bounce: 0.35, .warm: 0.2], tags: [.altmetal])),
        BandEntry(name: "Evanescence", profile: SongProfile(axes: [.raw: 0.15, .theatrical: 0.9, .cold: 0.45, .aggression: 0.5, .speed: 0.4, .elegance: 0.8, .decay: 0.4, .bright: 0.15, .bounce: 0.05, .warm: 0.3], tags: [.gothmetal])),
        BandEntry(name: "Ill Niño", profile: SongProfile(axes: [.raw: 0.6, .theatrical: 0.5, .cold: 0.1, .aggression: 0.8, .speed: 0.7, .elegance: 0.2, .decay: 0.35, .bright: 0.35, .bounce: 0.5, .warm: 0.7], tags: [.latinmetal])),
        BandEntry(name: "Static-X", profile: SongProfile(axes: [.raw: 0.5, .theatrical: 0.45, .cold: 0.75, .aggression: 0.8, .speed: 0.85, .elegance: 0.05, .decay: 0.3, .bright: 0.35, .bounce: 0.5, .warm: 0.05], tags: [.cybermetal, .altmetal])),
    ]

    /// B2 批 4（表內第五段，emo 群）：使用者 2026-10-13 看原型探針後簽字（P16）；值與 `Tests/Fixtures/LyricsFX/b2-batch4-signed.json` 一致
    /// （`B2BatchFourSignedFixtureTests` 把關）。只帶 `FXTag.emoFamily` 的標籤；
    /// 合作寫法 `The Used & My Chemical Romance` 使用者沒指定歸屬，不列別名
    static let batchFive: [BandEntry] = [
        BandEntry(name: "The Used", profile: SongProfile(axes: [.raw: 0.65, .theatrical: 0.6, .cold: 0.3, .aggression: 0.7, .speed: 0.65, .elegance: 0.2, .decay: 0.55, .bright: 0.25, .bounce: 0.25, .warm: 0.3], tags: [.emo, .posthardcore])),
        BandEntry(name: "My Chemical Romance", profile: SongProfile(axes: [.raw: 0.4, .theatrical: 0.9, .cold: 0.3, .aggression: 0.6, .speed: 0.65, .elegance: 0.5, .decay: 0.5, .bright: 0.3, .bounce: 0.35, .warm: 0.3], tags: [.emo])),
        BandEntry(name: "Death Cab for Cutie", profile: SongProfile(axes: [.raw: 0.2, .theatrical: 0.3, .cold: 0.5, .aggression: 0.1, .speed: 0.3, .elegance: 0.65, .decay: 0.2, .bright: 0.5, .bounce: 0.15, .warm: 0.45], tags: [.indieemo])),
        BandEntry(name: "A Day to Remember", profile: SongProfile(axes: [.raw: 0.5, .theatrical: 0.35, .cold: 0.15, .aggression: 0.7, .speed: 0.8, .elegance: 0.1, .decay: 0.2, .bright: 0.55, .bounce: 0.6, .warm: 0.45], tags: [.posthardcore, .emopop])),
        BandEntry(name: "New Found Glory", profile: SongProfile(axes: [.raw: 0.35, .theatrical: 0.3, .cold: 0.1, .aggression: 0.4, .speed: 0.8, .elegance: 0.15, .decay: 0.1, .bright: 0.75, .bounce: 0.7, .warm: 0.6], tags: [.emopop])),
        BandEntry(name: "You Me At Six", profile: SongProfile(axes: [.raw: 0.3, .theatrical: 0.45, .cold: 0.25, .aggression: 0.4, .speed: 0.6, .elegance: 0.35, .decay: 0.15, .bright: 0.55, .bounce: 0.4, .warm: 0.45], tags: [.emopop])),
        BandEntry(name: "The Story So Far", profile: SongProfile(axes: [.raw: 0.6, .theatrical: 0.2, .cold: 0.2, .aggression: 0.6, .speed: 0.85, .elegance: 0.05, .decay: 0.25, .bright: 0.5, .bounce: 0.45, .warm: 0.4], tags: [.emopop])),
    ]

    /// 正規化後撞鍵的名字（跨正式名與別名）；表要維持空集合（`ArtistOverrideTableTests`）
    static func duplicateKeys(in table: [BandEntry]) -> [String] {
        let counts = table.flatMap(\.keys).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.filter { $0.value > 1 }.map(\.key).sorted()
    }

    /// 撞鍵時先列的團勝出（Release 不因資料錯誤在啟動時 trap）
    static func overrides(from table: [BandEntry]) -> [String: SongProfile] {
        assert(duplicateKeys(in: table).isEmpty, "樂團覆寫表有重複的鍵")
        return Dictionary(table.flatMap { band in band.keys.map { ($0, band.profile) } }, uniquingKeysWith: { first, _ in first })
    }

    /// 單一關鍵字列的軸值由覆寫表中該曲風的代表樂團平均而來（可追溯，不另行手填）。
    /// B1 的黑金屬、交響兩列標籤是手定的，為不變基線（⑥b R3-6）；⑥b 新增的列標籤＝代表團標籤聯集扣 `genreRowPrivateTags`
    static let keywordRows: [KeywordRow] = originalRows + expandedRows

    static let originalRows: [KeywordRow] = [
        legacyRow("black", ["black", "pagan", "depressive", "heathen"], ["Mayhem", "Immortal", "Darkthrone"], tags: [.black]),
        legacyRow("symphonic", ["symphon", "neoclassic", "classical", "religious", "soundtrack", "score"], ["Nightwish", "Epica"], tags: [.symphonic]),
    ]

    /// ⑥b 計劃 §4.7（使用者 2026-10-24 選範圍 B）。`metal` 是 generic。
    /// 使用者 2026-10-24 真機逐列看過後整列拿掉兩列（不調軸值）：heavypower（Iron Maiden＋Nightwish，抽到哥德／交響元件，不像重金屬）、
    /// rock*（AC/DC＋The Beatles，套在 folk rock 上不像）——見 `GenreRowTests.removedRows`
    static let expandedRows: [KeywordRow] = [
        row("melodeath", ["melodic death"], ["Arch Enemy"]),
        row("death", ["death metal", "deathcore", "grind", "brutal death"], ["Cannibal Corpse", "Fleshgod Apocalypse"]),
        row("gothic", ["gothic", "goth rock", "darkwave"], ["Type O Negative", "Cradle of Filth"]),
        row("doom", ["doom", "sludge"], ["Type O Negative", "Burzum"]),
        row("thrash", ["thrash", "groove metal"], ["Slayer", "Arch Enemy"]),
        row("hardrock", ["hard rock", "glam", "heavy rock"], ["AC/DC", "Guns N' Roses"]),
        row("classicrock", ["classic rock", "blues rock", "psychedelic", "progressive rock", "art rock"], ["The Beatles", "Pink Floyd", "Queen"]),
        row("altindie", ["alternative rock", "indie rock", "grunge", "post-grunge", "britpop", "indie"], ["Blur", "Weezer", "Oasis"]),
        row("arena", ["pop rock", "piano rock", "soft rock", "arena rock"], ["Coldplay", "The Killers"]),
        row("poppunk", ["pop punk", "pop-punk"], ["Blink-182", "Green Day", "Sum 41", "Fall Out Boy", "Good Charlotte"]),
        row("punk", ["punk"], ["Ramones", "Sex Pistols", "The Offspring", "NOFX"]),
        row("ska", ["ska"], ["The Interrupters"]),
        row("metalcore", ["metalcore", "hardcore"], ["Hatebreed"]),
        row("nu", ["nu metal", "alternative metal", "rap metal", "rap rock"], ["Korn"]),
        row("metal", ["metal"], ["Iron Maiden", "Slayer"], isGeneric: true),
    ]

    /// 曲風列不得帶的標籤（⑥b R3-1）：emo 群、J-Pop 與批 3 的 Nu 系子標籤是各批私有，重用要重簽；`.nu`（B1 原型）不在此列
    static let genreRowPrivateTags: Set<FXTag> = FXTag.emoFamily.union(FXTag.jpopFamily).union(FXTag.nuFamily.subtracting([.nu]))

    /// 硬軸取 max：一個「狠」的曲風不得被溫柔的曲風稀釋（P11）；其餘軟軸取平均
    static let hardAxes: Set<FXAxis> = [.raw, .aggression, .speed, .decay, .cold, .theatrical]

    static func resolve(
        artist: String, genre: String?, lyrics: LyricsEvidence, artistGenres: ArtistGenres = .unknown, rows: [KeywordRow] = keywordRows
    ) -> ProfileResolution {
        if let profile = signedProfile(artist) { return .signedBand(profile) }
        if lyrics == .unknown { return .pending }
        if lyrics == .text(isJapanese: true) { return .jpop }
        // MB 還沒查、認不出、或碰不到任何列：不等，落到 Apple 曲風（只升不降，⑥b §4.3）
        if case .verified(let genres) = artistGenres, let profile = playable(compose(genres: genres, rows: rows)) {
            return .artistGenreRow(profile)
        }
        guard let genre else { return .pending }
        return playable(compose(genres: [genre], rows: rows)).map(ProfileResolution.genreRow) ?? .noMatch
    }

    /// 要不要為這位歌手查 MB：樂團表的團一律以表為準（與 `resolve` 的第一層同一個判斷）
    static func needsArtistGenres(_ artist: String) -> Bool {
        signedProfile(artist) == nil
    }

    private static func signedProfile(_ artist: String) -> SongProfile? {
        overrides[normalizedArtist(artist)]
    }

    /// 組不出六槽的目標值不算命中（⑥b R3-4）：讓下一層有機會，而不是靜默變成素面
    private static func playable(_ profile: SongProfile?) -> SongProfile? {
        profile.flatMap { Composer.isComposable($0) ? $0 : nil }
    }

    /// genre 命中的所有關鍵字列合成一個目標值；無命中＝nil
    static func compose(genre: String, rows: [KeywordRow]) -> SongProfile? {
        compose(genres: [genre], rows: rows)
    }

    /// 每個 genre 各自比對 → 命中的列去重 → 整體套一次 generic 抑制 → 合成。順序與重複不影響結果（⑥b R3-2）
    static func compose(genres: [String], rows: [KeywordRow] = keywordRows) -> SongProfile? {
        let normalized = genres.map(GenreStyleResolver.normalized)
        let hits = rows.filter { row in row.keywords.contains { keyword in normalized.contains { GenreStyleResolver.genre($0, matches: keyword) } } }
        let specific = hits.filter { !$0.isGeneric }
        return compose(rows: specific.isEmpty ? hits : specific)
    }

    /// 指定的列直接合成（不比對、不抑制 generic）；空＝nil
    static func compose(rows chosen: [KeywordRow]) -> SongProfile? {
        guard !chosen.isEmpty else { return nil }
        var axes: [FXAxis: Double] = [:]
        for axis in FXAxis.allCases {
            let values = chosen.compactMap { $0.axes[axis] }
            guard !values.isEmpty else { continue }
            axes[axis] = hardAxes.contains(axis) ? values.max() : values.reduce(0, +) / Double(values.count)
        }
        return SongProfile(axes: axes, tags: chosen.reduce(into: Set<FXTag>()) { $0.formUnion($1.tags) })
    }

    /// 固定 locale 小寫 → 去變音符號 → 去開頭 `the ` → 只留字母數字（B1 計劃 §3.5；不受使用者系統 locale 影響）
    static func normalizedArtist(_ name: String) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        var folded = name.lowercased(with: posix).folding(options: [.diacriticInsensitive, .widthInsensitive], locale: posix)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if folded.hasPrefix("the ") { folded.removeFirst(4) }
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// B1 的兩列：關鍵字、標籤照舊手定
    private static func legacyRow(_ id: String, _ keywords: [String], _ representatives: [String], tags: Set<FXTag>) -> KeywordRow {
        KeywordRow(id: id, keywords: keywords, representatives: representatives, tags: tags, axes: mean(of: representatives), isGeneric: false)
    }

    /// ⑥b 的列：標籤＝代表團聯集扣私有家族，軸值＝代表團平均
    private static func row(_ id: String, _ keywords: [String], _ representatives: [String], isGeneric: Bool = false) -> KeywordRow {
        let tags = representatives.compactMap(bandProfile).reduce(into: Set<FXTag>()) { $0.formUnion($1.tags) }.subtracting(genreRowPrivateTags)
        return KeywordRow(id: id, keywords: keywords, representatives: representatives, tags: tags, axes: mean(of: representatives), isGeneric: isGeneric)
    }

    /// 以正式名精確查樂團表；每團恰算一次（⑥b R3-5）
    private static func bandProfile(_ name: String) -> SongProfile? {
        bandTable.first { $0.name == name }?.profile
    }

    private static func mean(of artists: [String]) -> [FXAxis: Double] {
        let profiles = artists.compactMap(bandProfile)
        var axes: [FXAxis: Double] = [:]
        for axis in FXAxis.allCases {
            let values = profiles.compactMap { $0.axes[axis] }
            if !values.isEmpty { axes[axis] = values.reduce(0, +) / Double(values.count) }
        }
        return axes
    }

    private static func band(_ tags: Set<FXTag>, _ axes: [FXAxis: Double]) -> SongProfile {
        SongProfile(axes: axes, tags: tags)
    }

    private static let bandTargets: [(String, SongProfile)] = [
        ("Mayhem", band([.black], [.raw: 0.95, .theatrical: 0.1, .cold: 0.7, .aggression: 0.9, .speed: 0.8, .elegance: 0.05, .decay: 0.8, .bright: 0.05])),
        ("Immortal", band([.black], [.raw: 0.85, .theatrical: 0.15, .cold: 0.95, .aggression: 0.8, .speed: 0.75, .elegance: 0.1, .decay: 0.6, .bright: 0.05])),
        ("Darkthrone", band([.black], [.raw: 1, .theatrical: 0.05, .cold: 0.6, .aggression: 0.85, .speed: 0.7, .elegance: 0, .decay: 0.9, .bright: 0])),
        ("Burzum", band([.black, .doom], [.raw: 0.7, .theatrical: 0.2, .cold: 0.85, .aggression: 0.3, .speed: 0.15, .elegance: 0.3, .decay: 0.6, .bright: 0.1])),
        ("Emperor", band([.black, .symphonic], [.raw: 0.4, .theatrical: 0.65, .cold: 0.7, .aggression: 0.7, .speed: 0.7, .elegance: 0.6, .decay: 0.3, .bright: 0.2])),
        ("Cradle of Filth", band([.black, .gothic, .symphonic], [.raw: 0.35, .theatrical: 0.95, .cold: 0.3, .aggression: 0.88, .speed: 0.8, .elegance: 0.45, .decay: 0.7, .bright: 0.05, .bounce: 0, .warm: 0.15])),
        ("Dimmu Borgir", band([.black, .symphonic], [.raw: 0.2, .theatrical: 0.95, .cold: 0.6, .aggression: 0.8, .speed: 0.65, .elegance: 0.55, .decay: 0.3, .bright: 0.1, .bounce: 0, .warm: 0.05])),
        ("Arch Enemy", band([.melodeath, .death, .thrash], [.raw: 0.3, .theatrical: 0.35, .cold: 0.2, .aggression: 0.85, .speed: 0.85, .elegance: 0.4, .decay: 0.3, .bright: 0.3])),
        ("Cannibal Corpse", band([.death, .grind], [.raw: 0.7, .theatrical: 0.1, .cold: 0.1, .aggression: 1, .speed: 0.8, .elegance: 0, .decay: 0.8, .bright: 0])),
        ("Hatebreed", band([.hardcore, .nu], [.raw: 0.6, .theatrical: 0, .cold: 0.1, .aggression: 0.95, .speed: 0.9, .elegance: 0, .decay: 0.3, .bright: 0.2])),
        ("Nightwish", band([.symphonic, .power], [.raw: 0.05, .theatrical: 1, .cold: 0.3, .aggression: 0.3, .speed: 0.5, .elegance: 0.95, .decay: 0.05, .bright: 0.7])),
        ("Type O Negative", band([.gothic, .doom], [.raw: 0.3, .theatrical: 0.6, .cold: 0.4, .aggression: 0.3, .speed: 0.15, .elegance: 0.7, .decay: 0.6, .bright: 0.1])),
        ("Iron Maiden", band([.heavy, .power], [.raw: 0.3, .theatrical: 0.5, .cold: 0.2, .aggression: 0.6, .speed: 0.7, .elegance: 0.4, .decay: 0.2, .bright: 0.6])),
        ("Slayer", band([.thrash, .death], [.raw: 0.6, .theatrical: 0.15, .cold: 0.2, .aggression: 0.95, .speed: 1, .elegance: 0.05, .decay: 0.4, .bright: 0.1])),
        ("Rammstein", band([.industrial], [.raw: 0.3, .theatrical: 0.85, .cold: 0.8, .aggression: 0.85, .speed: 0.35, .elegance: 0.25, .decay: 0.2, .bright: 0.15, .bounce: 0, .warm: 0.15])),
        ("Korn", band([.nu], [.raw: 0.6, .theatrical: 0.3, .cold: 0.2, .aggression: 0.8, .speed: 0.6, .elegance: 0.05, .decay: 0.5, .bright: 0.4, .bounce: 0.4, .warm: 0.1])),
        ("Epica", band([.symphonic, .power, .melodeath], [.raw: 0.1, .theatrical: 0.95, .cold: 0.3, .aggression: 0.5, .speed: 0.6, .elegance: 0.9, .decay: 0.1, .bright: 0.5, .bounce: 0.1, .warm: 0.3])),
        ("Fleshgod Apocalypse", band([.symphonic, .death, .thrash], [.raw: 0.4, .theatrical: 0.85, .cold: 0.3, .aggression: 0.95, .speed: 0.95, .elegance: 0.6, .decay: 0.4, .bright: 0.2, .bounce: 0.1, .warm: 0.1])),
        ("The Chemical Brothers", band([.bigbeat, .electro, .techno], [.raw: 0.4, .theatrical: 0.5, .cold: 0.4, .aggression: 0.6, .speed: 0.8, .elegance: 0.2, .decay: 0.2, .bright: 0.6, .bounce: 0.6, .warm: 0.3])),
        ("Fatboy Slim", band([.bigbeat, .house, .electro], [.raw: 0.3, .theatrical: 0.5, .cold: 0.2, .aggression: 0.4, .speed: 0.8, .elegance: 0.1, .decay: 0.2, .bright: 0.8, .bounce: 0.9, .warm: 0.6])),
        ("Daft Punk", band([.frenchhouse, .house, .electro], [.raw: 0.05, .theatrical: 0.6, .cold: 0.4, .aggression: 0.2, .speed: 0.7, .elegance: 0.7, .decay: 0, .bright: 0.9, .bounce: 0.6, .warm: 0.5])),
        ("Aphex Twin", band([.idm, .ambient, .techno], [.raw: 0.5, .theatrical: 0.3, .cold: 0.8, .aggression: 0.4, .speed: 0.5, .elegance: 0.4, .decay: 0.4, .bright: 0.3, .bounce: 0.2, .warm: 0.1])),
        ("The Offspring", band([.punk, .skatepunk, .rock], [.raw: 0.5, .theatrical: 0.2, .cold: 0.2, .aggression: 0.6, .speed: 0.85, .elegance: 0.1, .decay: 0.3, .bright: 0.5, .bounce: 0.3, .warm: 0.4])),
        ("Blink-182", band([.poppunk, .skatepunk, .punk], [.raw: 0.3, .theatrical: 0.3, .cold: 0.1, .aggression: 0.4, .speed: 0.85, .elegance: 0.1, .decay: 0.2, .bright: 0.7, .bounce: 0.6, .warm: 0.6])),
        ("Green Day", band([.punk, .poppunk, .rock], [.raw: 0.45, .theatrical: 0.35, .cold: 0.15, .aggression: 0.5, .speed: 0.8, .elegance: 0.2, .decay: 0.3, .bright: 0.6, .bounce: 0.45, .warm: 0.5])),
        ("Sum 41", band([.poppunk, .skatepunk], [.raw: 0.3, .theatrical: 0.3, .cold: 0.1, .aggression: 0.5, .speed: 0.9, .elegance: 0.1, .decay: 0.2, .bright: 0.8, .bounce: 0.85, .warm: 0.6])),
        ("Ramones", band([.punk77, .punk], [.raw: 0.8, .theatrical: 0.1, .cold: 0.2, .aggression: 0.6, .speed: 0.95, .elegance: 0, .decay: 0.6, .bright: 0.4, .bounce: 0.5, .warm: 0.3])),
        ("Sex Pistols", band([.punk77, .punk], [.raw: 0.9, .theatrical: 0.4, .cold: 0.2, .aggression: 0.8, .speed: 0.8, .elegance: 0, .decay: 0.7, .bright: 0.4, .bounce: 0.4, .warm: 0.2])),
    ]
}
