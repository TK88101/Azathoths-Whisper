import Foundation
import Testing

@testable import AzathothsWhisper

// GatedPollClock 的語義鎖定：`sleep` 掛起直到測試放行；可取消；記錄每次請求的時長。
// 用途：驗「到期前」與「到期時」兩個時點（例如寫入成功後的升回延遲），ImmediateClock 做不到。
@Suite("GatedPollClock")
struct GatedPollClockTests {
    @Test func sleepSuspendsUntilReleased() async throws {
        let clock = GatedPollClock()
        let woke = Atomic()
        let task = Task {
            try await clock.sleep(for: .seconds(3))
            await woke.set()
        }
        await clock.waitUntilPending(1)
        await settle()
        #expect(await !woke.value, "放行前不得醒來")

        await clock.releaseAll()
        try await task.value
        #expect(await woke.value)
    }

    @Test func recordsRequestedDurationsInOrder() async throws {
        let clock = GatedPollClock()
        let first = Task { try await clock.sleep(for: .milliseconds(100)) }
        await clock.waitUntilPending(1)
        let second = Task { try await clock.sleep(for: .seconds(2)) }
        await clock.waitUntilPending(2)

        #expect(await clock.requested == [.milliseconds(100), .seconds(2)])
        await clock.releaseAll()
        try await first.value
        try await second.value
    }

    @Test func releaseNextWakesOnlyTheOldestSleeper() async throws {
        let clock = GatedPollClock()
        let firstDone = Atomic()
        let secondDone = Atomic()
        let first = Task { try await clock.sleep(for: .seconds(1)); await firstDone.set() }
        await clock.waitUntilPending(1)
        let second = Task { try await clock.sleep(for: .seconds(1)); await secondDone.set() }
        await clock.waitUntilPending(2)

        await clock.releaseNext()
        try await first.value
        await settle()
        #expect(await firstDone.value)
        #expect(await !secondDone.value)

        await clock.releaseAll()
        try await second.value
    }

    /// 對抗覆核 P2：取消後立刻 releaseNext——被取消者不得被「正常喚醒」，放行應落到下一個仍在等的人
    @Test func releaseNextSkipsACancelledSleeper() async throws {
        let clock = GatedPollClock()
        let secondDone = Atomic()
        let first = Task { try await clock.sleep(for: .seconds(1)) }
        await clock.waitUntilPending(1)
        let second = Task { try await clock.sleep(for: .seconds(1)); await secondDone.set() }
        await clock.waitUntilPending(2)

        first.cancel()
        await clock.releaseNext()

        await #expect(throws: CancellationError.self) { try await first.value }
        try await second.value
        #expect(await secondDone.value)
        #expect(await clock.pendingCount == 0)
    }

    @Test func cancellingTheSleeperThrowsCancellationError() async {
        let clock = GatedPollClock()
        let task = Task { try await clock.sleep(for: .seconds(5)) }
        await clock.waitUntilPending(1)

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await clock.pendingCount == 0, "取消後不得殘留等待者")
    }
}
