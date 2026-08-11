import Foundation
import SwiftSoup

// DarkLyrics 專輯頁 → 單曲歌詞（lyrics_fetcher.py:1371-1432 等價實現）
enum DarkLyricsParser {
    enum Outcome: Equatable {
        case lyrics(String)
        case containerMissing      // "Error: Could not parse lyrics container."
        case titleNotFound         // "Song title not found on album page."
        case parsedEmpty           // "Lyrics parsed empty."
    }

    private static let leadingIndex = try! NSRegularExpression(pattern: #"^\d+\.\s*"#)
    private static let excessiveNewlines = try! NSRegularExpression(pattern: #"\n{3,}"#)

    static func parse(html: String, targetTitle: String) -> Outcome {
        guard let document = try? SwiftSoup.parse(html),
              let container = try? document.select("div.lyrics").first(),
              let headers = try? container.select("h3").array()
        else { return .containerMissing }

        // py:1393 標題正規化：sanitize → 小寫 → 去空格（僅半形空格，對齊 str.replace(' ', '')）
        let target = TitleSanitizer.sanitize(targetTitle).pythonLowercased().replacingOccurrences(of: " ", with: "")

        guard let found = headers.first(where: { header in
            let raw = HTMLText.text(of: header, separator: "").pythonLowercased()
            let withoutIndex = replacing(leadingIndex, in: raw, with: "")
            let normalized = withoutIndex.replacingOccurrences(of: " ", with: "")
            // py:1407 雙向 substring 模糊匹配
            return normalized.contains(target) || target.contains(normalized)
        }) else { return .titleNotFound }

        var parts: [String] = []
        var cursor: Node? = found.nextSibling()
        while let node = cursor {
            if let element = node as? Element {
                let tag = element.tagName().lowercased()
                if tag == "h3" { break }
                if tag == "br" { parts.append("\n") }
            } else if let text = node as? TextNode {
                parts.append(text.getWholeText().pythonStripped())
            }
            cursor = node.nextSibling()
        }

        let joined = parts.joined().pythonStripped()
        let collapsed = replacing(excessiveNewlines, in: joined, with: "\n\n")
        return collapsed.isEmpty ? .parsedEmpty : .lyrics(collapsed)
    }

    private static func replacing(_ regex: NSRegularExpression, in value: String, with template: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }
}
