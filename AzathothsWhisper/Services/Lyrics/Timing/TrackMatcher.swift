import Foundation

/// 嚴格曲目比對（C 段計劃 §3.3）：歌手、曲名正規化後相符，時長差 ≤ 3 s，版本標記相容。
/// 規則與案例來自 2026-10-19 探針；版本護欄經 Codex 三輪辯論（計劃附錄 A #6）
enum TrackMatcher {
    static let durationTolerance: Double = 3
    /// 正規化後不超過這個長度的名稱只認完全相等（短名容一個字就會撞別首）
    static let shortNameLength = 4

    /// 括號或 ` - ` 尾綴裡出現這些詞＝版本不同的錄音
    static let versionKeywords: Set<String> = [
        "live", "acoustic", "unplugged", "demo", "remix", "mix", "edit", "version", "instrumental",
        "karaoke", "cover", "session", "take", "伴奏",
    ]
    /// 同一份錄音的重製：整段標記忽略（含其中的年份）
    static let remasterWords: Set<String> = ["remaster", "remastered"]

    /// 名稱長度上限：正規化用的 regex 對長字串是二次方回溯，外部候選可惡意塞長（安全評審 HIGH-3）
    static let maxNameLength = 300

    static func matches(_ wanted: TimingQuery, _ candidate: MatchedTrack) -> Bool {
        quality(wanted, candidate) != nil
    }

    /// 配對成功時有多接近（候選排序用）；nil＝不配對。配對與排序的唯一定義
    static func quality(_ wanted: TimingQuery, _ candidate: MatchedTrack) -> MatchQuality? {
        guard let duration = candidate.duration, abs(duration - wanted.duration) <= durationTolerance,
              [wanted.artist, wanted.title, candidate.artist, candidate.title].allSatisfy({ $0.count <= maxNameLength }),
              let artistDistance = artistDistance(wanted.artist, candidate.artist),
              let titleDistance = nameDistance(normalized(wanted.title), normalized(candidate.title)),
              versionsCompatible(versionWords(of: wanted.title), versionWords(of: candidate.title))
        else { return nil }
        let isExact = exactKey(wanted.artist) == exactKey(candidate.artist) && exactKey(wanted.title) == exactKey(candidate.title)
        return MatchQuality(isExact: isExact, titleDistance: titleDistance, artistDistance: artistDistance, durationGap: abs(duration - wanted.duration))
    }

    /// 去括號註記、版本尾綴、feat.、開頭 the、附加符號與標點，只留字母與數字
    static func normalized(_ text: String) -> String {
        var value = folded(text)
        value = value.replacing(bracketed, with: " ")
        if let suffix = value.firstMatch(of: dashSuffix), isVersionFragment(String(suffix.1)) {
            value = String(value[..<suffix.range.lowerBound])
        }
        value = value.replacing(featuring, with: "")
        value = value.trimmingCharacters(in: .whitespaces).replacing(leadingArticle, with: "")
        return String(value.filter { $0.isLetter || $0.isNumber })
    }

    // MARK: 內部

    // Regex 不是 Sendable：照 `LRCParser` 的寫法用計算屬性
    private static var bracketed: Regex<Substring> { /[\(\[（【][^\)\]）】]*[\)\]）】]/ }
    private static var dashSuffix: Regex<(Substring, Substring)> { /\s+[-–—]\s+(.+)$/ }
    private static var featuring: Regex<(Substring, Substring)> { /\b(feat|ft)\.?\s.*$/ }
    private static var leadingArticle: Regex<Substring> { /^the\s+/ }
    private static var artistSeparators: Regex<Substring> { /\s*(?:,|&|\/|、)\s*/ }

    /// 同 `SongProfileResolver.normalizedArtist`：固定 POSIX、寬度不敏感（全形英數＝半形），不受使用者 locale 影響
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "Æ", with: "AE").replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Ø", with: "O").replacingOccurrences(of: "ø", with: "o")
            .lowercased(with: posix)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: posix)
    }

    /// 「完全一致」的比較鍵：folding 後去頭尾空白、連續空白收成一個（不去標點，`AC/DC` 與 `ACDC` 不算完全一致）
    private static func exactKey(_ text: String) -> String {
        folded(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 整串（`AC/DC`）與拆成多位歌手後逐一比，取最接近者；都不中＝nil
    private static func artistDistance(_ wanted: String, _ candidate: String) -> Int? {
        let target = normalized(wanted)
        let parts = [candidate] + candidate.split(separator: artistSeparators).map(String.init)
        return parts.compactMap { nameDistance(target, normalized($0)) }.min()
    }

    /// 相等＝0；兩邊都長於 `shortNameLength` 時容一個字＝1；其餘＝nil（不配對）
    private static func nameDistance(_ left: String, _ right: String) -> Int? {
        guard !left.isEmpty, !right.isEmpty else { return nil }
        if left == right { return 0 }
        guard min(left.count, right.count) > shortNameLength else { return nil }
        let distance = EditDistance.between(Array(left), Array(right), limit: 1)
        return distance <= 1 ? distance : nil
    }

    /// 所有版本標記片段的詞（括號內容＋版本尾綴）；不是版本標記的片段（翻譯、feat.、deluxe）不算
    private static func versionWords(of title: String) -> Set<String> {
        let text = folded(title)
        var fragments = text.matches(of: bracketed).map { String(text[$0.range].dropFirst().dropLast()) }
        if let suffix = text.replacing(bracketed, with: " ").firstMatch(of: dashSuffix) { fragments.append(String(suffix.1)) }
        return fragments.filter(isVersionFragment).reduce(into: Set<String>()) { $0.formUnion(words(of: $1)) }
    }

    /// 版本標記＝含版本關鍵詞（re-record 連寫也算），或整段只是年份；含 remaster 的整段一律不算
    private static func isVersionFragment(_ fragment: String) -> Bool {
        let tokens = words(of: fragment)
        guard tokens.isDisjoint(with: remasterWords) else { return false }
        if !tokens.isDisjoint(with: versionKeywords) || tokens.joined().contains("rerecord") { return true }
        return !tokens.isEmpty && tokens.allSatisfy { $0.count == 4 && $0.allSatisfy(\.isNumber) }
    }

    private static func words(of fragment: String) -> Set<String> {
        Set(folded(fragment).split { !($0.isLetter || $0.isNumber) }.map(String.init))
    }

    /// 都沒有版本標記，或一方的詞是另一方的子集（`Live` ⊂ `Live 1991`）；`Live at Glastonbury` 對 `Live at Reading` 不相容
    private static func versionsCompatible(_ left: Set<String>, _ right: Set<String>) -> Bool {
        left.isSubset(of: right) && !left.isEmpty || right.isSubset(of: left) && !right.isEmpty || left.isEmpty && right.isEmpty
    }
}
