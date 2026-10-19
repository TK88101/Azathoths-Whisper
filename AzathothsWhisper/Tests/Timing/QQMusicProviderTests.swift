import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.7 QQ 音樂：musicu.fcg 搜尋 → fcg_query_lyric_new（可能是 JSONP、文字可能帶 HTML 實體）。歌詞為編造句
@Suite("QQMusicProvider")
struct QQMusicProviderTests {
    static let query = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200)

    static func search(interval: Int = 201, singer: String = "Some Band") -> String {
        #"{"code":0,"req_1":{"code":0,"data":{"body":{"song":{"list":[{"mid":"003abc","name":"Lantern Song","interval":\#(interval),"singer":[{"name":"\#(singer)"},{"name":"Guest"}]}]}}}}}"#
    }

    static let lyric = #"MusicJsonCallback({"retcode":0,"lyric":"[ti:Lantern Song]\n[00:10.00]Lanterns over the river\n[00:14.00]Ash in the wind&#39;s path\n[00:20.00]Count the silent bells"})"#

    private func provider(_ client: ScriptedHTTPClient) -> QQMusicProvider {
        QQMusicProvider(gate: .testing(client))
    }

    @Test func aMatchWithAnLRCIsAnAnswer() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, Self.lyric)])
        let outcome = try await provider(client).lookup(Self.query)
        guard case .timed(let lines, let matched) = outcome else { Issue.record("\(outcome)"); return }
        #expect(lines.map(\.start) == [10, 14, 20])
        #expect(lines[1].text == "Ash in the wind's path")
        #expect(matched.artist == "Some Band, Guest")
        let items = URLComponents(url: client.requests[1].url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "songmid", value: "003abc")))
        #expect(client.requests[1].headers["Referer"] == "https://y.qq.com/")
    }

    /// V2：搜尋 body 只帶「歌手 曲名」；沒有 cookie
    @Test func theSearchCarriesOnlyArtistAndTitle() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, Self.lyric)])
        _ = try await provider(client).lookup(Self.query)
        let request = client.requests[0]
        #expect(request.url.absoluteString == "https://u.y.qq.com/cgi-bin/musicu.fcg")
        let body = String(decoding: request.body ?? Data(), as: UTF8.self)
        #expect(body.contains(#""query":"Some Band Lantern Song""#))
        #expect(client.requests.allSatisfy { $0.headers["Cookie"] == nil })
    }

    @Test func anEmptyLyricIsNotFound() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, #"{"retcode":0,"lyric":""}"#)])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.notFound))
    }

    @Test func aLyricWithoutTimeTagsIsPlainOnly() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, #"{"retcode":0,"lyric":"Lanterns over the river\nAsh in the wind"}"#)])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.plainOnly))
    }

    @Test func aWrongSingerIsAMismatch() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search(singer: "Somebody Else"))])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.mismatch))
    }

    @Test func garbageIsUnparsable() async {
        let client = ScriptedHTTPClient([.respond(200, "<html>")])
        await #expect(throws: ProviderFailure.unparsable) { _ = try await provider(client).lookup(Self.query) }
    }
}
