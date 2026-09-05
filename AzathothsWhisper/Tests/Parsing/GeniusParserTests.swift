import Foundation
import Testing

@testable import AzathothsWhisper

// G-06 / G-07：Genius 主管線解析與首行標題頭剝除，逐案對照 Python golden
@Suite("GeniusParser")
struct GeniusParserTests {
    @Test func libraryPipelineMatchesGolden() throws {
        let file = try GoldenFixtures.golden("genius_library_clean.json")
        #expect(file.cases.count == 4)
        for c in file.cases {
            let page = try #require(c.page)
            let expected = try #require(c.expected)
            let html = try GoldenFixtures.html(page)
            let actual = GeniusParser.parse(html: html, removeSectionHeaders: true)
            #expect(actual == expected, "page: \(page)")
        }
    }

    @Test func titleHeaderStrippingMatchesGolden() throws {
        let file = try GoldenFixtures.golden("genius_library_firstline.json")
        #expect(file.cases.count == 6)
        for c in file.cases {
            let input = try #require(c.input)
            let expected = try #require(c.expected)
            #expect(GeniusParser.stripTitleHeaderLine(input) == expected, "input: \(input)")
        }
    }
}
