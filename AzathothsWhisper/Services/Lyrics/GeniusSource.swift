import Foundation

// Genius 歌詞來源（lyrics_fetcher.py:1221-1284 等價）。
// 原版走 lyricsgenius 庫 → 失敗才手動爬；Swift 合併為單一管線：
//   search API 取首個 hit 的 url → 抓頁 → GeniusParser（庫路徑口徑）→ 首行標題頭剝除。
// 驗收口徑＝golden `genius_library_clean.json` 的最終文本（Plan R3、ACCEPTANCE G-06/G-09）。
struct GeniusSource: LyricsSource {
    static let unconfiguredTokenPlaceholder = "INSERT_YOUR_GENIUS_ACCESS_TOKEN_HERE"
    static let searchEndpoint = URL(string: "https://api.genius.com/search")!

    let client: any HTTPClient
    let token: String

    init(client: any HTTPClient, token: String) {
        self.client = client
        self.token = token
    }

    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult {
        // py:1224-1225 未配置 token 的錯誤文案 1:1
        guard !token.isEmpty, token != Self.unconfiguredTokenPlaceholder else {
            return .error("Error: Genius Access Token not configured in script.")
        }

        do {
            guard let songURL = try await searchSongURL(for: query) else {
                return .notFound   // py:1281 "Lyrics not found on Genius."
            }
            let page = try await client.get(songURL, headers: [:], timeout: HTTPTimeout.genius)
            guard page.isOK else {
                return .error("Error: HTTP \(page.statusCode) accessing Genius page.")
            }
            guard let parsed = GeniusParser.parse(html: page.body, removeSectionHeaders: true),
                  !parsed.isEmpty
            else {
                // py:1276 頁面拿到但解析不出容器
                return .error("Found lyrics at: \(songURL.absoluteString) (Auto-scrape failed)")
            }
            let cleaned = GeniusParser.stripTitleHeaderLine(parsed)
            return cleaned.isEmpty ? .notFound : .found(cleaned)
        } catch let error as HTTPError {
            return .error("Genius Error: \(Self.describe(error))")
        } catch {
            return .error("Genius Error: \(error.localizedDescription)")
        }
    }

    /// py:1247-1256：GET /search?q="{title} {artist}" with Bearer；取 hits[0].result.url
    private func searchSongURL(for query: LyricsQuery) async throws -> URL? {
        var components = URLComponents(url: Self.searchEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: "\(query.title) \(query.artist)")]
        guard let url = components?.url else { throw HTTPError.invalidURL(Self.searchEndpoint.absoluteString) }

        let response = try await client.get(
            url,
            headers: ["Authorization": "Bearer \(token)"],
            timeout: HTTPTimeout.genius
        )
        guard response.isOK, let data = response.body.data(using: .utf8) else { return nil }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["response"] as? [String: Any],
            let hits = payload["hits"] as? [[String: Any]],
            let first = hits.first,
            let result = first["result"] as? [String: Any],
            let urlString = result["url"] as? String,
            let songURL = URL(string: urlString)
        else { return nil }

        return songURL
    }

    /// 讓錯誤文案穩定可測（避免帶入 localizedDescription 的機器相關內容）
    static func describe(_ error: HTTPError) -> String {
        switch error {
        case .timedOut: return "request timed out"
        case .cancelled: return "cancelled"
        case .transport(let message): return message
        case .invalidURL(let value): return "invalid URL \(value)"
        case .undecodableBody: return "undecodable response body"
        }
    }
}
