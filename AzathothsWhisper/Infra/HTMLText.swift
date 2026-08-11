import Foundation
import SwiftSoup

// BeautifulSoup 文本提取的等價實現。
// bs4 的 get_text(separator:) ＝ 以 separator 連接所有後代「字串節點」；
// script/style 內容在 bs4 是 Script/Stylesheet 型別、在 SwiftSoup 是 DataNode，兩邊都不算字串節點，
// 注釋亦然——故此處只收集 TextNode，並跳過 script/style 子樹。
enum HTMLText {
    // 迭代（非遞迴）深度優先走訪：Genius 頁面的 DOM 可達數千層，遞迴會在預設執行緒堆疊上
    // SIGBUS（M2 審查第 6 條）。顯式堆疊同時保證與 bs4 一致的文件順序。
    static func text(of element: Element, separator: String) -> String {
        var parts: [String] = []
        var stack: [Node] = element.getChildNodes().reversed()

        while let node = stack.popLast() {
            if let text = node as? TextNode {
                parts.append(text.getWholeText())
                continue
            }
            guard let child = node as? Element else { continue }
            let tag = child.tagName().lowercased()
            if tag == "script" || tag == "style" { continue }
            stack.append(contentsOf: child.getChildNodes().reversed())
        }
        return parts.joined(separator: separator)
    }
}
