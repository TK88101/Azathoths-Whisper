import Foundation
import SwiftSoup

// Genius 歌詞頁解析（主口徑＝lyricsgenius 3.7.5 genius.py:167-206；Plan R3、ACCEPTANCE G-06）
enum GeniusParser {
    private static let sectionHeaders = try! NSRegularExpression(pattern: #"(\[.*?\])*"#)
    private static let doubleNewline = try! NSRegularExpression(pattern: #"\n{2}"#)

    static func parse(html: String, removeSectionHeaders: Bool) -> String? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }

        // genius.py:170-173 先移除 LyricsHeader 區塊（貢獻者/翻譯頭）
        if let headers = try? document.select("div[class*=LyricsHeader]").array() {
            for header in headers { try? header.remove() }
        }

        guard let containers = try? document.select("div[data-lyrics-container=true]").array(),
              !containers.isEmpty
        else { return nil }

        var lyrics = ""
        for container in containers {
            let children = container.getChildNodes()
            if children.isEmpty {
                lyrics += "\n"
                continue
            }
            for child in children {
                if let element = child as? Element {
                    if element.tagName().lowercased() == "br" {
                        lyrics += "\n"
                    } else if (try? element.attr("data-exclude-from-selection")) != "true" {
                        lyrics += HTMLText.text(of: element, separator: "\n")
                    }
                } else if let text = child as? TextNode {
                    lyrics += text.getWholeText()
                }
            }
        }

        if removeSectionHeaders {
            lyrics = replacing(sectionHeaders, in: lyrics, with: "")
            lyrics = replacing(doubleNewline, in: lyrics, with: "\n")
        }
        // genius.py:206 只剝除首尾換行（不含空格）
        return trimmingNewlines(lyrics)
    }

    // py:1236-1241：首行 strip 後以 "Lyrics" 結尾則整行剝除，其餘 join 再 strip
    static func stripTitleHeaderLine(_ lyrics: String) -> String {
        var lines = lyrics.components(separatedBy: "\n")
        if let first = lines.first,
           first.pythonStripped().hasSuffix("Lyrics") {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").pythonStripped()
    }

    private static func trimmingNewlines(_ value: String) -> String {
        var result = Substring(value)
        while result.first == "\n" { result = result.dropFirst() }
        while result.last == "\n" { result = result.dropLast() }
        return String(result)
    }

    private static func replacing(_ regex: NSRegularExpression, in value: String, with template: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }
}
