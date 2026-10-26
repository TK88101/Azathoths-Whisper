import Foundation
import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// S4 T11（sprint-4-detail.md §4.8；D3）：進度補間與亂序丟棄。錨點＝收到事件的本機單調時鐘；sampledAt 只用來排序

private func event(_ state: PlaybackState, position: Double, duration: Double? = 200, at sampledAt: Double = 0) -> PlaybackEvent {
    PlaybackEvent(availability: .ok, trackID: "0000000000000001", albumID: nil, state: state, position: position,
                  duration: duration, sampledAt: sampledAt)
}

struct PlaybackClockTests {
    @Test func playingAdvancesFromReceiptTime() {
        let clock = PlaybackClock(event: event(.playing, position: 10), receivedAt: 100)
        #expect(clock.position(at: 100) == 10)
        #expect(clock.position(at: 102.5) == 12.5)
    }

    @Test func pausedAndStoppedDoNotAdvance() {
        #expect(PlaybackClock(event: event(.paused, position: 10), receivedAt: 100).position(at: 160) == 10)
        #expect(PlaybackClock(event: event(.stopped, position: 0), receivedAt: 100).position(at: 160) == 0)
    }

    @Test func clampedToDurationAndZero() {
        #expect(PlaybackClock(event: event(.playing, position: 199), receivedAt: 0).position(at: 5) == 200)
        #expect(PlaybackClock(event: event(.playing, position: -3), receivedAt: 0).position(at: 1) == 0)
        // 本機時鐘不會倒退，但呼叫端給了較早的時刻也不得倒退到錨點之前
        #expect(PlaybackClock(event: event(.playing, position: 10), receivedAt: 100).position(at: 90) == 10)
    }

    @Test func unknownDurationHasNoUpperBound() {
        #expect(PlaybackClock(event: event(.playing, position: 500, duration: nil), receivedAt: 0).position(at: 100) == 600)
    }

    @Test func olderOrEqualSampleIsDiscarded() {
        var ordering = PlaybackOrdering()
        let admitted = [10.0, 9, 10, 11].map { ordering.admits(event(.playing, position: 1, at: $0)) }
        #expect(admitted == [true, false, false, true])
    }

    /// Mac 重啟後單調鐘變小：新連線時重置基準，否則永遠丟棄（Codex 第 1 輪 P2-20）
    @Test func resetAcceptsSmallerSampleAfterReconnect() {
        var ordering = PlaybackOrdering()
        let first = ordering.admits(event(.playing, position: 1, at: 5000))
        ordering.reset()
        let afterReset = ordering.admits(event(.playing, position: 1, at: 3))
        #expect(first && afterReset)
    }
}
