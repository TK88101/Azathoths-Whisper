import Foundation
import RemoteTransport

/// 短暫錯誤的重試規則（F-L1；s6-61-library-retry.md §5）：專輯清單、曲目清單、書脊封面、詳情封面四處共用
/// 「什麼算短暫、試幾次、等多久」；各處的重試迴圈留在原處（只共用政策，不共用執行器；Codex R1）。
/// 刻意不用 `ErrorCode.isRetryable`：它含 libraryUnavailable，那個走 LibraryViewModel 既有的 10／20／40／60 s 長退避
enum ShortTransientRetry {
    /// 可拋出、可取消（Codex R1 阻擋-1）
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    /// 錯開比例 ∈ [0, 0.25)：各請求不在同一刻重送，免得一起撞上同一個限流窗口（Codex R1 高-3）
    typealias Jitter = @Sendable () -> Double

    struct Options: Sendable {
        let sleeper: Sleeper
        let jitter: Jitter

        static let live = Options(sleeper: { try await Task.sleep(for: $0) }, jitter: { Double.random(in: 0..<0.25) })

        /// 第 n 次（n ≥ 2）之前的等待；錯誤原樣丟出，由各呼叫端決定怎麼收場
        func pause(beforeAttempt attempt: Int) async throws {
            try await sleeper(ShortTransientRetry.delay(beforeAttempt: attempt, jitter: jitter()))
        }
    }

    /// 含第一次
    static let maxAttempts = 3
    static let firstDelay: Duration = .milliseconds(500)

    static func isShortTransient(_ error: EchoRequestError) -> Bool {
        error == .remote(.busy) || error == .remote(.rateLimited)
    }

    /// 第 n 次（從 1 起）失敗後還要不要再試
    static func shouldRetry(_ error: EchoRequestError, afterAttempt attempt: Int) -> Bool {
        isShortTransient(error) && attempt < maxAttempts
    }

    /// 第 n 次（n ≥ 2）之前等多久：0.5 s、1.0 s……，再乘上 1 + jitter
    static func delay(beforeAttempt attempt: Int, jitter: Double) -> Duration {
        firstDelay * (1 << (attempt - 2)) * (1 + jitter)
    }

    /// 清單與曲目的等待：睡眠被取消＝`.cancelled`；其他睡眠錯誤＝丟觸發這次重試的原錯誤，照一般失敗呈現、不卡在載入中
    /// （Codex R4-1）。「睡醒後」的取消檢查由呼叫端迴圈頂端那一道負責
    static func wait(beforeAttempt attempt: Int, after error: EchoRequestError, _ options: Options) async throws(EchoRequestError) {
        do {
            try await options.pause(beforeAttempt: attempt)
        } catch let sleepError {
            throw Task.isCancelled || sleepError is CancellationError ? .cancelled : error
        }
    }
}
