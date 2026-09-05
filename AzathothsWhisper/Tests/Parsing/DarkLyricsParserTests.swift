import Foundation
import Testing

@testable import AzathothsWhisper

// G-03 / G-04 / G-05：DarkLyrics 專輯頁解析逐案對照 Python golden
@Suite("DarkLyricsParser")
struct DarkLyricsParserTests {
    @Test func parseMatchesGolden() throws {
        let file = try GoldenFixtures.golden("darklyrics_parse.json")
        #expect(file.cases.count == 17)
        for c in file.cases {
            let page = try #require(c.page)
            let target = try #require(c.targetTitle)
            let expected = try #require(c.expected)
            let html = try GoldenFixtures.html(page)
            let actual = render(DarkLyricsParser.parse(html: html, targetTitle: target))
            #expect(actual == expected, "page: \(page) / target: \(target)")
        }
    }

    // Outcome → Python 的字串回傳值（錯誤文案 1:1）
    private func render(_ outcome: DarkLyricsParser.Outcome) -> String {
        switch outcome {
        case .lyrics(let text): return text
        case .containerMissing: return "Error: Could not parse lyrics container."
        case .titleNotFound: return "Song title not found on album page."
        case .parsedEmpty: return "Lyrics parsed empty."
        }
    }
}
