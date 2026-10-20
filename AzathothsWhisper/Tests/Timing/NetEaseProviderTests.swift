import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.7 網易雲：cloudsearch/pc（form POST）→ song/lyric 的 lrc.lyric。歌詞為編造句
@Suite("NetEaseProvider")
struct NetEaseProviderTests {
    static let query = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200)

    static func search(duration: Int = 200_500, code: Int = 200) -> String {
        #"{"code":\#(code),"result":{"songs":[{"id":42,"name":"Lantern Song","dt":\#(duration),"ar":[{"name":"Some Band"}]}]}}"#
    }

    static let lyric = #"{"code":200,"lrc":{"lyric":"[00:00.00] 作词 : Somebody\n[00:01.00] 作曲 : Somebody\n[00:10.00]Lanterns over the river\n[00:14.00]Ash in the wind\n[00:20.00]Count the silent bells"}}"#

    private func provider(_ client: ScriptedHTTPClient) -> NetEaseProvider {
        NetEaseProvider(gate: .testing(client))
    }

    @Test func aMatchWithAnLRCIsAnAnswerAndCreditLinesAreDropped() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, Self.lyric)])
        let outcome = try await provider(client).lookup(Self.query)
        guard case .timed(let lines, let matched) = outcome else { Issue.record("\(outcome)"); return }
        #expect(lines.map(\.start) == [10, 14, 20])
        #expect(matched.duration == 200.5)
        let items = URLComponents(url: client.requests[1].url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "id", value: "42")))
    }

    /// V2：搜尋 form 只帶「歌手 曲名」與固定參數；沒有 cookie
    @Test func theSearchCarriesOnlyArtistAndTitle() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, Self.lyric)])
        _ = try await provider(client).lookup(Self.query)
        let request = try #require(client.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://music.163.com/api/cloudsearch/pc")
        // 筆數＝TimingCandidate.limit（R3）
        #expect(String(decoding: request.body ?? Data(), as: UTF8.self) == "limit=10&s=Some%20Band%20Lantern%20Song&type=1")
        #expect(client.requests.allSatisfy { $0.headers["Cookie"] == nil })
    }

    @Test func aPureInstrumentalPlaceholderIsTooFewLines() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, #"{"code":200,"lrc":{"lyric":"[00:00.00] 纯音乐，请欣赏\n"}}"#)])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.tooFewLines))
    }

    @Test func noLyricIsNotFound() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search()), .respond(200, #"{"code":200,"nolyric":true}"#)])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.notFound))
    }

    @Test func aWrongDurationIsAMismatch() async throws {
        let client = ScriptedHTTPClient([.respond(200, Self.search(duration: 260_000))])
        #expect(try await provider(client).lookup(Self.query) == .noTiming(.mismatch))
    }

    @Test func anAPIErrorCodeIsUnparsable() async {
        let client = ScriptedHTTPClient([.respond(200, Self.search(code: 405))])
        await #expect(throws: ProviderFailure.unparsable) { _ = try await provider(client).lookup(Self.query) }
    }

    @Test(arguments: ["作词 : A", "作曲：B", "编曲 : C", "制作人 : D", "Lyrics by: E", "Composed by : F"])
    func creditLinesAreRecognised(text: String) {
        #expect(LyricCredits.isCredit(text))
    }

    @Test func ordinaryLinesAreNotCredits() {
        #expect(!LyricCredits.isCredit("Lanterns over the river"))
        #expect(!LyricCredits.isCredit("Time: the healer"))
    }
}
