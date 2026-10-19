import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.7 YouTube Music：WEB_REMIX 搜尋 → next 找 MPLY 歌詞分頁 → ANDROID_MUSIC browse 取 timedLyricsData。
// fixture 只保留解析用到的欄位，形狀照 2026-10-19 探針實測；歌詞為編造句
@Suite("YouTubeMusicProvider")
struct YouTubeMusicProviderTests {
    static let query = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200)

    static func searchResult(_ songs: [(artist: String, title: String, length: String, videoId: String)]) -> String {
        let items = songs.map { song in
            #"""
            {"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"\#(song.videoId)"},"flexColumns":[
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"\#(song.title)"}]}}},
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"\#(song.artist)"},{"text":" • "},{"text":"Some Album"},{"text":" • "},{"text":"\#(song.length)"}]}}}
            ]}}
            """#
        }.joined(separator: ",")
        return #"{"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[{"musicShelfRenderer":{"contents":[\#(items)]}}]}}}}]}}}"#
    }

    static let next = #"{"contents":{"singleColumnMusicWatchNextResultsRenderer":{"tabbedRenderer":{"watchNextTabbedResultsRenderer":{"tabs":[{"tabRenderer":{"endpoint":{"browseEndpoint":{"browseId":"MPTRt_x"}}}},{"tabRenderer":{"endpoint":{"browseEndpoint":{"browseId":"MPLYt_abc"}}}}]}}}}}"#
    static let nextWithoutLyrics = #"{"contents":{"tabs":[{"tabRenderer":{"endpoint":{"browseEndpoint":{"browseId":"MPTRt_x"}}}}]}}"#

    static func browse(timed: Bool) -> String {
        let lines = [(10_000, "Lanterns over the river"), (14_000, "Ash in the wind"), (20_000, "Count the silent bells")].map { start, text in
            timed ? #"{"lyricLine":"\#(text)","cueRange":{"startTimeMilliseconds":"\#(start)","endTimeMilliseconds":"\#(start + 3000)"}}"#
                  : #"{"lyricLine":"\#(text)"}"#
        }.joined(separator: ",")
        return #"{"contents":{"elementRenderer":{"newElement":{"type":{"componentType":{"model":{"timedLyricsModel":{"lyricsData":{"timedLyricsData":[\#(lines)],"sourceMessage":"Source: LyricFind"}}}}}}}}}"#
    }

    private func provider(_ client: ScriptedHTTPClient) -> YouTubeMusicProvider {
        YouTubeMusicProvider(gate: .testing(client))
    }

    @Test func aMatchingSongWithCueRangesIsAnAnswer() async throws {
        let client = ScriptedHTTPClient([
            .respond(200, Self.searchResult([("Other Band", "Lantern Song", "3:20", "v0"), ("Some Band", "Lantern Song", "3:21", "v1")])),
            .respond(200, Self.next), .respond(200, Self.browse(timed: true)),
        ])
        let outcome = try await provider(client).lookup(Self.query)
        guard case .timed(let lines, let matched) = outcome else { Issue.record("\(outcome)"); return }
        #expect(lines.map(\.start) == [10, 14, 20])
        #expect(matched == MatchedTrack(artist: "Some Band", title: "Lantern Song", duration: 201))
        let nextBody = try #require(client.requests[1].body)
        #expect(String(decoding: nextBody, as: UTF8.self).contains(#""videoId":"v1""#))
        let browseData = try #require(client.requests[2].body)
        let browseBody = String(decoding: browseData, as: UTF8.self)
        #expect(browseBody.contains("ANDROID_MUSIC"))
        #expect(browseBody.contains("MPLYt_abc"))
    }

    /// V2：搜尋請求只帶「歌手 曲名」與固定的客戶端欄位，沒有 cookie
    @Test func theSearchRequestCarriesOnlyArtistAndTitle() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.searchResult([]))])
        _ = try await provider(client).lookup(Self.query)
        let request = try #require(client.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://music.youtube.com/youtubei/v1/search?prettyPrint=false")
        #expect(request.headers["Cookie"] == nil)
        let data = try #require(request.body)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(body.keys) == ["context", "query", "params"])
        #expect(body["query"] as? String == "Some Band Lantern Song")
    }

    @Test func linesWithoutCueRangesArePlainOnly() async throws {
        let client = ScriptedHTTPClient([
            .respond(200, Self.searchResult([("Some Band", "Lantern Song", "3:20", "v1")])),
            .respond(200, Self.next), .respond(200, Self.browse(timed: false)),
        ])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.plainOnly))
    }

    @Test func noLyricsTabIsNotFound() async throws {
        let client = ScriptedHTTPClient([
            .respond(200, Self.searchResult([("Some Band", "Lantern Song", "3:20", "v1")])), .respond(200, Self.nextWithoutLyrics),
        ])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.notFound))
    }

    @Test func candidatesThatDoNotMatchAreAMismatch() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.searchResult([("Some Band", "Lantern Song", "4:30", "v1")]))])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.mismatch))
        #expect(client.requests.count == 1)
    }

    @Test func noResultsIsNotFound() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.searchResult([]))])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.notFound))
    }

    @Test(arguments: [("3:21", 201.0), ("1:02:03", 3723.0), ("abc", nil)])
    func lengthsAreParsed(text: String, seconds: Double?) {
        #expect(YouTubeMusicProvider.seconds(text) == seconds)
    }
}
