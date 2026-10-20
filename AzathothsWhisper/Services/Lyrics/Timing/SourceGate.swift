import Foundation

/// 每個時間軸來源一道 gate（C 段計劃 §3.6）：該來源**每一個**對外請求的唯一入口。
///
/// - 間隔：預約時段後才等待（actor 重入時順序不亂）；等待中被取消就退回時段、不發請求
/// - 逾時：一律用 `policy.timeout`，不信呼叫端
/// - 熔斷：連續 `failureLimit` 次失敗（429、403、5xx、連線、逾時）→ 開 `openDuration`；
///   到期後只放一個試探請求（半開），成功即關、失敗再開
/// - Retry-After：秒數或 HTTP-date，加 0–30 % 抖動，上限 1 h；期間視為熔斷中。
///   503＋短 Retry-After（LRCLIB 文件的 ServerOverloaded）等候後重試一次，不計入熔斷
/// - 快取：呼叫端標 `cacheable` 的 200 回應在記憶體留 30 分鐘、最多 200 筆
actor SourceGate {
    struct Policy: Sendable {
        static let defaultTimeout: TimeInterval = 6
        static let defaultOpenDuration: TimeInterval = 600
        static let maximumRetryAfter: TimeInterval = 3600
        /// 503 的 Retry-After 不超過這個才原地等候重試
        static let maximumInlineRetry: TimeInterval = 5
        static let retryAfterJitter = 0.3
        static let cacheLifetime: TimeInterval = 1800
        static let cacheCapacity = 200
        /// 只快取小回應、且總量有上限（安全評審 MEDIUM-2／效率審查）
        static let cacheableBodyLimit = 256 << 10
        static let cacheByteBudget = 8 << 20

        let minimumInterval: TimeInterval
        var timeout: TimeInterval = defaultTimeout
        var failureLimit = 3
        var openDuration: TimeInterval = defaultOpenDuration
    }

    private enum Circuit {
        case closed(failures: Int)
        case open(until: TimeInterval)
        case probing
    }

    private struct CachedResponse {
        let response: HTTPResponse
        let expires: TimeInterval
    }

    private let policy: Policy
    private let client: any HTTPClient
    private let clock: any MonotonicClock
    private let sleeper: any PollClock
    private let jitter: @Sendable () -> Double
    private let wallNow: @Sendable () -> Date

    private var circuit = Circuit.closed(failures: 0)
    private var nextSlot: TimeInterval = -.infinity
    private var cache: [String: CachedResponse] = [:]
    private var cacheOrder: [String] = []
    private var cachedBytes = 0

    init(
        policy: Policy, client: any HTTPClient, clock: any MonotonicClock = SystemMonotonicClock(),
        sleeper: any PollClock = SystemPollClock(), jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
        wallNow: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.policy = policy
        self.client = client
        self.clock = clock
        self.sleeper = sleeper
        self.jitter = jitter
        self.wallNow = wallNow
    }

    func send(_ request: HTTPRequest, cacheable: Bool = false) async throws(ProviderFailure) -> HTTPResponse {
        guard !Task.isCancelled else { throw .cancelled }
        let key = Self.cacheKey(request)
        if cacheable, let hit = cachedResponse(for: key) { return hit }
        let isProbe = try admit()
        do {
            let response = try await sendRetryingOverload(request)
            recordSuccess()
            if cacheable, response.statusCode == 200, response.body.utf8.count <= Policy.cacheableBodyLimit { store(response, for: key) }
            return response
        } catch {
            if isProbe, error == .cancelled { circuit = .open(until: clock.now) }   // 試探被取消：讓下一個請求接手試探
            throw error
        }
    }

    // MARK: 熔斷

    /// 放行就回傳「這是不是半開的試探」
    private func admit() throws(ProviderFailure) -> Bool {
        switch circuit {
        case .closed:
            return false
        case .probing:
            throw .circuitOpen
        case .open(let until):
            guard clock.now >= until else { throw .circuitOpen }
            circuit = .probing
            return true
        }
    }

    private func recordSuccess() {
        circuit = .closed(failures: 0)
    }

    private func recordFailure(openFor duration: TimeInterval? = nil) {
        switch circuit {
        case .closed(let failures) where duration == nil && failures + 1 < policy.failureLimit:
            circuit = .closed(failures: failures + 1)
        default:
            circuit = .open(until: clock.now + (duration ?? policy.openDuration))
        }
    }

    // MARK: 請求

    private func sendRetryingOverload(_ request: HTTPRequest) async throws(ProviderFailure) -> HTTPResponse {
        let response = try await sendSpaced(request)
        if response.statusCode == 503, let wait = retryAfter(response), wait <= Policy.maximumInlineRetry {
            try await sleep(wait)
            return try classify(try await sendSpaced(request))
        }
        return try classify(response)
    }

    private func sendSpaced(_ request: HTTPRequest) async throws(ProviderFailure) -> HTTPResponse {
        let previous = nextSlot
        let slot = max(clock.now, nextSlot + policy.minimumInterval)
        nextSlot = slot
        do {
            try await sleep(slot - clock.now)
        } catch {
            if nextSlot == slot { nextSlot = previous }   // 取消的等待退回時段
            throw error
        }
        let bounded = HTTPRequest(
            method: request.method, url: request.url, headers: request.headers, body: request.body,
            timeout: policy.timeout, maxResponseBytes: request.maxResponseBytes
        )
        do {
            return try await client.send(bounded)
        } catch let error as HTTPError {
            let failure = Self.failure(for: error)
            if failure != .cancelled { recordFailure() }
            throw failure
        } catch {
            recordFailure()
            throw .transport
        }
    }

    /// 429、403、5xx 是失敗；其餘（含 404）是答案
    private func classify(_ response: HTTPResponse) throws(ProviderFailure) -> HTTPResponse {
        switch response.statusCode {
        case 429:
            let wait = retryAfter(response)
            holdOff(for: wait ?? policy.openDuration)
            throw .rateLimited(retryAfter: wait)
        case 403:
            recordFailure()
            throw .blocked(status: 403)
        case 500...599:
            recordFailure()
            throw .server(status: response.statusCode)
        default:
            return response
        }
    }

    private func sleep(_ seconds: TimeInterval) async throws(ProviderFailure) {
        guard seconds > 0 else {
            if Task.isCancelled { throw .cancelled }
            return
        }
        do {
            try await sleeper.sleep(for: .milliseconds(Int((seconds * 1000).rounded(.up))))
        } catch {
            throw .cancelled
        }
    }

    /// 秒數或 HTTP-date；不加抖動的原值上限 1 h（回報給呼叫端的值）
    private func retryAfter(_ response: HTTPResponse) -> TimeInterval? {
        guard let raw = response.headers["retry-after"]?.trimmingCharacters(in: .whitespaces) else { return nil }
        let seconds: TimeInterval?
        if let value = TimeInterval(raw) {
            seconds = value
        } else if let date = Self.httpDate(raw) {
            seconds = date.timeIntervalSince(wallNow())
        } else {
            seconds = nil
        }
        guard let seconds, seconds.isFinite else { return nil }   // "nan" 也解析得到（安全評審 LOW-1）
        return min(max(seconds, 0), Policy.maximumRetryAfter)
    }

    /// 429：照 Retry-After 加抖動直接開路，不等累計到上限（LRCLIB 文件：不遵守可能被暫時封鎖）
    private func holdOff(for wait: TimeInterval) {
        recordFailure(openFor: min(wait * (1 + Policy.retryAfterJitter * jitter()), Policy.maximumRetryAfter))
    }

    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }

    private static func failure(for error: HTTPError) -> ProviderFailure {
        switch error {
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .transport, .invalidURL: return .transport
        case .undecodableBody, .responseTooLarge: return .unparsable
        }
    }

    // MARK: 快取

    private static func cacheKey(_ request: HTTPRequest) -> String {
        "\(request.method) \(request.url.absoluteString) \(request.body.map { String(decoding: $0, as: UTF8.self) } ?? "")"
    }

    private func cachedResponse(for key: String) -> HTTPResponse? {
        guard let entry = cache[key] else { return nil }
        guard entry.expires > clock.now else {
            evict(key)
            return nil
        }
        return entry.response
    }

    private func store(_ response: HTTPResponse, for key: String) {
        evict(key)
        cacheOrder.append(key)
        cache[key] = CachedResponse(response: response, expires: clock.now + Policy.cacheLifetime)
        cachedBytes += response.body.utf8.count
        while cacheOrder.count > Policy.cacheCapacity || cachedBytes > Policy.cacheByteBudget, let oldest = cacheOrder.first {
            evict(oldest)
        }
    }

    private func evict(_ key: String) {
        guard let entry = cache.removeValue(forKey: key) else { return }
        cachedBytes -= entry.response.body.utf8.count
        cacheOrder.removeAll { $0 == key }
    }
}
