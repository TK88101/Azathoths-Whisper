import Foundation

struct LRCLine: Equatable, Sendable {
    let start: Double
    let text: String
}

/// 層 1：Music 欄位內嵌的 LRC（母計劃 §2.4）。
///
/// 支援：一行多個時間標籤、`[mm:ss]`／`.x`／`.xx`／`.xxx`／`:xx`、`[offset:±ms]`（LRC 標準：正值＝提早）、
/// ID 標籤（`[ti:]` 等）略過、enhanced LRC 的 `<mm:ss.xx>` 逐字標籤剝除、CR／LF 都收。
/// 時間以整數毫秒計算再換成秒，避免浮點累加誤差
enum LRCParser {
    private static var timeTag: Regex<(Substring, Substring, Substring, Substring?)> { /^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/ }
    private static var wordTag: Regex<Substring> { /<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>/ }
    private static var offsetTag: Regex<(Substring, Substring)> { /\[offset:\s*([+-]?\d+)\s*\]/ }
    private static var idTagLine: Regex<Substring> { /^\[[A-Za-z]+:.*\]$/ }

    static func parse(_ text: String) -> [LRCLine] {
        let lines = LineEndings.normalized(text).components(separatedBy: "\n")
        let offset = lines.lazy.compactMap { $0.firstMatch(of: offsetTag).flatMap { Int($0.1) } }.first ?? 0
        let parsed = lines.flatMap { line -> [(milliseconds: Int, text: String)] in
            let (stamps, rest) = leadingStamps(of: line.trimmingCharacters(in: .whitespaces))
            let text = cleaned(rest)
            return stamps.map { ($0, text) }
        }
        // 穩定排序：同時刻的行保持原順序
        return parsed.enumerated()
            .sorted { ($0.element.milliseconds, $0.offset) < ($1.element.milliseconds, $1.offset) }
            .map { LRCLine(start: Double(max(0, $0.element.milliseconds - offset)) / 1000, text: $0.element.text) }
    }

    /// 非空行（ID 標籤行不算）中帶時間標籤者過半，且至少一行
    static func isLRC(_ text: String) -> Bool {
        let counted = LineEndings.normalized(text)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isIDTagLine($0) }
        let timed = counted.filter { $0.prefixMatch(of: timeTag) != nil }.count
        return timed >= 1 && timed * 2 >= counted.count
    }

    private static func isIDTagLine(_ line: String) -> Bool {
        line.prefixMatch(of: timeTag) == nil && line.wholeMatch(of: idTagLine) != nil
    }

    private static func leadingStamps(of line: String) -> ([Int], Substring) {
        var stamps: [Int] = []
        var rest = Substring(line)
        while let match = rest.prefixMatch(of: timeTag) {
            stamps.append(milliseconds(minutes: match.1, seconds: match.2, fraction: match.3))
            rest = rest[match.range.upperBound...]
        }
        return (stamps, rest)
    }

    private static func milliseconds(minutes: Substring, seconds: Substring, fraction: Substring?) -> Int {
        let whole = (Int(minutes) ?? 0) * 60_000 + (Int(seconds) ?? 0) * 1000
        guard let fraction, let value = Int(fraction) else { return whole }
        let scale = [1: 100, 2: 10, 3: 1][fraction.count] ?? 0
        return whole + value * scale
    }

    private static func cleaned(_ text: Substring) -> String {
        String(text).replacing(wordTag, with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
