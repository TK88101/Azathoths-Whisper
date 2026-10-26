import Foundation
import Testing
@testable import RemoteProtocol

// T2：完整外層訊息的實際編碼位元組 ≤ responseBudgetBytes（sprint-3-detail.md §4.3；Codex 最擔心的一點）。
// 對抗性輸入：多碼點 grapheme、需 JSON 跳脫的字元（控制字元跳脫後 6 倍）、最壞長度。

struct ResponseBudgetTests {
    private static let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"

    private static func worstAlbums(_ count: Int, text: String) -> [AlbumSummary] {
        (0..<count).map { i in
            AlbumSummary(id: String(format: "%016llx", UInt64(i)), title: TextClamp.clamp(text), artist: TextClamp.clamp(text),
                         trackCount: Int.max, artworkToken: "ffffffffffffffff")
        }
    }

    private static let adversarialTexts = [
        String(repeating: family, count: 300),
        String(repeating: "\u{01}", count: 1000),        // 控制字元：JSON 跳脫成 \u0001
        String(repeating: "\"\\", count: 500),           // 引號與反斜線
        String(repeating: "音", count: 1000),
        String(repeating: "e\u{301}\u{302}\u{303}", count: 400), // 一個 grapheme 多個組合符號
    ]

    private func pageMessage(_ albums: ArraySlice<AlbumSummary>) -> Data {
        let cursor = CatalogCursor(version: "ffffffffffffffff", offset: CatalogCursor.maxOffset).encoded()
        let body = CatalogPageResponse(version: "ffffffffffffffff", total: Int.max, albums: Array(albums), nextCursor: cursor)
        return Envelope.encode(.catalogPage, body, id: UUID())
    }

    @Test(arguments: adversarialTexts)
    func pageFitsBudgetAndHasAtLeastOneAlbum(text: String) {
        let albums = Self.worstAlbums(CatalogLimits.maxPageSize, text: text)
        let count = ResponseBudget.largestFittingCount(upTo: albums.count) { pageMessage(albums.prefix($0)) }
        #expect(count >= 1)
        #expect(pageMessage(albums.prefix(count)).count <= TransportLimits.responseBudgetBytes)
        if count < albums.count {
            #expect(pageMessage(albums.prefix(count + 1)).count > TransportLimits.responseBudgetBytes)
        }
    }

    @Test(arguments: adversarialTexts)
    func searchFitsBudget(text: String) {
        let albums = Self.worstAlbums(CatalogLimits.maxSearchResults, text: text)
        let message = { (n: Int) in Envelope.encode(.catalogSearch, CatalogSearchResponse(version: "ffffffffffffffff",
                                                                                          albums: Array(albums.prefix(n))), id: UUID()) }
        let count = ResponseBudget.largestFittingCount(upTo: albums.count, encode: message)
        #expect(count >= 1)
        #expect(message(count).count <= TransportLimits.responseBudgetBytes)
    }

    @Test func smallListFitsEntirely() {
        let albums = Self.worstAlbums(5, text: "Short Name")
        #expect(ResponseBudget.largestFittingCount(upTo: 5) { pageMessage(albums.prefix($0)) } == 5)
    }

    @Test func zeroItemsWhenEvenEmptyDoesNotFit() {
        #expect(ResponseBudget.largestFittingCount(upTo: 3, budget: 10) { _ in Data(count: 11) } == 0)
    }

    @Test func budgetLeavesRoomUnderTransportLimit() {
        #expect(TransportLimits.responseBudgetBytes < TransportLimits.maxMessageBytes)
    }

    /// spine 上限：base64 後加 JSON 外殼仍在預算內
    @Test func spineMaxJPEGFitsBudgetAfterBase64() {
        let body = ArtworkResponse(albumID: "ffffffffffffffff", size: .spine, outcome: .image, artworkToken: "ffffffffffffffff",
                                   jpeg: Data(repeating: 0xFF, count: CatalogLimits.spineMaxJPEGBytes))
        #expect(Envelope.encode(.artworkGet, body, id: UUID()).count <= TransportLimits.responseBudgetBytes)
    }
}

struct EnvelopeEncodingTests {
    @Test func encodedEnvelopeDecodesAsHeader() throws {
        let id = UUID()
        let data = Envelope.encode(.catalogPage, CatalogChangedEvent(version: "0123456789abcdef"), id: id, seq: 3,
                                   nonce: Data(count: TransportLimits.nonceBytes))
        let header = try EnvelopeHeader.decode(data).get()
        #expect(header.id == id && header.kind == .catalogPage && header.seq == 3)
    }
}
