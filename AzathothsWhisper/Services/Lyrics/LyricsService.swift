import Foundation

// 歌詞來源編排（lyrics_fetcher.py:2082-2097 fetch_lyrics / 2229-2243 fetch_single_missing 等價）
//
// 保真要點（py 原始判定，非筆誤）：
//   Editor：只用 Genius；非 .found 一律呈現 "Lyrics not found"（py:2095 只判 startswith("Error")，
//           其餘由 JS 層 startsWith("Lyrics not found") 兜住，兩層合成即此語義）。
//   Batch ：Genius .found 直接回；否則 fallback 到 DarkLyrics。
//           偏離原版一處（用戶 2026-08-10 拍板）：py:2232 只判 startswith("Error")，使「Genius 上
//           沒有這首歌」不觸發 fallback——DarkLyrics 實際只在 token 未配置/拋異常時才跑。此處改為
//           .notFound 也 fallback，讓兩級來源真正生效（見 ACCEPTANCE C-10a）。
struct LyricsService: Sendable {
    let genius: LyricsSource
    let darkLyrics: LyricsSource

    init(genius: LyricsSource, darkLyrics: LyricsSource) {
        self.genius = genius
        self.darkLyrics = darkLyrics
    }

    /// Editor 的 Fetch：僅 Genius。
    func fetchForEditor(artist: String, title: String, album: String) async -> LyricsResult {
        let query = LyricsQuery(artist: artist, title: TitleSanitizer.sanitize(title), album: album)
        let result = await genius.fetchLyrics(for: query)
        if case .found = result { return result }
        return .notFound
    }

    /// Batch 的 Fetch Missing：Genius → （僅在 Genius 出錯時）DarkLyrics。
    /// album 依用戶決策 5 傳入，讓 DarkLyrics 直連專輯頁快路徑可用（原版未傳）。
    func fetchForBatch(artist: String, title: String, album: String) async -> LyricsResult {
        let query = LyricsQuery(artist: artist, title: TitleSanitizer.sanitize(title), album: album)
        let geniusResult = await genius.fetchLyrics(for: query)
        if case .found = geniusResult { return geniusResult }

        let fallback = await darkLyrics.fetchLyrics(for: query)
        if case .found = fallback { return fallback }
        return .notFound
    }
}
