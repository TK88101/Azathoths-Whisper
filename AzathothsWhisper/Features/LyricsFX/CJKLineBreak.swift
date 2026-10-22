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
        /// 開頭是收尾標點（不能放列首）／結尾是開頭標點（不能放列尾）。存布林值：顯示字可能不止一個字素（「ß」大寫＝「SS」）
        let cannotStartRow: Bool
        let cannotEndRow: Bool
        /// 超寬詞逐字斷開的第一個字：所在列已有字就換列（沿用改動前的超寬詞行為）
        var forcesNewRow = false

        init(width: CGFloat, gapBefore: CGFloat, leading: String, trailing: String, forcesNewRow: Bool = false) {
            self.width = width
            self.gapBefore = gapBefore
            cannotStartRow = leading.first.map(closing.contains) ?? false
            cannotEndRow = trailing.last.map(opening.contains) ?? false
            self.forcesNewRow = forcesNewRow
        }
    }

    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: LyricsScript.isCJK)
    }

    /// 這個字要不要開一個新 token（切 token 的唯一規則，組合與素面共用）：原文空白處、中日文字前後都是邊界；其餘連續的字同一個
    static func startsToken(isCJK: Bool, previousIsCJK: Bool?, spaceBefore: Bool) -> Bool {
        guard let previousIsCJK else { return true }
        return spaceBefore || isCJK || previousIsCJK
    }

    /// 字串切成 token（字素叢集為單位，不拆 emoji）
    static func tokens(of text: String) -> [(text: String, spaceBefore: Bool)] {
        var result: [(text: String, spaceBefore: Bool)] = []
        var previousIsCJK: Bool?
        for (wordIndex, word) in text.split(whereSeparator: \.isWhitespace).enumerated() {
            for (offset, character) in word.enumerated() {
                let cjk = isCJK(character)
                let spaceBefore = offset == 0 && wordIndex > 0
                if startsToken(isCJK: cjk, previousIsCJK: previousIsCJK, spaceBefore: spaceBefore) {
                    result.append((String(character), spaceBefore))
                } else {
                    result[result.count - 1].text.append(character)
                }
                previousIsCJK = cjk
            }
        }
        return result
    }

    /// 兩個 token 之間可以斷嗎（禁則）
    static func canBreak(between before: Token, and after: Token) -> Bool {
        !after.cannotStartRow && !before.cannotEndRow
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
        if tokens[index].cannotStartRow { return nil }
        if tokens[index - 1].cannotEndRow, index - 1 > rowStart { return index - 1 }
        return index
    }
}
