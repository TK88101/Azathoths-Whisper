import Foundation
import Testing

@testable import AzathothsWhisper

// G-01 / G-02：sanitize_title 與 DarkLyrics URL normalize，逐案對照 Python golden
@Suite("TitleSanitizer")
struct TitleSanitizerTests {
    @Test func sanitizeMatchesGolden() throws {
        let file = try GoldenFixtures.golden("sanitize_title.json")
        #expect(file.cases.count == 22)
        for c in file.cases {
            let input = try #require(c.input)
            let expected = try #require(c.expected)
            #expect(TitleSanitizer.sanitize(input) == expected, "input: \(input)")
        }
    }

    @Test func normalizeMatchesGolden() throws {
        let file = try GoldenFixtures.golden("darklyrics_normalize.json")
        #expect(file.cases.count == 12)
        for c in file.cases {
            let input = try #require(c.input)
            let expected = try #require(c.expected)
            #expect(TitleSanitizer.normalizeForURL(input) == expected, "input: \(input)")
        }
    }
}
