import Foundation

// 歌詞查詢與三態結果。
// 三態取代 Python 的字串前綴判定（"Error..." / "Lyrics not found..."），
// 但最終用戶可見行為 1:1 —— 映射規則由各 Source 實現負責（M3）。
struct LyricsQuery: Equatable, Sendable {
    let artist: String
    let title: String   // 已經過 TitleSanitizer.sanitize
    let album: String   // 可為空字串（Editor 路徑不帶專輯）
}

enum LyricsResult: Equatable, Sendable {
    case found(String)
    case notFound
    case error(String)
}

protocol LyricsSource: Sendable {
    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult
}
