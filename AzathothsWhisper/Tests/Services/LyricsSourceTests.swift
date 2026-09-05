import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE G-09…G-14：兩個 Source 的全鏈路（MockHTTP 餵真實頁面 fixture，零網路）
@Suite("LyricsSources")
struct LyricsSourceTests {
    private let query = LyricsQuery(artist: "Dark Tranquillity", title: "Monochromatic Stains", album: "Damage Done")

    private func searchJSON(url: String) -> String {
        "{\"response\":{\"hits\":[{\"result\":{\"url\":\"\(url)\"}}]}}"
    }

    // MARK: Genius

    @Test func geniusRejectsMissingToken() async {
        for token in ["", GeniusSource.unconfiguredTokenPlaceholder] {
            let client = MockHTTPClient()
            let source = GeniusSource(client: client, token: token)
            let result = await source.fetchLyrics(for: query)
            #expect(result == .error("Error: Genius Access Token not configured in script."))
            #expect(client.requestedURLs.isEmpty, "未配置 token 時不應發任何請求")
        }
    }

    @Test func geniusFullChainMatchesGoldenText() async throws {
        let page = try GoldenFixtures.html("genius_Dark-tranquillity-monochromatic-stains.html")
        let golden = try GoldenFixtures.golden("genius_library_clean.json")
        let expectedRaw = try #require(
            golden.cases.first { $0.page == "genius_Dark-tranquillity-monochromatic-stains.html" }?.expected
        )
        let expected = GeniusParser.stripTitleHeaderLine(expectedRaw)

        let client = MockHTTPClient()
        client.on("api.genius.com/search", respond: HTTPResponse(statusCode: 200, body: searchJSON(url: "https://genius.com/song")))
        client.on("genius.com/song", respond: HTTPResponse(statusCode: 200, body: page))

        let result = await GeniusSource(client: client, token: "fake-token").fetchLyrics(for: query)
        #expect(result == .found(expected))
        #expect(client.requests.first?.headers["Authorization"] == "Bearer fake-token")
    }

    @Test func geniusMapsEmptySearchHitsToNotFound() async {
        let client = MockHTTPClient()
        client.on("api.genius.com/search", respond: HTTPResponse(statusCode: 200, body: "{\"response\":{\"hits\":[]}}"))
        let result = await GeniusSource(client: client, token: "fake-token").fetchLyrics(for: query)
        #expect(result == .notFound)
    }

    @Test func geniusMapsUnparseablePageToAutoScrapeFailed() async {
        let client = MockHTTPClient()
        client.on("api.genius.com/search", respond: HTTPResponse(statusCode: 200, body: searchJSON(url: "https://genius.com/song")))
        client.on("genius.com/song", respond: HTTPResponse(statusCode: 200, body: "<html><body>nothing</body></html>"))
        let result = await GeniusSource(client: client, token: "fake-token").fetchLyrics(for: query)
        #expect(result == .error("Found lyrics at: https://genius.com/song (Auto-scrape failed)"))
    }

    @Test func geniusPropagatesTimeoutAsError() async {
        let client = MockHTTPClient()
        client.on("api.genius.com/search", fail: .timedOut)
        let result = await GeniusSource(client: client, token: "fake-token").fetchLyrics(for: query)
        #expect(result == .error("Genius Error: request timed out"))
    }

    // MARK: DarkLyrics

    @Test func darkLyricsUsesDirectAlbumURLWhenAvailable() async throws {
        let page = try GoldenFixtures.html("darklyrics_darktranquillity_damagedone.html")
        let client = MockHTTPClient()
        client.on("darklyrics.com/lyrics/darktranquillity/damagedone.html", respond: HTTPResponse(statusCode: 200, body: page))

        let result = await DarkLyricsSource(client: client).fetchLyrics(for: query)
        guard case .found(let text) = result else {
            Issue.record("expected found, got \(result)")
            return
        }
        #expect(text.contains("There is this face in the still water"))
        #expect(client.requestedURLs == ["http://www.darklyrics.com/lyrics/darktranquillity/damagedone.html"])
    }

    @Test func darkLyricsFallsBackToSearchWhenDirectMisses() async throws {
        let ddg = try GoldenFixtures.html("ddg_lite_darktranquillity.html")
        let page = try GoldenFixtures.html("darklyrics_darktranquillity_damagedone.html")

        let client = MockHTTPClient()
        client.on("darklyrics.com/lyrics/darktranquillity/wrongalbum.html", respond: HTTPResponse(statusCode: 404, body: ""))
        client.on("lite.duckduckgo.com", respond: HTTPResponse(statusCode: 200, body: ddg))
        client.on("darklyrics.com/lyrics/darktranquillity/damagedone.html", respond: HTTPResponse(statusCode: 200, body: page))

        let miss = LyricsQuery(artist: query.artist, title: query.title, album: "Wrong Album")
        let result = await DarkLyricsSource(client: client).fetchLyrics(for: miss)

        guard case .found = result else {
            Issue.record("expected found, got \(result)")
            return
        }
        #expect(client.requestedURLs.count == 3, "直連 → DDG → 專輯頁")
        #expect(client.requests[1].form["q"] == "site:darklyrics.com \"Dark Tranquillity\" \"Monochromatic Stains\"")
    }

    @Test func darkLyricsSkipsDirectWhenAlbumEmpty() async throws {
        let ddg = try GoldenFixtures.html("ddg_lite_darktranquillity.html")
        let page = try GoldenFixtures.html("darklyrics_darktranquillity_damagedone.html")
        let client = MockHTTPClient()
        client.on("lite.duckduckgo.com", respond: HTTPResponse(statusCode: 200, body: ddg))
        client.on("damagedone.html", respond: HTTPResponse(statusCode: 200, body: page))

        let noAlbum = LyricsQuery(artist: query.artist, title: query.title, album: "")
        _ = await DarkLyricsSource(client: client).fetchLyrics(for: noAlbum)
        #expect(client.requestedURLs.first?.contains("duckduckgo") == true)
    }

    @Test func darkLyricsReportsBlockedSearch() async {
        let client = MockHTTPClient()
        client.setFallback(.response(HTTPResponse(statusCode: 403, body: "")))
        let noAlbum = LyricsQuery(artist: query.artist, title: query.title, album: "")
        let result = await DarkLyricsSource(client: client).fetchLyrics(for: noAlbum)
        #expect(result == .error("Error: Could not search for song (DDG Lite Blocked)."))
    }

    @Test func darkLyricsReportsNotFoundWhenSearchHasNoLink() async {
        let client = MockHTTPClient()
        client.on("lite.duckduckgo.com", respond: HTTPResponse(
            statusCode: 200,
            body: "<html><body><a class='result-link' href='https://example.com/x'>x</a></body></html>"
        ))
        let noAlbum = LyricsQuery(artist: query.artist, title: query.title, album: "")
        let result = await DarkLyricsSource(client: client).fetchLyrics(for: noAlbum)
        #expect(result == .notFound)
    }

    @Test func directURLNormalizationHandlesDiacritics() {
        let url = DarkLyricsSource.directURL(artist: "Mötley Crüe", album: "Dr. Feelgood")
        #expect(url?.absoluteString == "http://www.darklyrics.com/lyrics/mtleycre/drfeelgood.html")
    }

    @Test func formEncodingIsStable() {
        let encoded = URLSessionHTTPClient.encodeForm(["q": "a b&c", "z": "1"])
        #expect(encoded == "q=a%20b%26c&z=1")
    }
}
