import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥b 計劃 §4.2、§4.5（R1-5、R2-4、R2-5）：MB 請求的形狀、逸出、預算與失敗。回應全為自編 JSON
@Suite("MusicBrainz client")
struct MusicBrainzClientTests {
    private func client(_ steps: [ScriptedHTTPClient.Step], clock: FakeTimingClock = FakeTimingClock()) -> (MusicBrainzClient, ScriptedHTTPClient) {
        let http = ScriptedHTTPClient(steps)
        let gate = SourceGate(policy: MusicBrainzClient.policy, client: http, clock: clock, sleeper: clock, jitter: { 0 }, wallNow: { Date(timeIntervalSince1970: 1_800_000_000) })
        return (MusicBrainzClient(gate: gate), http)
    }

    private static func search(_ artists: [(String, String, [String])]) -> String {
        let items = artists.map { id, name, aliases in
            "{\"id\":\"\(id)\",\"name\":\"\(name)\",\"score\":100,\"aliases\":[\(aliases.map { "{\"name\":\"\($0)\"}" }.joined(separator: ","))]}"
        }
        return "{\"artists\":[\(items.joined(separator: ","))]}"
    }

    private static func lookup(genres: [(String, Int)], groups: [String], idPrefix: String = "rg") -> String {
        let g = genres.map { "{\"name\":\"\($0.0)\",\"count\":\($0.1)}" }.joined(separator: ",")
        let r = groups.enumerated().map { "{\"id\":\"\(idPrefix)\($0.offset)\",\"title\":\"\($0.element)\"}" }.joined(separator: ",")
        return "{\"genres\":[\(g)],\"release-groups\":[\(r)]}"
    }

    private static func browse(_ groups: [String], total: Int, idPrefix: String = "page") -> String {
        let r = groups.enumerated().map { "{\"id\":\"\(idPrefix)\($0.offset)\",\"title\":\"\($0.element)\"}" }.joined(separator: ",")
        return "{\"release-groups\":[\(r)],\"release-group-count\":\(total)}"
    }

    private func query(_ request: HTTPRequest) -> [String: String] {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    @Test func theSearchRequestNamesTheAppAndAsksForJSON() async throws {
        let (mb, http) = client([.respond(200, Self.search([]))])
        _ = try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"])
        let request = try #require(http.requests.first)
        #expect(request.url.host == "musicbrainz.org" && request.url.path == "/ws/2/artist")
        #expect(query(request) == ["query": "artist:\"Velvet Lanterns\"", "limit": "25", "fmt": "json"])
        #expect(request.headers["User-Agent"] == "AzathothsWhisper/\(AppInfo.version) ( \(AppInfo.repositoryURL.absoluteString) )")
        #expect(request.headers["Accept"] == "application/json")
    }

    /// R2-4：Lucene phrase 逸出（`"`、`\`）與 URL 編碼分開；`+` 不得被伺服器讀成空白
    @Test func quotesBackslashesAndPlusSignsSurviveTheTrip() async throws {
        let (mb, http) = client([.respond(200, Self.search([]))])
        _ = try await mb.identify(artist: #"Say "Hi" \ Now+Then (Live: Part-1)"#, albums: [])
        let request = try #require(http.requests.first)
        #expect(query(request)["query"] == #"artist:"Say \"Hi\" \\ Now+Then (Live: Part-1)""#)
        #expect(request.url.absoluteString.contains("%2B") && !request.url.query!.contains("+"))
    }

    @Test func aVerifiedArtistComesBackWithItsGenres() async throws {
        let (mb, http) = client([
            .respond(200, Self.search([("mb-1", "Velvet Lanterns", [])])),
            .respond(200, Self.lookup(genres: [("black metal", 3), ("doom metal", 1)], groups: ["Night Ferry", "Paper Harbour"])),
        ])
        let lookup = try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry", "Paper Harbour"])
        #expect(lookup == .verified(id: "mb-1", matchedReleaseGroups: ["rg0", "rg1"], genres: [.init(name: "black metal", count: 3), .init(name: "doom metal", count: 1)]))
        let second = try #require(http.requests.last)
        #expect(second.url.path == "/ws/2/artist/mb-1" && query(second)["inc"] == "genres+release-groups")
    }

    @Test func noNamesakeStopsAfterTheSearch() async throws {
        let (mb, http) = client([.respond(200, Self.search([("mb-1", "Velvet Lantern Co", [])]))])
        #expect(try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"]) == .unresolved(.notFound))
        #expect(http.requests.count == 1)
    }

    @Test func moreThanEightNamesakesStopAfterTheSearch() async throws {
        let many = (0..<9).map { ("mb-\($0)", "Velvet Lanterns", [String]()) }
        let (mb, http) = client([.respond(200, Self.search(many))])
        #expect(try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"]) == .unresolved(.ambiguous))
        #expect(http.requests.count == 1)
    }

    @Test func aFullFirstPageIsBrowsedUntilAnAlbumMatches() async throws {
        let filler = (0..<25).map { "Filler \($0)" }
        let (mb, http) = client([
            .respond(200, Self.search([("mb-1", "Velvet Lanterns", [])])),
            .respond(200, Self.lookup(genres: [("gothic rock", 2)], groups: filler)),
            .respond(200, Self.browse(filler + ["Night Ferry"], total: 26)),
        ])
        let lookup = try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"])
        #expect(lookup == .verified(id: "mb-1", matchedReleaseGroups: ["page25"], genres: [.init(name: "gothic rock", count: 2)]))
        let browse = try #require(http.requests.last)
        #expect(browse.url.path == "/ws/2/release-group" && query(browse)["artist"] == "mb-1" && query(browse)["limit"] == "100" && query(browse)["offset"] == "0")
    }

    /// R2-5：每位歌手最多 12 個請求，用完還沒判定＝ambiguous
    @Test func theRequestBudgetCapsOneArtist() async throws {
        let filler = (0..<25).map { "Filler \($0)" }
        let namesakes = (0..<8).map { ("mb-\($0)", "Velvet Lanterns", [String]()) }
        let steps: [ScriptedHTTPClient.Step] = [.respond(200, Self.search(namesakes))]
            + Array(repeating: .respond(200, Self.lookup(genres: [], groups: filler)), count: 8)
            + Array(repeating: .respond(200, Self.browse(filler + filler + filler + filler, total: 400)), count: 20)
        let (mb, http) = client(steps)
        #expect(try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"]) == .unresolved(.ambiguous))
        #expect(http.requests.count == MusicBrainzClient.requestBudget)
    }

    @Test func requestsAreSpacedAboveOneSecond() async throws {
        let clock = FakeTimingClock()
        let (mb, _) = client([.respond(200, Self.search([("mb-1", "Velvet Lanterns", [])])), .respond(200, Self.lookup(genres: [], groups: []))], clock: clock)
        _ = try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"])
        #expect(clock.sleeps.count == 1 && abs(clock.sleeps[0] - MusicBrainzClient.policy.minimumInterval) < 0.01, "\(clock.sleeps)")
        #expect(MusicBrainzClient.policy.minimumInterval > 1)
    }

    @Test func aServerFailureIsThrownNotRecorded() async {
        let (mb, _) = client([.respond(500), .respond(500), .respond(500)])
        await #expect(throws: ProviderFailure.self) { _ = try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"]) }
    }

    @Test func anUnreadableBodyIsThrown() async {
        let (mb, _) = client([.respond(200, "<html>")])
        await #expect(throws: ProviderFailure.unparsable) { _ = try await mb.identify(artist: "Velvet Lanterns", albums: ["Night Ferry"]) }
    }

    @Test func anUnqueryableNameSendsNothing() async throws {
        let (mb, http) = client([])
        #expect(try await mb.identify(artist: "!!!", albums: ["Night Ferry"]) == .unresolved(.emptyName))
        #expect(http.requests.isEmpty)
    }
}
