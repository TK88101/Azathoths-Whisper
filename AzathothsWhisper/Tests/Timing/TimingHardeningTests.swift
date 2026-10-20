import Foundation
import Testing

@testable import AzathothsWhisper

// /simcodex R1 安全評審的回歸測試：外部內容不得讓 app 閃退、卡死或吃光記憶體。歌詞為編造句
@Suite("Timing hardening")
struct TimingHardeningTests {
    // HIGH-1
    @Test(arguments: ["-9223372036854775808", "9223372036854775807", "-3600001"])
    func anAbsurdOffsetIsIgnoredInsteadOfOverflowing(offset: String) {
        let lines = LRCParser.parse("[offset:\(offset)]\n[00:10.00]Lanterns over the river")
        #expect(lines == [LRCLine(start: 10, text: "Lanterns over the river")])
    }

    // HIGH-2
    @Test(arguments: ["５:００", "²:²", "٣:٢١", "3:", ":21", "Ⅻ:00"])
    func nonASCIIDigitsAreNotALength(text: String) {
        #expect(YouTubeMusicProvider.seconds(text) == nil)
    }

    // HIGH-3
    @Test func pathologicalNamesAreRejectedQuickly() {
        let wanted = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200)
        let hostile = [String(repeating: " ", count: 5000) + "- x", String(repeating: "(", count: 5000), "Lantern Song" + String(repeating: " ", count: 400)]
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for name in hostile {
                #expect(!TrackMatcher.matches(wanted, MatchedTrack(artist: name, title: "Lantern Song", duration: 200)))
                #expect(!TrackMatcher.matches(wanted, MatchedTrack(artist: "Some Band", title: name, duration: 200)))
            }
        }
        #expect(elapsed < .milliseconds(100))
    }

    // MEDIUM-1
    @Test func tooManyCuesAreOversized() {
        let lines = (0...ProviderOutcome.maximumTimedLines).map { LRCLine(start: Double($0) / 100, text: "Line \($0)") }
        #expect(ProviderOutcome.validatedTiming(lines, matched: MatchedTrack(artist: "A", title: "T", duration: 200), duration: 200) == .noTiming(.oversized))
    }

    @Test func overlongLinesAreDropped() {
        let long = String(repeating: "a", count: ProviderOutcome.maximumLineLength + 1)
        let lines = [LRCLine(start: 1, text: long), LRCLine(start: 2, text: "Ash in the wind"), LRCLine(start: 3, text: "Count the silent bells"), LRCLine(start: 4, text: "Paper boats at dawn")]
        guard case .timed(let kept, _) = ProviderOutcome.validatedTiming(lines, matched: MatchedTrack(artist: "A", title: "T", duration: 200), duration: 200) else {
            Issue.record("expected timed"); return
        }
        #expect(kept.map(\.start) == [2, 3, 4])
    }

    // LOW-5
    @Test func onlyWellFormedTokensAreAccepted() {
        #expect(DeezerProvider.isWellFormedToken("aGVhZGVy.cGF5bG9hZA.c2ln-_"))
        #expect(!DeezerProvider.isWellFormedToken("a.b\r\nX-Injected: 1"))
        #expect(!DeezerProvider.isWellFormedToken(""))
        #expect(!DeezerProvider.isWellFormedToken(String(repeating: "a", count: 4097)))
    }
}

@Suite("SourceGate hardening")
struct SourceGateHardeningTests {
    private func gate(_ client: ScriptedHTTPClient, _ clock: FakeTimingClock) -> SourceGate {
        SourceGate(policy: .init(minimumInterval: 0), client: client, clock: clock, sleeper: clock, jitter: { 0 })
    }

    // LOW-1：nan 不得讓來源永久熔斷
    @Test func aNaNRetryAfterFallsBackToTheNormalOpenPeriod() async throws {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([.respond(429, headers: ["retry-after": "nan"]), .respond(200)])
        let gate = gate(client, clock)
        await #expect(throws: ProviderFailure.rateLimited(retryAfter: nil)) { _ = try await gate.send(SourceGateTests.get()) }
        clock.advance(by: SourceGate.Policy.defaultOpenDuration + 1)
        #expect(try await gate.send(SourceGateTests.get(URL(string: "https://example.com/b")!)).statusCode == 200)
    }

    // MEDIUM-2：大回應不快取
    @Test func aLargeResponseIsNotCached() async throws {
        let big = String(repeating: "x", count: SourceGate.Policy.cacheableBodyLimit + 1)
        let client = ScriptedHTTPClient([.respond(200, big), .respond(200, "small")])
        let gate = gate(client, FakeTimingClock())
        _ = try await gate.send(SourceGateTests.get(), cacheable: true)
        #expect(try await gate.send(SourceGateTests.get(), cacheable: true).body == "small")
    }

    @Test func theCacheStaysWithinItsByteBudget() async throws {
        let chunk = String(repeating: "x", count: SourceGate.Policy.cacheableBodyLimit)
        let count = SourceGate.Policy.cacheByteBudget / SourceGate.Policy.cacheableBodyLimit + 1
        let client = ScriptedHTTPClient(Array(repeating: .respond(200, chunk), count: count + 1))
        let gate = gate(client, FakeTimingClock())
        for index in 0..<count { _ = try await gate.send(SourceGateTests.get(URL(string: "https://example.com/\(index)")!), cacheable: true) }
        _ = try await gate.send(SourceGateTests.get(URL(string: "https://example.com/0")!), cacheable: true)
        #expect(client.requests.count == count + 1)   // 最舊的那筆因位元組預算被擠掉
    }
}
