import CoreGraphics
import Foundation

/// 中日文的斷行規則（⑤ 中日韓字型計劃 §4.4）：中日文字之間可斷、不加詞距；最小禁則；找不到允許的斷點時違例退路。
/// 組合樣式與素面共用。純英文只有「空白處可斷」，與改動前的貪婪折行完全相同
enum CJKLineBreak {
    /// 不能放在列首
    static let closing: Set<Character> = ["、", "。", "，", "．", "！", "？", "」", "』", "）", "〕", "】", "・", "ー"]
    /// 不能放在列尾
    static let opening: Set<Character> = ["「", "『", "（", "〔", "【"]

    /// 排版單位：中日文一字一個，其餘連續的字一個；token 之間都是候選斷點
    struct Token: Equatable {
        let width: CGFloat
        /// 與前一個 token 同列時要加的間距（原文空白處＝詞距，其餘 0）
        let gapBefore: CGFloat
        let first: Character
        let last: Character
        /// 超寬詞逐字斷開的第一個字：所在列已有字就換列（沿用改動前的超寬詞行為）
        var forcesNewRow = false
    }

    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: LyricsScript.isCJK)
    }

    /// 字串切成 token：原文的空白是詞界；詞內的中日文字各自一個、其餘連續字一個（字素叢集為單位，不拆 emoji）
    static func tokens(of text: String) -> [(text: String, spaceBefore: Bool)] {
        var result: [(text: String, spaceBefore: Bool)] = []
        for (wordIndex, word) in text.split(whereSeparator: \.isWhitespace).enumerated() {
            var run = ""
            var first = true
            func flush() {
                guard !run.isEmpty else { return }
                result.append((run, first && wordIndex > 0))
                first = false
                run = ""
            }
            for character in word {
                if isCJK(character) {
                    flush()
                    result.append((String(character), first && wordIndex > 0))
                    first = false
                } else {
                    if let last = run.last, isCJK(last) { flush() }
                    run.append(character)
                }
            }
            flush()
        }
        return result
    }

    /// 兩個 token 之間可以斷嗎（禁則）
    static func canBreak(between before: Token, and after: Token) -> Bool {
        !closing.contains(after.first) && !opening.contains(before.last)
    }

    /// 貪婪分列，回傳每個 token 的列號。放不下時往回找最近的允許斷點；找不到：收尾標點懸在列尾、開頭標點帶到下一列，其餘照寬度硬斷
    static func assignRows(_ tokens: [Token], maxWidth: CGFloat) -> [Int] {
        var rowOf: [Int] = []
        var rowStart = 0
        var row = 0
        var width: CGFloat = 0
        for (index, token) in tokens.enumerated() {
            if index == rowStart {
                rowOf.append(row)
                width = token.width
                continue
            }
            if !token.forcesNewRow, width + token.gapBefore + token.width <= maxWidth {
                rowOf.append(row)
                width += token.gapBefore + token.width
                continue
            }
            let breakAt = token.forcesNewRow ? index : breakPoint(tokens, rowStart: rowStart, before: index)
            guard let breakAt else {
                // 收尾標點懸在列尾（不換列）
                rowOf.append(row)
                width += token.gapBefore + token.width
                continue
            }
            row += 1
            rowStart = breakAt
            for moved in breakAt..<index { rowOf[moved] = row }
            rowOf.append(row)
            width = tokens[breakAt...index].enumerated().reduce(0) { sum, item in
                sum + item.element.width + (item.offset == 0 ? 0 : item.element.gapBefore)
            }
        }
        return rowOf
    }

    /// 換列要斷在哪個 token 之前；nil＝懸掛（`before` 是收尾標點且整列找不到允許的斷點）
    private static func breakPoint(_ tokens: [Token], rowStart: Int, before index: Int) -> Int? {
        var candidate = index
        while candidate > rowStart {
            if canBreak(between: tokens[candidate - 1], and: tokens[candidate]) { return candidate }
            candidate -= 1
        }
        if closing.contains(tokens[index].first) { return nil }
        if opening.contains(tokens[index - 1].last), index - 1 > rowStart { return index - 1 }
        return index
    }
}
