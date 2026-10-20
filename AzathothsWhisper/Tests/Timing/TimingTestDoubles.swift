import Foundation

@testable import AzathothsWhisper

/// 手動推進的單調時鐘＋sleep：sleep 直接把時間往前推，測試不真的等
final class FakeTimingClock: MonotonicClock, PollClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval
    private var slept: [TimeInterval] = []

    init(start: TimeInterval = 1_000) { current = start }

    var now: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    var sleeps: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return slept
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current += seconds
    }

    func sleep(for interval: Duration) async throws {
        try Task.checkCancellation()
        let seconds = interval.inSeconds
        lock.withLock {
            slept.append(seconds)
            current += seconds
        }
        try Task.checkCancellation()
    }
}

/// 依序回應的 HTTP 替身：每個請求取下一個腳本項；可在某一項掛住直到放行（測半開只放一個試探）
final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    enum Step: Sendable {
        case respond(Int, String = "", headers: [String: String] = [:])
        case fail(HTTPError)
        case hold(Int)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var sent: [HTTPRequest] = []
    private var holds: [CheckedContinuation<Void, Never>] = []

    init(_ steps: [Step]) { self.steps = steps }

    var requests: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return sent
    }

    func release() {
        lock.lock()
        let waiting = holds
        holds = []
        lock.unlock()
        waiting.forEach { $0.resume() }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let step: Step = lock.withLock {
            sent.append(request)
            return steps.isEmpty ? .respond(200, "") : steps.removeFirst()
        }
        switch step {
        case .respond(let status, let body, let headers):
            return HTTPResponse(statusCode: status, body: body, headers: headers)
        case .fail(let error):
            throw error
        case .hold(let status):
            await withCheckedContinuation { continuation in
                lock.withLock { holds.append(continuation) }
            }
            return HTTPResponse(statusCode: status, body: "")
        }
    }

    func get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        try await send(HTTPRequest(method: "GET", url: url, headers: headers, timeout: timeout))
    }

    func post(_ url: URL, form: [String: String], headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        try await send(HTTPRequest(method: "POST", url: url, headers: headers, timeout: timeout))
    }
}

/// 退路鏈測試用的來源替身：依序回應腳本；`.suspend` 會掛到被取消（或 `release()`）為止
actor FakeTimingProvider: TimedLyricsProvider {
    enum Step: Sendable {
        case outcome(ProviderOutcome)
        case failure(ProviderFailure)
        case suspend(then: ProviderOutcome)
        /// 不理會取消：放行後照樣回傳（測「晚到的舊結果不得存檔」）
        case suspendIgnoringCancel(then: ProviderOutcome)
    }

    nonisolated let source: StoredTimingSource
    private var steps: [Step]
    private(set) var queries: [TimingQuery] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ source: StoredTimingSource, _ steps: [Step]) {
        self.source = source
        self.steps = steps
    }

    var callCount: Int { queries.count }

    func release() {
        let resumed = waiting
        waiting = []
        resumed.forEach { $0.resume() }
    }

    nonisolated func lookup(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        let step = await next(query)
        switch step {
        case .outcome(let outcome):
            return outcome
        case .failure(let failure):
            throw failure
        case .suspend(let outcome):
            await withTaskCancellationHandler {
                await park()
            } onCancel: {
                Task { await self.release() }
            }
            if Task.isCancelled { throw .cancelled }
            return outcome
        case .suspendIgnoringCancel(let outcome):
            await park()
            return outcome
        }
    }

    private func next(_ query: TimingQuery) -> Step {
        queries.append(query)
        return steps.isEmpty ? .outcome(.noTiming(.notFound)) : steps.removeFirst()
    }

    private func park() async {
        await withCheckedContinuation { waiting.append($0) }
    }
}

/// 掛到被取消為止的 sleep（時限永遠不會自己到期）
struct NeverSleeper: PollClock {
    func sleep(for interval: Duration) async throws {
        try await Task.sleep(for: .seconds(86_400 * 365))
    }
}

extension SourceGate {
    /// 測試用：無間隔、假時鐘、無抖動
    static func testing(_ client: ScriptedHTTPClient) -> SourceGate {
        let clock = FakeTimingClock()
        return SourceGate(policy: .init(minimumInterval: 0), client: client, clock: clock, sleeper: clock, jitter: { 0 })
    }
}
