import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.6：每個來源一道 gate——間隔、逾時、熔斷（開／半開／關）、Retry-After、快取。全部用假時鐘，不真的等
@Suite("SourceGate")
struct SourceGateTests {
    static let url = URL(string: "https://example.com/search?q=x")!
    static func get(_ url: URL = url) -> HTTPRequest { HTTPRequest(method: "GET", url: url, timeout: 30) }

    private func gate(_ client: ScriptedHTTPClient, _ clock: FakeTimingClock, interval: TimeInterval = 1, wallNow: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> SourceGate {
        SourceGate(
            policy: .init(minimumInterval: interval), client: client, clock: clock, sleeper: clock,
            jitter: { 0 }, wallNow: { wallNow }
        )
    }

    @Test func requestsAreSpacedByTheMinimumInterval() async throws {
        let clock = FakeTimingClock()
        let gate = gate(ScriptedHTTPClient([.respond(200), .respond(200)]), clock, interval: 0.5)
        _ = try await gate.send(Self.get(URL(string: "https://example.com/a")!))
        _ = try await gate.send(Self.get(URL(string: "https://example.com/b")!))
        #expect(clock.sleeps == [0.5])
    }

    @Test func theGateImposesItsOwnShortTimeout() async throws {
        let client = ScriptedHTTPClient([.respond(200)])
        _ = try await gate(client, FakeTimingClock()).send(Self.get())
        #expect(client.requests.first?.timeout == SourceGate.Policy.defaultTimeout)
    }

    @Test(arguments: [ScriptedHTTPClient.Step.respond(403), .respond(500), .fail(.transport("x")), .fail(.timedOut)])
    func threeConsecutiveFailuresOpenTheCircuit(failure: ScriptedHTTPClient.Step) async {
        let client = ScriptedHTTPClient([failure, failure, failure, .respond(200)])
        let gate = gate(client, FakeTimingClock())
        for index in 0..<3 {
            await #expect(throws: (any Error).self) { _ = try await gate.send(Self.get(URL(string: "https://example.com/\(index)")!)) }
        }
        await #expect(throws: ProviderFailure.circuitOpen) { _ = try await gate.send(Self.get()) }
        #expect(client.requests.count == 3)
    }

    @Test func aSuccessResetsTheFailureCount() async throws {
        let client = ScriptedHTTPClient([.respond(500), .respond(500), .respond(200), .respond(500), .respond(500), .respond(200)])
        let gate = gate(client, FakeTimingClock())
        for index in 0..<6 { _ = try? await gate.send(Self.get(URL(string: "https://example.com/\(index)")!)) }
        #expect(client.requests.count == 6)
    }

    @Test func afterTheOpenPeriodOneProbeIsLetThroughAndItsSuccessCloses() async throws {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([.respond(500), .respond(500), .respond(500), .respond(200), .respond(200)])
        let gate = gate(client, clock)
        for index in 0..<3 { _ = try? await gate.send(Self.get(URL(string: "https://example.com/\(index)")!)) }
        clock.advance(by: SourceGate.Policy.defaultOpenDuration)
        #expect(try await gate.send(Self.get(URL(string: "https://example.com/probe")!)).statusCode == 200)
        #expect(try await gate.send(Self.get(URL(string: "https://example.com/after")!)).statusCode == 200)
    }

    @Test func aFailedProbeReopensTheCircuit() async throws {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([.respond(500), .respond(500), .respond(500), .respond(500)])
        let gate = gate(client, clock)
        for index in 0..<3 { _ = try? await gate.send(Self.get(URL(string: "https://example.com/\(index)")!)) }
        clock.advance(by: SourceGate.Policy.defaultOpenDuration)
        _ = try? await gate.send(Self.get(URL(string: "https://example.com/probe")!))
        await #expect(throws: ProviderFailure.circuitOpen) { _ = try await gate.send(Self.get(URL(string: "https://example.com/next")!)) }
        #expect(client.requests.count == 4)
    }

    @Test func whileTheProbeIsInFlightOthersAreTurnedAway() async throws {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([.respond(500), .respond(500), .respond(500), .hold(200)])
        let gate = gate(client, clock, interval: 0)
        for index in 0..<3 { _ = try? await gate.send(Self.get(URL(string: "https://example.com/\(index)")!)) }
        clock.advance(by: SourceGate.Policy.defaultOpenDuration)
        let probe = Task { try await gate.send(Self.get(URL(string: "https://example.com/probe")!)) }
        while client.requests.count < 4 { await Task.yield() }
        await #expect(throws: ProviderFailure.circuitOpen) { _ = try await gate.send(Self.get(URL(string: "https://example.com/other")!)) }
        client.release()
        #expect(try await probe.value.statusCode == 200)
    }

    @Test func retryAfterSecondsOn429KeepsTheSourceClosedThatLong() async throws {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([.respond(429, headers: ["retry-after": "120"]), .respond(200)])
        let gate = gate(client, clock)
        await #expect(throws: ProviderFailure.rateLimited(retryAfter: 120)) { _ = try await gate.send(Self.get()) }
        clock.advance(by: 119)
        await #expect(throws: ProviderFailure.circuitOpen) { _ = try await gate.send(Self.get(URL(string: "https://example.com/b")!)) }
        clock.advance(by: 2)
        #expect(try await gate.send(Self.get(URL(string: "https://example.com/c")!)).statusCode == 200)
    }

    @Test func retryAfterAsAnHTTPDateIsUnderstood() async {
        let wall = Date(timeIntervalSince1970: 1_800_000_000)
        let later = wall.addingTimeInterval(90)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let client = ScriptedHTTPClient([.respond(429, headers: ["retry-after": formatter.string(from: later)])])
        await #expect(throws: ProviderFailure.rateLimited(retryAfter: 90)) {
            _ = try await gate(client, FakeTimingClock(), wallNow: wall).send(Self.get())
        }
    }

    @Test func retryAfterIsCappedAtOneHour() async {
        let client = ScriptedHTTPClient([.respond(429, headers: ["retry-after": "999999"])])
        await #expect(throws: ProviderFailure.rateLimited(retryAfter: SourceGate.Policy.maximumRetryAfter)) {
            _ = try await gate(client, FakeTimingClock()).send(Self.get())
        }
    }

    /// LRCLIB 文件：503＝ServerOverloaded，照 Retry-After（通常 1 秒）再試——重試一次、不計入熔斷
    @Test func a503WithAShortRetryAfterIsRetriedOnceWithoutCountingAsAFailure() async throws {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([
            .respond(503, headers: ["retry-after": "1"]), .respond(200, "a"),
            .respond(500), .respond(500), .respond(200, "b"),
        ])
        let gate = gate(client, clock, interval: 0)
        #expect(try await gate.send(Self.get()).body == "a")
        #expect(clock.sleeps.contains(1))
        _ = try? await gate.send(Self.get(URL(string: "https://example.com/2")!))
        _ = try? await gate.send(Self.get(URL(string: "https://example.com/3")!))
        #expect(try await gate.send(Self.get(URL(string: "https://example.com/4")!)).body == "b")
    }

    @Test func aNotFoundIsAnAnswerNotAFailure() async throws {
        let client = ScriptedHTTPClient([.respond(404), .respond(404), .respond(404), .respond(200)])
        let gate = gate(client, FakeTimingClock())
        for index in 0..<4 { _ = try await gate.send(Self.get(URL(string: "https://example.com/\(index)")!)) }
        #expect(client.requests.count == 4)
    }

    @Test func aCachedResponseIsServedWithoutTouchingTheNetworkUntilItExpires() async throws {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([.respond(200, "first"), .respond(200, "second")])
        let gate = gate(client, clock)
        #expect(try await gate.send(Self.get(), cacheable: true).body == "first")
        #expect(try await gate.send(Self.get(), cacheable: true).body == "first")
        clock.advance(by: SourceGate.Policy.cacheLifetime + 1)
        #expect(try await gate.send(Self.get(), cacheable: true).body == "second")
        #expect(client.requests.count == 2)
    }

    @Test func theCacheKeepsAtMostItsCapacity() async throws {
        let client = ScriptedHTTPClient([])
        let gate = gate(client, FakeTimingClock(), interval: 0)
        for index in 0...SourceGate.Policy.cacheCapacity {
            _ = try await gate.send(Self.get(URL(string: "https://example.com/\(index)")!), cacheable: true)
        }
        _ = try await gate.send(Self.get(URL(string: "https://example.com/0")!), cacheable: true)
        #expect(client.requests.count == SourceGate.Policy.cacheCapacity + 2)   // 最舊的那筆已被擠掉
    }

    @Test func cancellationWhileWaitingSendsNothing() async {
        let clock = FakeTimingClock()
        let client = ScriptedHTTPClient([.respond(200), .respond(200)])
        let gate = gate(client, clock, interval: 10)
        _ = try? await gate.send(Self.get(URL(string: "https://example.com/a")!))
        let task = Task { try await gate.send(Self.get(URL(string: "https://example.com/b")!)) }
        task.cancel()
        await #expect(throws: ProviderFailure.cancelled) { _ = try await task.value }
        #expect(client.requests.count == 1)
    }

    @Test(arguments: [
        (HTTPError.timedOut, ProviderFailure.timedOut), (.cancelled, .cancelled), (.transport("x"), .transport),
        (.responseTooLarge, .unparsable), (.undecodableBody, .unparsable),
    ])
    func transportErrorsAreClassified(error: HTTPError, expected: ProviderFailure) async {
        await #expect(throws: expected) { _ = try await gate(ScriptedHTTPClient([.fail(error)]), FakeTimingClock()).send(Self.get()) }
    }
}
