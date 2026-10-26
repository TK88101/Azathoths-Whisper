import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// S6 #6-1 g 版 T7（s6-61-g-perf-wear.md §5.7）：搜尋零結果提示——有效 query、搜尋已回應、0 筆才顯示；未回應（debounce 中）與失敗不顯示
struct NoResultsTests {
    static let album = AlbumSummary(id: "a", title: "A", artist: "B", trackCount: 1, artworkToken: nil)

    @Test func showsOnlyWhenSearchRespondedWithNothing() {
        #expect(LibraryPresentation.searchStatus(query: "qqq", searchResults: [], resultsQuery: "qqq") == .noResults)
        #expect(LibraryPresentation.searchStatus(query: " qqq ", searchResults: [], resultsQuery: "qqq") == .noResults)
        #expect(LibraryPresentation.searchStatus(query: "qqq", searchResults: nil, resultsQuery: nil) == .none)
        #expect(LibraryPresentation.searchStatus(query: "qqq", searchResults: [Self.album], resultsQuery: "qqq") == .none)
        #expect(LibraryPresentation.searchStatus(query: "   ", searchResults: [], resultsQuery: "   ") == .none)
        #expect(LibraryPresentation.searchStatus(query: "", searchResults: nil, resultsQuery: nil) == .none)
    }

    /// Codex 確認輪 P2：上一次 0 筆、改了字還在等新結果＝不顯示（結果不屬於目前的字）
    @Test func staleEmptyResultsForOldQueryDoNotShow() {
        #expect(LibraryPresentation.searchStatus(query: "qqqz", searchResults: [], resultsQuery: "qqq") == .none)
    }

    @Test func messageFormatsQuery() {
        #expect(LibraryPresentation.noResultsMessage(query: "  qqq ").contains("qqq"))
    }
}
