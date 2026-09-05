import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE B-09 / C-10：來源編排順序與三態判定（stub source，不觸網）
@Suite("LyricsService")
struct LyricsServiceTests {
    // 記錄被呼叫的 query，用於斷言「有沒有走 fallback」
    private actor CallLog {
        private(set) var queries: [LyricsQuery] = []
        func record(_ query: LyricsQuery) { queries.append(query) }
    }

    private struct StubSource: LyricsSource {
        let result: LyricsResult
        let log: CallLog
        func fetchLyrics(for query: LyricsQuery) async -> LyricsResult {
            await log.record(query)
            return result
        }
    }

    private func makeService(
        genius: LyricsResult,
        darkLyrics: LyricsResult
    ) -> (LyricsService, CallLog, CallLog) {
        let geniusLog = CallLog()
        let darkLog = CallLog()
        let service = LyricsService(
            genius: StubSource(result: genius, log: geniusLog),
            darkLyrics: StubSource(result: darkLyrics, log: darkLog)
        )
        return (service, geniusLog, darkLog)
    }

    @Test func editorUsesGeniusOnly() async throws {
        let (service, geniusLog, darkLog) = makeService(genius: .found("body"), darkLyrics: .found("dark"))
        let result = await service.fetchForEditor(artist: "Dark Tranquillity", title: "T", album: "Al")
        #expect(result == .found("body"))
        #expect(await geniusLog.queries.count == 1)
        #expect(await geniusLog.queries.first?.artist == "Dark Tranquillity", "artist 必須原樣傳下去")
        #expect(await geniusLog.queries.first?.album == "Al")
        #expect(await darkLog.queries.isEmpty)
    }

    // 偏離原版（已批准）：py:2095 只判 startswith("Error")，而 fetch_genius 的異常路徑回
    // "Genius Error: ..." 不以 Error 開頭 → 原版會把異常訊息當歌詞填進編輯器並顯示 "Lyrics fetched"。
    // Swift 一律降為 notFound，不把錯誤訊息寫進使用者歌詞欄（見 ACCEPTANCE B-11a）。
    @Test func editorMapsNotFoundAndErrorToNotFound() async throws {
        for geniusResult in [LyricsResult.notFound, .error("Genius Error: boom")] {
            let (service, _, darkLog) = makeService(genius: geniusResult, darkLyrics: .found("dark"))
            let result = await service.fetchForEditor(artist: "A", title: "T", album: "Al")
            #expect(result == .notFound)
            #expect(await darkLog.queries.isEmpty, "Editor 永不走 DarkLyrics")
        }
    }

    @Test func editorSanitizesTitleBeforeQuery() async throws {
        let (service, geniusLog, _) = makeService(genius: .found("body"), darkLyrics: .notFound)
        _ = await service.fetchForEditor(artist: "A", title: "Song (Remastered 2009)", album: "Al")
        #expect(await geniusLog.queries.first?.title == "Song")
    }

    @Test func batchReturnsGeniusHitWithoutFallback() async throws {
        let (service, _, darkLog) = makeService(genius: .found("body"), darkLyrics: .found("dark"))
        let result = await service.fetchForBatch(artist: "A", title: "T", album: "Al")
        #expect(result == .found("body"))
        #expect(await darkLog.queries.isEmpty)
    }

    // 用戶 2026-08-10 拍板修正：Genius 回「找不到」時也 fallback。
    // 原版 py:2232 只判 startswith("Error")，導致 DarkLyrics 幾乎從不觸發（見 ACCEPTANCE C-10a）。
    @Test func batchFallsBackWhenGeniusReportsNotFound() async throws {
        let (service, _, darkLog) = makeService(genius: .notFound, darkLyrics: .found("dark"))
        let result = await service.fetchForBatch(artist: "A", title: "T", album: "Al")
        #expect(result == .found("dark"))
        #expect(await darkLog.queries.count == 1)
    }

    @Test func batchFallsBackToDarkLyricsOnGeniusError() async throws {
        let (service, _, darkLog) = makeService(genius: .error("Error: no token"), darkLyrics: .found("dark"))
        let result = await service.fetchForBatch(artist: "A", title: "T", album: "Al")
        #expect(result == .found("dark"))
        #expect(await darkLog.queries.count == 1)
    }

    // 決策 5：fallback 必須帶 album（原版未傳，導致直連專輯頁快路徑失效）
    @Test func batchFallbackCarriesArtistAlbumAndSanitizedTitle() async throws {
        let (service, _, darkLog) = makeService(genius: .error("Error: boom"), darkLyrics: .found("dark"))
        _ = await service.fetchForBatch(artist: "Dark Tranquillity", title: "T (Live)", album: "Damage Done")
        let query = try #require(await darkLog.queries.first)
        #expect(query.artist == "Dark Tranquillity")
        #expect(query.album == "Damage Done")
        #expect(query.title == "T")
    }

    @Test func batchMapsFailedFallbackToNotFound() async throws {
        for darkResult in [LyricsResult.notFound, .error("Error: HTTP 503")] {
            let (service, _, darkLog) = makeService(genius: .error("Error: boom"), darkLyrics: darkResult)
            let result = await service.fetchForBatch(artist: "A", title: "T", album: "Al")
            #expect(result == .notFound)
            #expect(await darkLog.queries.count == 1)
        }
    }
}
