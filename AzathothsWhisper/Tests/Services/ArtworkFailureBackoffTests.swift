import Foundation
import Testing

@testable import AzathothsWhisper

// 取圖失敗的退避（M7 P2-2）。時間全部由測試給定，不依賴真實時鐘。
@Suite("ArtworkFailureBackoff")
struct ArtworkFailureBackoffTests {
    @Test func neverFailedIDIsDue() {
        let backoff = ArtworkFailureBackoff()
        #expect(backoff.isDue("PID1", now: 0))
    }

    @Test func notDueBeforeRetryAfter() {
        var backoff = ArtworkFailureBackoff()
        backoff.record("PID1", now: 100)

        #expect(!backoff.isDue("PID1", now: 100 + ArtworkFailureBackoff.baseDelay - 0.1))
        #expect(backoff.isDue("PID1", now: 100 + ArtworkFailureBackoff.baseDelay))
    }

    @Test func backoffGrowsExponentiallyAndCaps() {
        #expect(ArtworkFailureBackoff.delay(forCount: 1) == 5)
        #expect(ArtworkFailureBackoff.delay(forCount: 2) == 10)
        #expect(ArtworkFailureBackoff.delay(forCount: 3) == 20)
        #expect(ArtworkFailureBackoff.delay(forCount: 7) == ArtworkFailureBackoff.maxDelay)
    }

    /// 長期失敗不得讓指數溢位——先 clamp 再取冪
    @Test func countIsSaturatedAtCap() {
        var backoff = ArtworkFailureBackoff()
        for step in 0..<1000 { backoff.record("PID1", now: TimeInterval(step) * 1000) }

        #expect(ArtworkFailureBackoff.delay(forCount: 1000) == ArtworkFailureBackoff.maxDelay)
        #expect(ArtworkFailureBackoff.delay(forCount: 1000).isFinite)
        #expect(!backoff.isDue("PID1", now: 999_000 + 1))
        #expect(backoff.isDue("PID1", now: 999_000 + ArtworkFailureBackoff.maxDelay))
    }

    @Test func successClearsFailure() {
        var backoff = ArtworkFailureBackoff()
        backoff.record("PID1", now: 0)
        // `#expect` 巨集把表達式拆成閉包，mutating 方法不能直接寫在裡面
        let wasRecovery = backoff.recordSuccess("PID1")
        #expect(wasRecovery, "先前失敗過＝這次是恢復")
        #expect(backoff.isDue("PID1", now: 0), "成功後須立即恢復可取")
    }

    /// 從未失敗過的成功不是「恢復」——呼叫端本來就從回傳值拿到圖，不需要被通知
    @Test func successWithoutPriorFailureIsNotRecovery() {
        var backoff = ArtworkFailureBackoff()
        let wasRecovery = backoff.recordSuccess("PID1")
        #expect(!wasRecovery)
    }

    /// 連續兩次成功只有第一次算恢復
    @Test func recoveryIsReportedOnlyOnce() {
        var backoff = ArtworkFailureBackoff()
        backoff.record("PID1", now: 0)
        let first = backoff.recordSuccess("PID1")
        let second = backoff.recordSuccess("PID1")
        #expect(first)
        #expect(!second)
    }

    /// 清除後重新失敗要從頭算，否則一次偶發失敗會永久拉高該曲的退避
    @Test func successResetsGrowth() {
        var backoff = ArtworkFailureBackoff()
        backoff.record("PID1", now: 0)
        backoff.record("PID1", now: 0)
        backoff.recordSuccess("PID1")
        backoff.record("PID1", now: 1000)

        #expect(backoff.isDue("PID1", now: 1000 + ArtworkFailureBackoff.baseDelay))
    }

    @Test func recordsAreIndependentPerID() {
        var backoff = ArtworkFailureBackoff()
        backoff.record("PID1", now: 0)
        #expect(backoff.isDue("PID2", now: 0))
    }
}
