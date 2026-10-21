import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.7 LRCLIB：先 /api/get、404 或沒有時間軸才 /api/search；帶 User-Agent；對外只送三欄。
// 候選排序計劃 §3.1：廢除「唯一」規則，帶時間軸的候選全部列出（排序在 resolver）。歌詞全為編造句
@Suite("LRCLIBProvider")
struct LRCLIBProviderTests {
    static let query = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200.4)
    static let synced = "[00:10.00] Lanterns over the river\\n[00:14.00] Ash in the wind\\n[00:20.00] Count the silent bells"

    static func record(id: Int = 1, artist: String = "Some Band", title: String = "Lantern Song", duration: Double = 200, synced: String? = Self.synced) -> String {
        let syncedJSON = synced.map { "\"\($0)\"" } ?? "null"
        return #"{"id":\#(id),"trackName":"\#(title)","artistName":"\#(artist)","albumName":"X","duration":\#(duration),"instrumental":false,"plainLyrics":"p","syncedLyrics":\#(syncedJSON)}"#
    }

    private func provider(_ client: ScriptedHTTPClient) -> LRCLIBProvider {
        LRCLIBProvider(gate: .testing(client))
    }

    @Test func anExactGetWithSyncedLyricsIsAnAnswer() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.record())])
        let outcome = try await provider(client).lookupFirstRanked(Self.query)
        guard case .timed(let lines, let matched) = outcome else { Issue.record("\(outcome)"); return }
        #expect(lines.map(\.start) == [10, 14, 20])
        #expect(matched == MatchedTrack(artist: "Some Band", title: "Lantern Song", duration: 200))
        #expect(client.requests.count == 1)
    }

    /// V2：完整請求只有三欄、帶 User-Agent、沒有 cookie
    @Test func theRequestCarriesOnlyArtistTitleAndDurationWithAUserAgent() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.record())])
        _ = try await provider(client).lookupFirstRanked(Self.query)
        let request = try #require(client.requests.first)
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(request.url.host == "lrclib.net")
        #expect(request.url.path == "/api/get")
        #expect(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) == ["artist_name": "Some Band", "track_name": "Lantern Song", "duration": "200"])
        #expect(request.headers["User-Agent"] == "AzathothsWhisper/\(AppInfo.version) (https://github.com/TK88101/Azathoths-Whisper)")
        #expect(request.headers["Cookie"] == nil)
        #expect(request.body == nil)
    }

    @Test func a404FallsBackToSearchAndUsesTheSingleMatchingCandidate() async throws {
        let search = "[\(Self.record(id: 9, artist: "Other", title: "Else")),\(Self.record())]"
        let client = ScriptedHTTPClient([.respond(404, "{}"), .respond(200, search)])
        let outcome = try await provider(client).lookupFirstRanked(Self.query)
        guard case .timed = outcome else { Issue.record("\(outcome)"); return }
        #expect(client.requests.map(\.url.path) == ["/api/get", "/api/search"])
    }

    @Test func twoMatchingSyncedCandidatesAreBothListedAndEachCarriesItsOwnTiming() async throws {
        let later = "[00:11.00] Lanterns over the river\\n[00:15.00] Ash in the wind\\n[00:21.00] Count the silent bells"
        let search = "[\(Self.record(id: 1)),\(Self.record(id: 2, duration: 201, synced: later))]"
        let client = ScriptedHTTPClient([.respond(404, "{}"), .respond(200, search)])
        let provider = provider(client)
        let candidates = try await provider.candidates(for: Self.query)
        #expect(candidates.map(\.id) == ["1", "2"])
        guard case .timed(let lines, _) = try await provider.timing(of: candidates[1], for: Self.query) else { Issue.record("expected timed"); return }
        #expect(lines.map(\.start) == [11, 15, 21])
        #expect(client.requests.count == 2)   // 取時間軸不再發請求
    }

    @Test func recordsWithoutSyncedLyricsAreNotCandidates() async throws {
        let search = "[\(Self.record(id: 1, synced: nil)),\(Self.record(id: 2))]"
        let client = ScriptedHTTPClient([.respond(404, "{}"), .respond(200, search)])
        #expect(try await provider(client).candidates(for: Self.query).map(\.id) == ["2"])
    }

    @Test func anExactRecordWithoutSyncedLyricsFallsBackToSearch() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.record(synced: nil)), .respond(200, "[\(Self.record(id: 7))]")])
        let candidates = try await provider(client).candidates(for: Self.query)
        #expect(candidates.map(\.id) == ["7"])
        #expect(client.requests.map(\.url.path) == ["/api/get", "/api/search"])
    }

    @Test func plainLyricsEverywhereIsNotFound() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.record(synced: nil)), .respond(200, "[\(Self.record(synced: nil))]")])
        #expect(try await provider(client).lookupFirstRanked(Self.query) == .noTiming(.notFound))
    }

    @Test func aWrongSongIsAMismatch() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.record(title: "Different Song"))])
        #expect(try await provider(client).lookupFirstRanked(Self.query) == .noTiming(.mismatch))
    }

    @Test func nothingAnywhereIsNotFound() async throws {
        let client = ScriptedHTTPClient([.respond(404, "{}"), .respond(200, "[]")])
        #expect(try await provider(client).lookupFirstRanked(Self.query) == .noTiming(.notFound))
    }

    @Test func garbageIsUnparsable() async {
        let client = ScriptedHTTPClient([.respond(200, "<html>")])
        await #expect(throws: ProviderFailure.unparsable) { _ = try await provider(client).lookupFirstRanked(Self.query) }
    }
}
