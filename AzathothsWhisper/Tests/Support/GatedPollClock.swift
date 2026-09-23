import Foundation

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
    /// 每次 `sleep` 請求的時長，依請求順序
    private(set) var requested: [Duration] = []

    var pendingCount: Int { sleepers.count }

    func sleep(for interval: Duration) async throws {
        requested.append(interval)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await suspend(id: id)
        } onCancel: { [weak self] in
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

    /// 喚醒最早的一個等待者
    func releaseNext() {
        guard !sleepers.isEmpty else { return }
        sleepers.removeFirst().continuation.resume()
    }

    func releaseAll() {
        let woken = sleepers
        sleepers = []
        woken.forEach { $0.continuation.resume() }
    }

    /// 讓出直到至少 `count` 個等待者已掛上（有界：超過輪數即返回，由呼叫端的斷言暴露）
    func waitUntilPending(_ count: Int, iterations: Int = 20_000) async {
        for _ in 0..<iterations {
            if sleepers.count >= count { return }
            await Task.yield()
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
