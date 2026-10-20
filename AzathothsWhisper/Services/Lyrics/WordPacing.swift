import Foundation

/// 行內逐字的最慢速度（docs/plans/2026-10-19-lyrics-fx-word-pacing.md §3）：行終點＝下一行起點會把停頓、間奏都攤進字裡，
/// 字因此比歌聲晚。外部與內嵌 LRC 改成在 `0.08 s×字數 + 0.40 s×詞數` 內出完，行本身仍停到下一行起點。
/// 只評估過英文（網易雲 yrc 30 首）：只套用在 Latin 字母、以空白分詞的行；CJK、韓文、其他文字照舊
enum WordPacing {
    static let secondsPerCharacter = 0.08
    static let secondsPerWord = 0.40

    static func revealEnd(text: String, start: Double, lineEnd: Double) -> Double {
        guard start.isFinite, lineEnd.isFinite, isPaced(text) else { return lineEnd }
        guard lineEnd > start else { return start }
        let words = text.split(whereSeparator: \.isWhitespace)
        let characters = words.reduce(0) { $0 + $1.count }
        let singing = secondsPerCharacter * Double(characters) + secondsPerWord * Double(words.count)
        return start + min(lineEnd - start, singing)
    }

    /// 與 `TimedWord.split` 同一個分詞規則：有空白才按詞分；字母全是 Latin 才套用
    static func isPaced(_ text: String) -> Bool {
        guard text.contains(where: \.isWhitespace) else { return false }
        let letters = text.unicodeScalars.filter(\.properties.isAlphabetic)
        return !letters.isEmpty && letters.allSatisfy(isLatin)
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: return true
        default: return false
        }
    }
}
