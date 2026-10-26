import Foundation
import Testing
@testable import RemoteProtocol

// S3 曲庫訊息（sprint-3-detail.md §4.3、§4.4）。測試字串一律自編，不用真實曲名。

struct CatalogRequestValidationTests {
    @Test(arguments: [(nil as String?, 1, true), (nil, 200, true), (nil, 0, false), (nil, 201, false), ("not-a-cursor", 10, false)])
    func pageRequestLimitsAndCursor(cursor: String?, limit: Int, valid: Bool) {
        #expect(CatalogPageRequest(cursor: cursor, limit: limit).isValid == valid)
    }

    @Test func pageRequestAcceptsEncodedCursor() {
        let cursor = CatalogCursor(version: "0123456789abcdef", offset: 200).encoded()
        #expect(CatalogPageRequest(cursor: cursor, limit: 200).isValid)
    }

    @Test(arguments: [("blue", 1, true), ("blue", 50, true), ("blue", 0, false), ("blue", 51, false),
                      ("", 10, false), ("   ", 10, false), (String(repeating: "a", count: 64), 10, true),
                      (String(repeating: "a", count: 65), 10, false)])
    func searchRequestLimits(query: String, limit: Int, valid: Bool) {
        #expect(CatalogSearchRequest(query: query, limit: limit).isValid == valid)
    }

    @Test func searchQueryLengthCountsCharactersNotBytes() {
        // 64 個多位元組字元仍合法
        #expect(CatalogSearchRequest(query: String(repeating: "音", count: 64), limit: 1).isValid)
    }

    @Test(arguments: [("0123456789abcdef", "fedcba9876543210", true), ("0123456789ABCDEF", "fedcba9876543210", false),
                      ("0123456789abcde", "fedcba9876543210", false), ("0123456789abcdeg", "fedcba9876543210", false),
                      ("0123456789abcdef", "short", false)])
    func artworkRequestIDsMustBeLowercaseHex16(albumID: String, token: String, valid: Bool) {
        #expect(ArtworkRequest(albumID: albumID, size: .spine, artworkToken: token).isValid == valid)
    }

    @Test func artworkSizeIsClosedEnum() throws {
        let json = Data(#"{"albumID":"0123456789abcdef","size":"huge","artworkToken":"fedcba9876543210"}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ArtworkRequest.self, from: json) }
    }

    @Test func missingFieldFailsToDecode() {
        let json = Data(#"{"cursor":null}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CatalogPageRequest.self, from: json) }
    }
}

struct CatalogCursorTests {
    @Test func roundTrips() {
        let cursor = CatalogCursor(version: "0123456789abcdef", offset: 1234)
        #expect(CatalogCursor.decode(cursor.encoded()) == cursor)
    }

    @Test func encodingIsURLSafeWithoutPadding() {
        let encoded = CatalogCursor(version: "0123456789abcdef", offset: 7).encoded()
        #expect(!encoded.contains("+") && !encoded.contains("/") && !encoded.contains("="))
    }

    @Test(arguments: ["", "!!!", "MDEyMzQ1Njc4OWFiY2RlZg", // 只有版本、沒有冒號
                      CatalogCursor.encodeRaw("0123456789abcdef:-1"), CatalogCursor.encodeRaw("0123456789abcdef:abc"),
                      CatalogCursor.encodeRaw("0123456789ABCDEF:1"), CatalogCursor.encodeRaw("0123:1"),
                      CatalogCursor.encodeRaw("0123456789abcdef:99999999999"), CatalogCursor.encodeRaw("0123456789abcdef:1:2")])
    func rejectsTamperedCursor(raw: String) {
        #expect(CatalogCursor.decode(raw) == nil)
    }
}

struct TextFoldTests {
    @Test(arguments: [("Blue Moon", "blue moon"), ("ＢＬＵＥ", "blue"), ("Café", "cafe"), ("ﬁre", "fire"),
                      ("ｶﾞｲﾄﾞ", "がいど"), ("ガイド", "がいど")])
    func foldsCaseWidthDiacriticsAndCompatibility(input: String, expected: String) {
        #expect(TextFold.fold(input) == expected)
    }

    /// 實測（2026-10-17）：Foundation 的 diacriticInsensitive 不去日文濁點／半濁點，ば・ぱ・は 仍可區分
    @Test func japaneseVoicingMarksAreKept() {
        #expect(TextFold.fold("ば") != TextFold.fold("は"))
        #expect(TextFold.fold("ぱ") != TextFold.fold("は"))
    }

    @Test func katakanaAndHiraganaFoldTogether() {
        #expect(TextFold.fold("カタカナ") == TextFold.fold("かたかな"))
    }
}

struct TextClampTests {
    @Test func shortTextUnchanged() {
        #expect(TextClamp.clamp("Night Ride") == "Night Ride")
    }

    @Test func clampsToMaxGraphemes() {
        let clamped = TextClamp.clamp(String(repeating: "a", count: 500))
        #expect(clamped.count == CatalogLimits.maxTextCharacters)
    }

    @Test func clampsToMaxUTF8BytesWithoutSplittingGraphemes() {
        // 每個 grapheme 由 7 個碼點組成（家庭 emoji），200 個遠超 600 B
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let clamped = TextClamp.clamp(String(repeating: family, count: 200))
        #expect(clamped.utf8.count <= CatalogLimits.maxTextUTF8Bytes)
        #expect(clamped.allSatisfy { String($0) == family })
        #expect(!clamped.isEmpty)
    }
}

struct CatalogMessageRoundTripTests {
    @Test func pageResponseRoundTrips() throws {
        let album = AlbumSummary(id: "0123456789abcdef", title: "Test Album", artist: "Test Artist", trackCount: 9,
                                 artworkToken: "fedcba9876543210")
        let response = CatalogPageResponse(version: "00000000000000aa", total: 1, albums: [album], nextCursor: nil)
        let decoded = try JSONDecoder().decode(CatalogPageResponse.self, from: JSONEncoder().encode(response))
        #expect(decoded == response)
    }

    @Test func artworkResponseCarriesOutcomeAndToken() throws {
        let response = ArtworkResponse(albumID: "0123456789abcdef", size: .spine, outcome: .stale,
                                       artworkToken: "fedcba9876543210", jpeg: nil)
        let decoded = try JSONDecoder().decode(ArtworkResponse.self, from: JSONEncoder().encode(response))
        #expect(decoded == response)
        #expect(decoded.isValid)
    }

    @Test func artworkResponseImageMustCarryJPEG() {
        #expect(!ArtworkResponse(albumID: "0123456789abcdef", size: .spine, outcome: .image, artworkToken: nil, jpeg: nil).isValid)
        #expect(!ArtworkResponse(albumID: "0123456789abcdef", size: .spine, outcome: .none, artworkToken: nil,
                                 jpeg: Data([0xFF])).isValid)
    }

    @Test func catalogChangedEventRoundTrips() throws {
        let event = CatalogChangedEvent(version: "00000000000000bb")
        #expect(try JSONDecoder().decode(CatalogChangedEvent.self, from: JSONEncoder().encode(event)) == event)
    }
}
