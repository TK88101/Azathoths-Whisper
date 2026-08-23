import Foundation
import Testing

@testable import AzathothsWhisper

// LyricsGate 的語義鎖定（A2）。
// 背景：2026-08-23 A1 查明單槽 continuation 是 test run 掛死的根因，
// 見 docs/plans/2026-08-23-m6-closeout.md 附錄。這組測試把修復後的 broadcast
// 語義釘住，防止日後有人改回單槽。
@Suite("LyricsGate")
struct LyricsGateTests {
    /// 核心修復：兩個等待者，open() 後**兩者皆推進**（原實作只會放行後者）
    @Test func gateResumesAllWaiters() async {
        let gate = LyricsGate()
        let firstDone = Atomic()
        let secondDone = Atomic()

        let first = Task { await gate.wait(); await firstDone.set() }
        let second = Task { await gate.wait(); await secondDone.set() }

        // 讓兩個等待者都確實註冊進 gate
        await settle()
        await gate.open()

        await first.value
        await second.value
        #expect(await firstDone.value, "第一個等待者必須被喚醒（原單槽實作在此永久掛起）")
        #expect(await secondDone.value)
    }

    @Test func gateReturnsImmediatelyAfterOpen() async {
        let gate = LyricsGate()
        await gate.open()
        await gate.wait()   // 掛住即為失敗（外部 timeout 捕捉）
    }

    /// 重複 open() 不得重放已 resume 的 continuation（重複 resume 會 fatalError 殺 host）
    @Test func repeatedOpenDoesNotDoubleResume() async {
        let gate = LyricsGate()
        let task = Task { await gate.wait() }
        await settle(50)

        await gate.open()
        await gate.open()
        await gate.open()

        await task.value
    }

    /// 等待中的 Task 被取消後，gate 仍須正常放行其餘等待者
    @Test func cancelledWaiterDoesNotHangGate() async {
        let gate = LyricsGate()
        let survivorDone = Atomic()

        let cancelled = Task { await gate.wait() }
        let survivor = Task { await gate.wait(); await survivorDone.set() }
        await settle()

        cancelled.cancel()
        await gate.open()

        await survivor.value
        #expect(await survivorDone.value, "取消其中一個等待者不得影響其餘等待者")
    }
}

/// 跨 Task 邊界的布林旗標（測試用）
actor Atomic {
    private(set) var value = false
    func set() { value = true }
}
