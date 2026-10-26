import Foundation
import Network

/// 按鈕①②：Bonjour 瀏覽 `_yse._tcp`，恰好一個服務時以明文 TCP 連它、收一行 N5 訊息。
/// N5 不驗 TLS，也不證明身分（只證明 Bonjour＋TCP 可達）；身分由使用者目視比對 challenge。
enum NetworkProbe {
    /// 找到第一個服務後再多等這麼久，讓同時出現的其他服務也列進來
    private static let settleSeconds: TimeInterval = 1.5
    private static let queue = DispatchQueue(label: "yse-probe.network")

    struct BrowseOutcome: Sendable {
        let names: [String]
        let endpoint: NWEndpoint?
        let failure: String?
    }

    // MARK: ① Bonjour 瀏覽

    static func browse(window: TimeInterval = probeTimeoutSeconds) async -> BrowseOutcome {
        let browser = NWBrowser(for: .bonjour(type: N5Message.serviceType, domain: nil), using: .tcp)
        let state = BrowseState()
        let outcome: BrowseOutcome = await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            browser.browseResultsChangedHandler = { results, _ in
                if state.update(results: results) {
                    queue.asyncAfter(deadline: .now() + settleSeconds) { once.resume(state.snapshot()) }
                }
            }
            browser.stateUpdateHandler = { newState in
                switch newState {
                case .failed(let error):
                    state.record(failure: "failed: \(networkErrorText(error))")
                    once.resume(state.snapshot())
                case .waiting(let error):
                    state.record(failure: "waiting: \(networkErrorText(error))")
                default: break
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + window) { once.resume(state.snapshot()) }
        }
        browser.cancel()
        return outcome
    }

    private final class BrowseState: @unchecked Sendable {
        private let lock = NSLock()
        private var services: [(name: String, endpoint: NWEndpoint)] = []
        private var failure: String?
        private var settleScheduled = false

        /// 回傳 true＝這次是第一次出現結果（呼叫端據此排程收尾）
        func update(results: Set<NWBrowser.Result>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let services = results.compactMap { result -> (String, NWEndpoint)? in
                if case .service(let name, _, _, _) = result.endpoint { return (name, result.endpoint) }
                return nil
            }.sorted { $0.0 < $1.0 }
            self.services = services.map { (name: $0.0, endpoint: $0.1) }
            guard !services.isEmpty, !settleScheduled else { return false }
            settleScheduled = true
            return true
        }

        func record(failure text: String) {
            lock.lock()
            failure = text
            lock.unlock()
        }

        func snapshot() -> BrowseOutcome {
            lock.lock()
            defer { lock.unlock() }
            let names = services.map(\.name)
            // 只有規則判定唯一時才交出端點（規則見 BrowseSelection）
            guard case .unique(let index) = BrowseSelection.select(names: names, failure: failure) else {
                return BrowseOutcome(names: names, endpoint: nil, failure: failure)
            }
            return BrowseOutcome(names: names, endpoint: services[index].endpoint, failure: failure)
        }
    }

    // MARK: ② 明文 TCP 收一行

    static func connect(to endpoint: NWEndpoint?, timeout: TimeInterval = probeTimeoutSeconds) async -> ConnectResult {
        guard let endpoint else { return .noEndpoint }
        let connection = NWConnection(to: endpoint, using: .tcp)
        let state = ConnectState()
        let result: ConnectResult = await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready: receive(connection, buffer: Data(), once: once)
                case .failed(let error): once.resume(.failed(networkErrorText(error)))
                case .waiting(let error): state.record(waiting: "waiting: \(networkErrorText(error))")
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                once.resume(state.waiting.map { .failed($0) } ?? .timedOut)
            }
        }
        connection.cancel()
        return result
    }

    private final class ConnectState: @unchecked Sendable {
        private let lock = NSLock()
        private var lastWaiting: String?

        func record(waiting text: String) {
            lock.lock()
            lastWaiting = text
            lock.unlock()
        }

        var waiting: String? {
            lock.lock()
            defer { lock.unlock() }
            return lastWaiting
        }
    }

    /// TCP 可能分段，交給 N5Message.frame 判斷是否收齊
    private static func receive(_ connection: NWConnection, buffer: Data, once: OneShot<ConnectResult>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: N5Message.maxFrameBytes) { data, _, isComplete, error in
            var next = buffer
            if let data { next.append(data) }
            switch N5Message.frame(next) {
            case .challenge(let challenge): once.resume(.received(challenge))
            case .invalid: once.resume(.invalidMessage)
            case .needMore:
                if let error {
                    once.resume(.failed(networkErrorText(error)))
                } else if isComplete {
                    once.resume(.failed("連線在收到完整訊息前關閉"))
                } else {
                    receive(connection, buffer: next, once: once)
                }
            }
        }
    }
}
