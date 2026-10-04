import Foundation

/// 段落標籤的種類（母計劃 §2.4 層 3）
enum LyricsSectionKind: Equatable, Sendable {
    /// Chorus／Refrain／Pre-Chorus／Post-Chorus／Hook：之後到下一個標籤前的行是サビ
    case chorus
    /// Instrumental／Solo／Intro／Outro／Break／Interlude：一段無字的間奏
    case interlude
    /// 其餘（Verse、Bridge…）：只當段落分隔
    case other
}

enum LyricsLine: Equatable, Sendable {
    case lyric(String, isChorus: Bool)
    case section(LyricsSectionKind)
    case blank
}

/// 把 Music 欄位的純文字切成行並分類。**估算與對齊共用這一份**（A1 計劃 §3.4）：
/// 兩邊各自判段落標籤，Genius 的 `[Chorus: X]` 這類寫法一漂移，存檔的行序就會對不上
enum LyricsLines {
    // Regex 不是 Sendable，不能做 static let（Swift 6 strict concurrency）
    private static var sectionPattern: Regex<(Substring, Substring)> { /^\[(.+)\]$/ }
    private static var timestampPrefix: Regex<Substring> { /^\[\d{1,3}:\d/ }
    private static var chorusWords: Regex<(Substring, Substring)> { /\b(chorus|refrain|hook)\b/ }
    private static var interludeWords: Regex<(Substring, Substring)> { /\b(instrumental|solo|intro|outro|break|interlude)\b/ }

    static func parse(_ text: String) -> [LyricsLine] {
        var inChorus = false
        return LineEndings.normalized(text)
            .components(separatedBy: "\n")
            .map { raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { return .blank }
                if let kind = sectionKind(of: line) {
                    inChorus = (kind == .chorus)
                    return .section(kind)
                }
                return .lyric(line, isChorus: inChorus)
            }
    }

    /// 只要可顯示的歌詞行（存檔的 `index` 就是這個陣列的序號）
    static func lyricTexts(_ text: String) -> [String] {
        parse(text).compactMap { line in
            if case .lyric(let text, _) = line { return text }
            return nil
        }
    }

    private static func sectionKind(of line: String) -> LyricsSectionKind? {
        guard let match = line.wholeMatch(of: sectionPattern),
              line.prefixMatch(of: timestampPrefix) == nil
        else { return nil }
        // 只看冒號前（`[Chorus: James]`），不分大小寫
        let name = String(match.1).split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        if name.contains(chorusWords) { return .chorus }
        if name.contains(interludeWords) { return .interlude }
        return .other
    }
}
