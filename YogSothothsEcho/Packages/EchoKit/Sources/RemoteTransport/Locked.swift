import os

/// `OSAllocatedUnfairLock` 的薄包裝：鎖內只做純狀態轉移，不在鎖內做 I/O 或 Network 操作（sprint-2-detail.md §4.7）
public final class Locked<State: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<State>

    public init(_ initial: State) { lock = OSAllocatedUnfairLock(initialState: initial) }

    public func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
        try lock.withLock(body)
    }
}
