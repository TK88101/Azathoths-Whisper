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
}

/// 歌曲目標值
struct SongProfile: Equatable, Sendable {
    let axes: [FXAxis: Double]
    let tags: Set<FXTag>
}

/// `pending`＝genre 還沒讀到（會等）；`mono`＝讀到了但無已知關鍵字（定論）
enum ProfileResolution: Equatable, Sendable {
    case pending
    case mono
    case profile(SongProfile)
}

/// 歌曲目標值的來源（B1 計劃 §3.5）：樂團覆寫表 → genre 關鍵字合成
enum SongProfileResolver {
    struct KeywordRow: Sendable {
        let keywords: [String]
        let tags: Set<FXTag>
        let axes: [FXAxis: Double]
        /// generic（metal、rock…）只在沒有任何非 generic 命中時才貢獻
        let isGeneric: Bool
    }

    /// 樂團覆寫表：使用者在探針 P2、P9–P11 給的判據，原樣抄自原型 `composer.js:123-152` 的 TARGETS（等 D 段 Jev 取代）。
    /// 鍵＝`normalizedArtist`
    static let overrides: [String: SongProfile] = Dictionary(uniqueKeysWithValues: bandTargets.map { (normalizedArtist($0.0), $0.1) })

    /// 單一關鍵字列的軸值由覆寫表中該曲風的代表樂團平均而來（可追溯，不另行手填）；B1 只填黑金屬與交響兩列，其餘 genre＝mono
    static let keywordRows: [KeywordRow] = [
        KeywordRow(keywords: ["black", "pagan", "depressive", "heathen"], tags: [.black], axes: mean(of: ["Mayhem", "Immortal", "Darkthrone"]), isGeneric: false),
        KeywordRow(keywords: ["symphon", "neoclassic", "classical", "religious", "soundtrack", "score"], tags: [.symphonic], axes: mean(of: ["Nightwish", "Epica"]), isGeneric: false),
    ]

    /// 硬軸取 max：一個「狠」的曲風不得被溫柔的曲風稀釋（P11）；其餘軟軸取平均
    static let hardAxes: Set<FXAxis> = [.raw, .aggression, .speed, .decay, .cold, .theatrical]

    static func resolve(artist: String, genre: String?) -> ProfileResolution {
        if let profile = overrides[normalizedArtist(artist)] { return .profile(profile) }
        guard let genre else { return .pending }
        return compose(genre: genre, rows: keywordRows).map(ProfileResolution.profile) ?? .mono
    }

    /// genre 命中的所有關鍵字列合成一個目標值；無命中＝nil
    static func compose(genre: String, rows: [KeywordRow]) -> SongProfile? {
        let hits = rows.filter { row in row.keywords.contains { GenreStyleResolver.genre(genre, matches: $0) } }
        let specific = hits.filter { !$0.isGeneric }
        let chosen = specific.isEmpty ? hits : specific
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

    private static func mean(of artists: [String]) -> [FXAxis: Double] {
        let profiles = artists.compactMap { name in bandTargets.first { $0.0 == name }?.1 }
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
