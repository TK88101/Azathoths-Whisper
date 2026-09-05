import Foundation
import SwiftSoup

// DarkLyrics 歌詞來源（lyrics_fetcher.py:1286-1369 等價）。
// 策略 1：有 album → 直連 http://www.darklyrics.com/lyrics/{norm_artist}/{norm_album}.html
// 策略 2：DuckDuckGo Lite 搜 site:darklyrics.com "artist" "title" → 追第一個 /lyrics/ 連結
// 註：該站 443 端口拒絕連線（2026-08-10 實測），故維持 http＋Info.plist ATS 例外。
struct DarkLyricsSource: LyricsSource {
    static let host = "http://www.darklyrics.com"
    static let duckDuckGoLite = URL(string: "https://lite.duckduckgo.com/lite/")!

    let client: any HTTPClient

    init(client: any HTTPClient) {
        self.client = client
    }

    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult {
        do {
            if !query.album.isEmpty, let direct = Self.directURL(artist: query.artist, album: query.album) {
                let response = try await client.get(direct, headers: [:], timeout: HTTPTimeout.darkLyricsDirect)
                if response.isOK {
                    return Self.map(DarkLyricsParser.parse(html: response.body, targetTitle: query.title))
                }
                // 非 200 落到搜尋策略（py:1316-1317）
            }
            return try await searchAndFetch(query)
        } catch let error as HTTPError {
            return .error("Error fetching from DarkLyrics: \(GeniusSource.describe(error))")
        } catch {
            return .error("Error fetching from DarkLyrics: \(error.localizedDescription)")
        }
    }

    /// py:1305-1309 的 URL 構造
    static func directURL(artist: String, album: String) -> URL? {
        let normArtist = TitleSanitizer.normalizeForURL(artist)
        let normAlbum = TitleSanitizer.normalizeForURL(album)
        guard !normArtist.isEmpty, !normAlbum.isEmpty else { return nil }
        return URL(string: "\(host)/lyrics/\(normArtist)/\(normAlbum).html")
    }

    /// py:1321-1364：DDG Lite POST（非 200 轉 GET）→ 找 result-link → 抓專輯頁
    private func searchAndFetch(_ query: LyricsQuery) async throws -> LyricsResult {
        let searchQuery = "site:darklyrics.com \"\(query.artist)\" \"\(query.title)\""
        let headers = ["Referer": "https://lite.duckduckgo.com/"]

        var response = try await client.post(
            Self.duckDuckGoLite,
            form: ["q": searchQuery],
            headers: headers,
            timeout: HTTPTimeout.duckDuckGo
        )
        if !response.isOK {
            var components = URLComponents(url: Self.duckDuckGoLite, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "q", value: searchQuery)]
            guard let getURL = components?.url else {
                return .error("Error: Could not search for song (DDG Lite Blocked).")
            }
            response = try await client.get(getURL, headers: [:], timeout: HTTPTimeout.duckDuckGo)
        }
        guard response.isOK else {
            return .error("Error: Could not search for song (DDG Lite Blocked).")   // py:1339
        }

        guard let albumURL = Self.firstAlbumLink(in: response.body) else {
            return .notFound   // py:1357 "Lyrics not found on DarkLyrics."
        }

        let page = try await client.get(albumURL, headers: [:], timeout: HTTPTimeout.darkLyricsPage)
        guard page.isOK else {
            return .error("Error: HTTP \(page.statusCode) accessing Lyrics page.")  // py:1362
        }
        return Self.map(DarkLyricsParser.parse(html: page.body, targetTitle: query.title))
    }

    /// py:1345-1354：a.result-link 中第一個含 darklyrics.com/lyrics/ 的 href，去掉 # 錨點
    static func firstAlbumLink(in html: String) -> URL? {
        guard let document = try? SwiftSoup.parse(html),
              let links = try? document.select("a.result-link").array()
        else { return nil }

        for link in links {
            guard let href = try? link.attr("href"), href.contains("darklyrics.com/lyrics/") else { continue }
            let withoutAnchor = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            return URL(string: String(withoutAnchor))
        }
        return nil
    }

    /// 解析結果 → 三態。原版把 "Song title not found on album page." 等字串當歌詞回傳
    /// （py:2240 只擋 "Lyrics not found" 子串），此處歸為 notFound —— 用戶可見結果相同
    /// （UI 都顯示未找到），但不會把錯誤訊息寫進歌詞欄。
    static func map(_ outcome: DarkLyricsParser.Outcome) -> LyricsResult {
        switch outcome {
        case .lyrics(let text): return .found(text)
        case .containerMissing: return .error("Error: Could not parse lyrics container.")
        case .titleNotFound, .parsedEmpty: return .notFound
        }
    }
}
