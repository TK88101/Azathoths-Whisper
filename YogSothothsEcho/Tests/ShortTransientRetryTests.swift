import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// F-L1 R1（s6-61-library-retry.md §5）：四處讀取共用的短暫錯誤重試規則
struct ShortTransientRetryTests {
    @Test(arguments: [EchoRequestError.remote(.busy), .remote(.rateLimited)])
    func busyAndRateLimitedAreShortTransient(_ error: EchoRequestError) {
        #expect(ShortTransientRetry.isShortTransient(error))
    }

    /// 刻意與 `ErrorCode.isRetryable` 分歧：libraryUnavailable 走清單的 10／20／40／60 s 長退避，不走短重試
    @Test(arguments: [EchoRequestError.remote(.libraryUnavailable), .remote(.invalidRequest), .disconnected, .cancelled, .timeout,
                      .invalidResponse])
    func othersAreNotShortTransient(_ error: EchoRequestError) {
        #expect(!ShortTransientRetry.isShortTransient(error))
    }

    @Test func libraryUnavailableIsRetryableButNotShortTransient() {
        #expect(ErrorCode.libraryUnavailable.isRetryable)
        #expect(!ShortTransientRetry.isShortTransient(.remote(.libraryUnavailable)))
    }

    /// 最多 3 次（含第一次）：第 1、2 次失敗後再試，第 3 次失敗即停；不是短暫錯誤就不試
    @Test func retriesAfterFirstAndSecondAttemptOnly() {
        #expect(ShortTransientRetry.shouldRetry(.remote(.busy), afterAttempt: 1))
        #expect(ShortTransientRetry.shouldRetry(.remote(.rateLimited), afterAttempt: 2))
        #expect(!ShortTransientRetry.shouldRetry(.remote(.busy), afterAttempt: 3))
        #expect(!ShortTransientRetry.shouldRetry(.remote(.libraryUnavailable), afterAttempt: 1))
    }

    @Test func delayGrowsAndIsStretchedByJitter() {
        #expect(ShortTransientRetry.delay(beforeAttempt: 2, jitter: 0) == .milliseconds(500))
        #expect(ShortTransientRetry.delay(beforeAttempt: 3, jitter: 0) == .seconds(1))
        #expect(ShortTransientRetry.delay(beforeAttempt: 2, jitter: 0.2) == .milliseconds(600))
        #expect(ShortTransientRetry.delay(beforeAttempt: 3, jitter: 0.2) == .milliseconds(1_200))
    }

    @Test func liveJitterStaysBelowAQuarter() {
        for _ in 0..<200 {
            let jitter = ShortTransientRetry.Options.live.jitter()
            #expect(jitter >= 0 && jitter < 0.25)
        }
    }

    /// 等待：睡眠被取消＝`.cancelled`；其他睡眠錯誤＝丟觸發這次重試的原錯誤（Codex R4-1）
    @Test func waitMapsSleepErrors() async {
        let failing = CancellableSleeper()
        failing.lock.withLock { failing.failure = SleepFailure() }
        await #expect(throws: EchoRequestError.remote(.busy)) {
            try await ShortTransientRetry.wait(beforeAttempt: 2, after: .remote(.busy), failing.options)
        }
        let cancelling = CancellableSleeper()
        cancelling.lock.withLock { cancelling.failure = CancellationError() }
        await #expect(throws: EchoRequestError.cancelled) {
            try await ShortTransientRetry.wait(beforeAttempt: 2, after: .remote(.busy), cancelling.options)
        }
        let ok = CancellableSleeper()
        try? await ShortTransientRetry.wait(beforeAttempt: 3, after: .remote(.rateLimited), ok.options)
        #expect(ok.durations == [.seconds(1)])
    }
}
