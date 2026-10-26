import Foundation

/// continuation 只能 resume 一次；狀態回呼、逾時可能各觸發一次，先到者勝（yse-spike 的網路探針也共用）
public final class OneShot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    public init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    public func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// 工作與逾時賽跑：逾時回 nil。工作可能卡在同步呼叫（如 Keychain），所以不用 TaskGroup
/// （它會等所有子任務結束），逾時後工作的結果直接丟棄。
public func raceTimeout<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let once = OneShot(continuation)
        Task.detached { once.resume(await work()) }
        Task.detached {
            try? await Task.sleep(for: .seconds(seconds))
            once.resume(nil)
        }
    }
}
