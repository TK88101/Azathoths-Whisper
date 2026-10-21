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

/// 退路鏈測試用的來源替身（候選排序計劃 §3.1、T2）：搜尋腳本與每個候選的取詞腳本分開，搜尋次數與取詞順序分開計。
/// 舊的單步建構：一步＝搜尋回 1 筆配對的候選＋取這筆（`.noTiming(.notFound)`＝搜尋沒有結果、`.noTiming(.mismatch)`＝搜尋回 1 筆對不上的、
/// `.failure`＝搜尋失敗）；`.suspend` 會掛到被取消（或 `release()`）為止
actor FakeTimingProvider: TimedLyricsProvider {
    indirect enum Step: Sendable {
        case outcome(ProviderOutcome)
        case failure(ProviderFailure)
        case suspend(then: ProviderOutcome)
        /// 不理會取消：放行後照樣回傳（測「晚到的舊結果不得存檔」）
        case suspendIgnoringCancel(then: ProviderOutcome)
        /// 回應前把注入的假時鐘推進這麼多秒（測時間預算）
        case advancing(TimeInterval, Step)
    }

    enum Search: Sendable {
        case candidates([TimingCandidate])
        case failure(ProviderFailure)
        /// 舊單步建構的 `.suspend`：在搜尋這一步掛住（與舊 `lookup` 同一次呼叫裡記數後掛住的時序相同），放行後才回候選
        case suspending(Step, [TimingCandidate])
    }

    nonisolated let source: StoredTimingSource
    private var legacy: [Step]?
    private var searches: [Search]
    private var timings: [String: [Step]]
    private let clock: FakeTimingClock?
    private var legacyCount = 0
    private(set) var queries: [TimingQuery] = []
    /// 依序被取時間軸的候選 id
    private(set) var fetched: [String] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ source: StoredTimingSource, _ steps: [Step]) {
        self.source = source
        legacy = steps
        searches = []
        timings = [:]
        clock = nil
    }

    init(_ source: StoredTimingSource, searches: [Search], timings: [String: [Step]], clock: FakeTimingClock? = nil) {
        self.source = source
        legacy = nil
        self.searches = searches
        self.timings = timings
        self.clock = clock
    }

    /// 搜尋次數（舊名：一次搜尋＝一次查找）
    var callCount: Int { queries.count }

    func release() {
        let resumed = waiting
        waiting = []
        resumed.forEach { $0.resume() }
    }

    nonisolated func candidates(for query: TimingQuery) async throws(ProviderFailure) -> [TimingCandidate] {
        switch await nextSearch(query) {
        case .candidates(let list): return list
        case .failure(let failure): throw failure
        case .suspending(let step, let list):
            _ = try await perform(step)
            return list
        }
    }

    nonisolated func timing(of candidate: TimingCandidate, for query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        try await perform(await nextTiming(candidate.id))
    }

    private nonisolated func perform(_ step: Step) async throws(ProviderFailure) -> ProviderOutcome {
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
        case .advancing(let seconds, let next):
            await advanceClock(by: seconds)
            return try await perform(next)
        }
    }

    private func advanceClock(by seconds: TimeInterval) {
        clock?.advance(by: seconds)
    }

    private func nextSearch(_ query: TimingQuery) -> Search {
        queries.append(query)
        guard var steps = legacy else {
            return searches.isEmpty ? .candidates([]) : searches.removeFirst()
        }
        let step = steps.isEmpty ? .outcome(.noTiming(.notFound)) : steps.removeFirst()
        legacy = steps
        legacyCount += 1
        let id = "legacy-\(legacyCount)"
        let matching = TimingCandidate(track: MatchedTrack(artist: query.artist, title: query.title, duration: query.duration), id: id)
        switch step {
        case .failure(let failure):
            return .failure(failure)
        case .outcome(.noTiming(.notFound)):
            return .candidates([])
        case .outcome(.noTiming(.mismatch)):
            return .candidates([TimingCandidate(track: MatchedTrack(artist: "Unrelated Act", title: "Unrelated Piece", duration: query.duration), id: id)])
        case .suspend(let then), .suspendIgnoringCancel(let then):
            timings[id] = [.outcome(then)]
            return .suspending(step, [matching])
        default:
            timings[id] = [step]
            return .candidates([matching])
        }
    }

    private func nextTiming(_ id: String) -> Step {
        fetched.append(id)
        guard var steps = timings[id], !steps.isEmpty else { return .outcome(.noTiming(.notFound)) }
        let step = steps.removeFirst()
        timings[id] = steps
        return step
    }

    private func park() async {
        await withCheckedContinuation { waiting.append($0) }
    }
}

extension TimedLyricsProvider {
    /// 舊 `lookup` 的語意（測試用）：搜尋 → 排序 → 只取第 1 名；沒有配對＝notFound／mismatch
    func lookupFirstRanked(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        let found = try await candidates(for: query)
        guard let first = TimingCandidate.ranked(found, for: query).first else { return .noTiming(.miss(among: found.count)) }
        return try await timing(of: first, for: query)
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
