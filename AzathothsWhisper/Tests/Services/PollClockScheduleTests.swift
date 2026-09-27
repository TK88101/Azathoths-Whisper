import Foundation
import Testing

@testable import AzathothsWhisper

// 「等一段時間、沒被取消才執行」的唯一實作（2026-09-27 simcodex 遺留 P2，使用者裁定合併）：
// LyricsFlow 的升回與 Batch 成功後切回 Editor 分頁共用
@MainActor
@Suite("PollClock.schedule")
struct PollClockScheduleTests {
    @MainActor
    final class Counter {
        var fired = 0
    }

    @Test func runsTheActionAfterTheDelay() async {
        let clock = GatedPollClock()
        let counter = Counter()

        let task = clock.schedule(after: .seconds(3)) { counter.fired += 1 }
        await clock.waitUntilPending(1)
        #expect(counter.fired == 0, "到期前不執行")
        #expect(await clock.requested == [.seconds(3)])

        await clock.releaseAll()
        await task.value

        #expect(counter.fired == 1)
    }

    @Test func cancellingBeforeTheDelaySkipsTheAction() async {
        let clock = GatedPollClock()
        let counter = Counter()

        let task = clock.schedule(after: .seconds(3)) { counter.fired += 1 }
        await clock.waitUntilPending(1)
        task.cancel()
        await clock.releaseAll()
        await task.value

        #expect(counter.fired == 0)
    }
}
