import Foundation

/// 時間從哪裡來（母計劃 C.3 的退路順序）。**一個 enum**：存檔只收其子集 `StoredTimingSource`
enum TimingSource: String, Sendable, Codable, CaseIterable {
    case embeddedLRC, lrclib, youtubeMusic, deezer, qq, kugou, estimated
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
    let words: [TimedWord]

    init(start: Double, end: Double, text: String, isChorus: Bool) {
        self.start = start
        self.end = end
        self.text = text
        self.isChorus = isChorus
        self.words = TimedWord.split(text, start: start, end: end)
    }
}

/// 可顯示的時間軸。不存檔（存的是 `TimingRecord`）
struct LyricsTimeline: Equatable, Sendable {
    let lines: [TimedLine]
    let source: TimingSource
    let duration: Double
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
        switch scalar.value {
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF,   // 平假名、片假名、片假名擴充
             0x3400...0x4DBF, 0x4E00...0x9FFF:                     // CJK 擴充 A、基本漢字
            return true
        default:
            return false
        }
    }
}
