import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.7 Deezer：公開搜尋（一般關鍵字；進階語法 2026-10-19 探針回空）→ 匿名 JWT（只放記憶體）→ GraphQL synchronizedLines
@Suite("DeezerProvider")
struct DeezerProviderTests {
    static let query = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200)
    static let search = #"{"data":[{"id":11,"title":"Lantern Song","duration":199,"artist":{"name":"Some Band"}}],"total":1}"#
    static let jwt = #"{"jwt":"header.payload.signature"}"#
    static let synced = #"{"data":{"track":{"lyrics":{"text":"x","synchronizedLines":[{"milliseconds":10000,"line":"Lanterns over the river"},{"milliseconds":14000,"line":"Ash in the wind"},{"milliseconds":20000,"line":"Count the silent bells"}]}}}}"#
    static let plain = #"{"data":{"track":{"lyrics":{"text":"Lanterns over the river","synchronizedLines":null}}}}"#

    private func provider(_ client: ScriptedHTTPClient) -> DeezerProvider {
        DeezerProvider(gate: .testing(client))
    }

    @Test func aMatchWithSynchronizedLinesIsAnAnswer() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search), .respond(200, Self.jwt), .respond(200, Self.synced)])
        let outcome = try await provider(client).lookup(Self.query)
        guard case .timed(let lines, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(lines.map(\.start) == [10, 14, 20])
        let graph = client.requests[2]
        #expect(graph.headers["Authorization"] == "Bearer header.payload.signature")
        #expect(String(decoding: graph.body ?? Data(), as: UTF8.self).contains(#""trackId":"11""#))
    }

    /// V2：搜尋只帶「歌手 曲名」；匿名通行證請求不帶任何使用者資料；沒有 cookie
    @Test func requestsCarryNothingButArtistAndTitle() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search), .respond(200, Self.jwt), .respond(200, Self.synced)])
        _ = try await provider(client).lookup(Self.query)
        let search = client.requests[0]
        let items = URLComponents(url: search.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(search.url.host == "api.deezer.com")
        #expect(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) == ["q": "Some Band Lantern Song", "limit": "10"])
        #expect(client.requests[1].url.host == "auth.deezer.com")
        #expect(client.requests[1].body == nil)
        #expect(client.requests.allSatisfy { $0.headers["Cookie"] == nil })
    }

    @Test func theAnonymousTokenIsReusedAcrossLookups() async throws {
        let client = ScriptedHTTPClient([
            .respond(200, Self.search), .respond(200, Self.jwt), .respond(200, Self.synced),
            .respond(200, Self.search.replacingOccurrences(of: "Lantern Song", with: "Other Song")), .respond(200, Self.synced),
        ])
        let provider = provider(client)
        _ = try await provider.lookup(Self.query)
        _ = try await provider.lookup(TimingQuery(artist: "Some Band", title: "Other Song", duration: 200))
        #expect(client.requests.filter { $0.url.host == "auth.deezer.com" }.count == 1)
    }

    @Test func anExpiredTokenIsRefreshedOnce() async throws {
        let client = ScriptedHTTPClient([
            .respond(200, Self.search), .respond(200, Self.jwt), .respond(401, "{}"), .respond(200, Self.jwt), .respond(200, Self.synced),
        ])
        guard case .timed = try await provider(client).lookup(Self.query) else { Issue.record("expected timed"); return }
        #expect(client.requests.filter { $0.url.host == "auth.deezer.com" }.count == 2)
    }

    @Test func textWithoutSynchronizedLinesIsPlainOnly() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search), .respond(200, Self.jwt), .respond(200, Self.plain)])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.plainOnly))
    }

    @Test func aWrongDurationIsAMismatchAndSkipsTheToken() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search.replacingOccurrences(of: "199", with: "250"))])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.mismatch))
        #expect(client.requests.count == 1)
    }

    @Test func anErrorPayloadFromSearchIsUnparsable() async {
        let client = ScriptedHTTPClient([.respond(200, #"{"error":{"type":"Exception","code":4}}"#)])
        await #expect(throws: ProviderFailure.unparsable) { _ = try await provider(client).lookup(Self.query) }
    }
}
