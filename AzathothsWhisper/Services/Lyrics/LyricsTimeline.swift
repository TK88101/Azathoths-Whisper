import Foundation

/// 時間從哪裡來（母計劃 C.3 的退路順序）。**一個 enum**：存檔只收其子集 `StoredTimingSource`
enum TimingSource: String, Sendable, Codable, CaseIterable {
    case embeddedLRC, lrclib, youtubeMusic, deezer, qq, netease, estimated
}

struct TimedWord: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

struct TimedLine: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
    let isChorus: Bool
    /// 字出完的時刻（≤ `end`）：外部與內嵌 LRC 由 `WordPacing` 限速，其餘等於 `end`
    let revealEnd: Double
    let words: [TimedWord]
    /// 這一行的文字種類（建行時算一次，繪製時不重掃）
    let script: LineScript

    init(start: Double, end: Double, text: String, isChorus: Bool, revealEnd: Double? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.isChorus = isChorus
        self.revealEnd = revealEnd ?? end
        self.words = TimedWord.split(text, start: start, end: self.revealEnd)
        script = LyricsScript.line(text)
    }
}

/// 可顯示的時間軸。不存檔（存的是 `TimingRecord`）
struct LyricsTimeline: Equatable, Sendable {
    let lines: [TimedLine]
    let source: TimingSource
    let duration: Double
    /// 整首的中日文之分（只在 `.cjk` 行選字型時用）
    let cjkLanguage: CJKLanguage

    init(lines: [TimedLine], source: TimingSource, duration: Double) {
        self.lines = lines
        self.source = source
        self.duration = duration
        cjkLanguage = LyricsScript.language(of: lines.map(\.text))
    }
}

extension TimedWord {
    /// 行內逐字：有空白按詞、無空白而含 CJK 按字、其餘整行一詞；時長∝字數（母計劃 §2.4）
    static func split(_ text: String, start: Double, end: Double) -> [TimedWord] {
        let tokens = tokens(of: text)
        let total = tokens.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        let span = end - start
        var cursor = start
        var consumed = 0
        return tokens.map { token in
            consumed += token.count
            let tokenEnd = start + span * Double(consumed) / Double(total)
            defer { cursor = tokenEnd }
            return TimedWord(start: cursor, end: tokenEnd, text: token)
        }
    }

    private static func tokens(of text: String) -> [String] {
        if text.contains(where: \.isWhitespace) {
            return text.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        if text.unicodeScalars.contains(where: JapaneseText.isKanaOrKanji) {
            return text.map(String.init)
        }
        return text.isEmpty ? [] : [text]
    }
}

/// 假名與漢字的判定（曲風體系判定與逐字切分共用）
enum JapaneseText {
    static func isKanaOrKanji(_ scalar: Unicode.Scalar) -> Bool {
        LyricsScript.isKana(scalar) || LyricsScript.isHan(scalar)
    }
}
