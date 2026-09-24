import Foundation
import os

@testable import AzathothsWhisper

/// 可控時鐘（計劃 Q0）：`sleep` 掛起直到測試放行。
///
/// 與 `ImmediateClock` 的分工：後者讓輪詢以測試節奏空轉；本型別用來斷言「到期前」與「到期時」
/// 兩個時點（例如寫入成功後的升回延遲、延遲中換歌），也能驗取消。
actor GatedPollClock: PollClock {
    private struct Sleeper {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var sleepers: [Sleeper] = []
    /// 已取消的等待者。取消在呼叫端**同步**發生，而 actor 內的移除要等排程——中間若有人 release，
    /// 會把已取消者當成正常喚醒（對抗覆核 P2）。故以鎖同步記錄，release 時即可跳過
    private nonisolated let cancelledIDs = OSAllocatedUnfairLock(initialState: Set<UUID>())
    /// 每次 `sleep` 請求的時長，依請求順序
    private(set) var requested: [Duration] = []

    var pendingCount: Int { sleepers.filter { !isCancelled($0.id) }.count }

    func sleep(for interval: Duration) async throws {
        requested.append(interval)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await suspend(id: id)
        } onCancel: { [weak self] in
            self?.cancelledIDs.withLock { _ = $0.insert(id) }
            Task { await self?.cancel(id) }
        }
    }

    private func suspend(id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // 已取消的任務不得掛進等待列（onCancel 可能先於此處觸發，屆時找不到可喚醒的對象）
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
                return
            }
            sleepers.append(Sleeper(id: id, continuation: continuation))
        }
    }

    /// 喚醒最早的一個仍在等的等待者（途中遇到已取消者，以 CancellationError 結束它）
    func releaseNext() {
        while !sleepers.isEmpty {
            let sleeper = sleepers.removeFirst()
            if isCancelled(sleeper.id) {
                sleeper.continuation.resume(throwing: CancellationError())
                continue
            }
            sleeper.continuation.resume()
            return
        }
    }

    func releaseAll() {
        let woken = sleepers
        sleepers = []
        for sleeper in woken {
            if isCancelled(sleeper.id) {
                sleeper.continuation.resume(throwing: CancellationError())
            } else {
                sleeper.continuation.resume()
            }
        }
    }

    /// 讓出直到至少 `count` 個等待者已掛上（有界：超過輪數即返回，由呼叫端的斷言暴露）
    func waitUntilPending(_ count: Int, iterations: Int = 20_000) async {
        for _ in 0..<iterations {
            if sleepers.count >= count { return }
            await Task.yield()
        }
    }

    private nonisolated func isCancelled(_ id: UUID) -> Bool {
        cancelledIDs.withLock { $0.contains(id) }
    }

    /// 每個 continuation 只會被 resume 一次：只有從 `sleepers` 移出的那一方會 resume 它
    private func cancel(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
