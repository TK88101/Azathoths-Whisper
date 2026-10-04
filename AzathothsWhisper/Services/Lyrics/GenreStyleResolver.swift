import Foundation

enum LyricsSystem: Sendable {
    case japanese
    case english
}

/// 歌詞特效的家族（母計劃 §2.5；§2.10 的元件組合器在 B 段以家族為起點）
enum StyleFamily: String, CaseIterable, Sendable {
    case jrock, jpop
    case cathedral, velvet, frost, slab, stencil, riot, block, circuit, hearth, pop, indie, chrome, rock, mono
}

struct GenreStyle: Equatable, Sendable {
    let family: StyleFamily

    /// 由家族推出：「英語系＋jpop」這種組合從型別上就不存在
    var system: LyricsSystem {
        switch family {
        case .jrock, .jpop: return .japanese
        default: return .english
        }
    }
}

/// Music 的 genre 標籤（＋歌詞文字）→ 體系＋家族（母計劃 §2.5；A1 計劃 §3.5）。
///
/// 曲庫標籤很雜（斜線複合、尾端空白、日文、大小寫不一），所以是「切詞＋子字串＋優先序」規則，不是精確比對。
/// **順序即優先序，首個命中者勝**。pagan／heathen 歸 frost（2026-10-04 查證定論，A1 計劃附錄 A.3）
enum GenreStyleResolver {
    /// 歌詞中「字母類字元」裡假名＋漢字的占比達此值即視為日本語系
    static let japaneseRatioThreshold = 0.3
    /// 長度不超過此值的關鍵字只比整詞（防 trap→rap、democore→emo）
    static let wholeWordMaxLength = 3

    private static let separators = CharacterSet(charactersIn: "/,&+- ").union(.whitespaces)

    private static let japaneseTags = ["ロック", "j-pop"]

    private static let englishRules: [(StyleFamily, [String])] = [
        (.cathedral, ["symphon", "neoclassic", "classical", "religious", "soundtrack", "score"]),
        (.velvet, ["goth", "doom"]),
        (.frost, ["black", "pagan", "depressive", "heathen"]),
        (.slab, ["death", "grind", "brutal"]),
        (.stencil, ["nu", "industrial", "groove", "new wave of american"]),
        (.riot, ["punk", "hardcore", "emo"]),
        (.block, ["hip-hop", "rap", "r&b", "soul"]),
        (.circuit, ["electronic", "dance", "house", "techno"]),
        (.hearth, ["viking", "folk", "country", "world"]),
        (.pop, ["pop", "afro", "tropical"]),
        (.indie, ["alternative", "indie", "britpop"]),
        (.chrome, ["thrash", "heavy", "speed", "power", "progressive", "metal"]),
        (.rock, ["hard rock", "rock"]),
    ]

    static func resolve(genre: String?, lyrics: String?) -> GenreStyle {
        let tag = (genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isJapanese = japaneseTags.contains { tag.contains($0) }
            || japaneseRatio(lyrics ?? "") >= japaneseRatioThreshold
        if isJapanese {
            return GenreStyle(family: tag.contains("pop") ? .jpop : .jrock)
        }
        let tokens = Set(tag.components(separatedBy: separators).filter { !$0.isEmpty })
        let family = englishRules.first { _, keywords in
            keywords.contains { matches($0, tag: tag, tokens: tokens) }
        }?.0 ?? .mono
        return GenreStyle(family: family)
    }

    /// 字母類字元中假名＋漢字的比例；沒有字母＝0
    static func japaneseRatio(_ text: String) -> Double {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return 0 }
        let japanese = letters.filter { $0.unicodeScalars.first.map(JapaneseText.isKanaOrKanji) ?? false }
        return Double(japanese.count) / Double(letters.count)
    }

    private static func matches(_ keyword: String, tag: String, tokens: Set<String>) -> Bool {
        let hasSeparator = keyword.unicodeScalars.contains { separators.contains($0) }
        if !hasSeparator && keyword.count <= wholeWordMaxLength {
            return tokens.contains(keyword)
        }
        return tag.contains(keyword)
    }
}
