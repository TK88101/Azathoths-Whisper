import Foundation
import Network
import RemoteProtocol

public struct DiscoveredMac: Equatable, Sendable {
    /// Bonjour 實例名：只作尋址提示，不作身分（CR-010 ②(b)）
    public let name: String
    public let endpoint: NWEndpoint

    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
    }
}

/// iPad 端 Bonjour 瀏覽（`_yse._tcp`、`local.`、不走 peer-to-peer；sprint-2-detail.md §4.7）
public final class MacBrowser: Sendable {
    static let descriptor = NWBrowser.Descriptor.bonjour(type: EchoService.type, domain: EchoService.domain)

    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "yse.transport.browser")

    public init() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        browser = NWBrowser(for: Self.descriptor, using: parameters)
    }

    /// 目前看到的 Mac 清單（每次變動送一次）；取消 stream 即停止瀏覽
    public func results() -> AsyncStream<[DiscoveredMac]> {
        AsyncStream { continuation in
            browser.browseResultsChangedHandler = { results, _ in
                continuation.yield(results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredMac(name: name, endpoint: result.endpoint)
                })
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { continuation.finish() }
                if case .cancelled = state { continuation.finish() }
            }
            continuation.onTermination = { [browser] _ in browser.cancel() }
            browser.start(queue: queue)
        }
    }

    /// 收集一個時窗內的結果（LOW-6）：每次變動送的都是完整清單，保留最後一批。
    /// - `isEnough` 為真（看到 QR 上那台或已配對的 Mac）後再收 `grace`：冒名者先廣播同名時，真的那台仍來得及進清單（security review LOW-3）
    /// - 一直不夠時，第一批非空之後最多再等 `settle`，不等滿時窗（simplify 效率 #6）
    /// - 串流先結束就回最後一批
    public static func gather(_ results: AsyncStream<[DiscoveredMac]>, window: Duration, grace: Duration = .milliseconds(300),
                              settle: Duration = .seconds(1),
                              isEnough: @escaping @Sendable ([DiscoveredMac]) -> Bool) async -> [DiscoveredMac] {
        let latest = Locked<[DiscoveredMac]>([])
        let deadline = Locked<ContinuousClock.Instant>(.now + window)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await macs in results {
                    let wasEmpty = latest.withLock { old in defer { old = macs }; return old.isEmpty }
                    let extra: Duration? = isEnough(macs) ? grace : (wasEmpty && !macs.isEmpty ? settle : nil)
                    if let extra { deadline.withLock { $0 = min($0, .now + extra) } }
                }
            }
            group.addTask {
                while ContinuousClock.now < deadline.withLock({ $0 }) {
                    try? await Task.sleep(for: .milliseconds(100))   // 等 Mac 出現時一窗 30 s，步長 100 ms 減少喚醒（S4 F14；單發等待化列 P2）
                    if Task.isCancelled { return }
                }
            }
            await group.next()
            group.cancelAll()
        }
        return latest.withLock { $0 }
    }

    /// QR 上的實例名排最前（只是尋址提示；真正的身分由釘選決定），其餘保持原順序
    public static func order(_ macs: [DiscoveredMac], preferring name: String?) -> [DiscoveredMac] {
        order(macs, preferringAny: name.map { [$0] } ?? [])
    }

    /// 已配對的每一台都算偏好（S4 F14：等任何一台配對過的 Mac 出現）
    public static func order(_ macs: [DiscoveredMac], preferringAny names: Set<String>) -> [DiscoveredMac] {
        macs.filter { names.contains($0.name) } + macs.filter { !names.contains($0.name) }
    }
}
