import Foundation

@testable import YogSothothsEcho

/// F-L1 R0（s6-61-library-retry.md §6）：可取消的假睡眠。記錄每次要求的時長；`hold` 時掛起直到 `wake`；
/// 掛起中被取消＝拋 `CancellationError`；設了 `failure` 就拋它（測非取消的睡眠錯誤）
final class CancellableSleeper: @unchecked Sendable {
    let lock = NSLock()
    var hold = false
    var failure: (any Error & Sendable)?
    private var requested: [Duration] = []
    private var gates: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func sleep(_ duration: Duration) async throws {
        let (hold, failure) = lock.withLock { () -> (Bool, (any Error & Sendable)?) in
            requested.append(duration)
            return (self.hold, self.failure)
        }
        if let failure { throw failure }
        try Task.checkCancellation()
        guard hold else { return }
        let id = UUID()
        let woke = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    gates[id] = c
                    return false
                }
                if cancelled { c.resume(returning: false) }
            }
        } onCancel: {
            lock.withLock { gates.removeValue(forKey: id) }?.resume(returning: false)
        }
        if !woke { throw CancellationError() }
    }

    func wake() { lock.withLock { () -> [CheckedContinuation<Bool, Never>] in defer { gates = [:] }; return Array(gates.values) }.forEach { $0.resume(returning: true) } }
    var durations: [Duration] { lock.withLock { requested } }
    var waiting: Int { lock.withLock { gates.count } }
    var options: ShortTransientRetry.Options { .init(sleeper: { [self] in try await sleep($0) }, jitter: { 0 }) }
}

struct SleepFailure: Error {}
