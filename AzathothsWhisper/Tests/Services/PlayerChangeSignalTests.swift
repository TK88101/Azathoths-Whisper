import Foundation
import Testing

@testable import AzathothsWhisper

// F1 系統邊界（計劃 2026-09-27-coverflow-f1-f2 §3.1、§4 10–12）。
// 一律用本測試專屬的通知名：絕不 post Music 的通知名（使用者機上其他監聽者會收到）
@MainActor
@Suite("PlayerChangeSignal")
struct PlayerChangeSignalTests {
    private static func uniqueName() -> Notification.Name {
        Notification.Name("com.ibridgezhao.azathothswhisper.tests.playerChange.\(UUID().uuidString)")
    }

    private static func post(_ name: Notification.Name, userInfo: [AnyHashable: Any]? = ["Player State": "Playing"]) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: userInfo, deliverImmediately: true
        )
    }

    /// distributed 通知是非同步送達：有界等待條件成立（主執行緒 run loop 要轉起來才會送達）
    private static func waitDelivered(_ condition: () -> Bool, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func liveSignalCallsBackOnThePostedName() async {
        let name = Self.uniqueName()
        let signal = MusicPlayerInfoSignal(name: name)
        var calls = 0
        signal.start { calls += 1 }
        defer { signal.stop() }

        Self.post(name)

        #expect(await Self.waitDelivered { calls == 1 })
    }

    @Test func stopRemovesTheObserver() async {
        let stoppedName = Self.uniqueName()
        let sentinelName = Self.uniqueName()
        let stopped = MusicPlayerInfoSignal(name: stoppedName)
        let sentinel = MusicPlayerInfoSignal(name: sentinelName)
        var stoppedCalls = 0
        var sentinelCalls = 0
        stopped.start { stoppedCalls += 1 }
        sentinel.start { sentinelCalls += 1 }
        defer { sentinel.stop() }

        stopped.stop()
        Self.post(stoppedName)
        Self.post(sentinelName)

        // 後發的哨兵已送達 → 先發的那則若會送達也已送達
        #expect(await Self.waitDelivered { sentinelCalls == 1 })
        #expect(stoppedCalls == 0)
    }

    @Test func startIsIdempotentAndRestartable() async {
        let name = Self.uniqueName()
        let signal = MusicPlayerInfoSignal(name: name)
        var calls = 0
        signal.start { calls += 1 }
        signal.start { calls += 1 }
        Self.post(name)
        #expect(await Self.waitDelivered { calls >= 1 })
        // 再以一則後發的通知界定：若重複註冊，第一則會回呼兩次
        Self.post(name)
        #expect(await Self.waitDelivered { calls >= 2 })
        #expect(calls == 2, "start 兩次不得重複註冊")

        signal.stop()
        signal.start { calls += 10 }
        defer { signal.stop() }
        Self.post(name)
        #expect(await Self.waitDelivered { calls == 12 }, "stop 後再 start 照常回呼一次")
    }

    /// U3（計劃 §10，Codex＋Jev 裁決 A）：在清單中點歌時 Music 先送 `Stopped`，那一刻讀會讀到「沒在播」。
    /// 只丟明確的 `Stopped`；其餘一律放行（失敗放行：格式漂移不得讓換歌默默退回 3 秒輪詢）
    @Test func aStoppedNotificationDoesNotTriggerARead() async {
        let name = Self.uniqueName()
        let signal = MusicPlayerInfoSignal(name: name)
        var calls = 0
        signal.start { calls += 1 }
        defer { signal.stop() }

        Self.post(name, userInfo: ["Player State": "Stopped"])
        Self.post(name, userInfo: ["Player State": "Playing"])     // 後發的哨兵

        #expect(await Self.waitDelivered { calls >= 1 })
        #expect(calls == 1, "Stopped 不觸發，只有後面的 Playing 觸發")
    }

    @Test("非 Stopped 或讀不懂的通知一律觸發", arguments: [
        "Paused", "Playing", "stopped", "missing", "notAString", "noUserInfo",
    ])
    func everyOtherNotificationTriggersARead(kind: String) async {
        let name = Self.uniqueName()
        let signal = MusicPlayerInfoSignal(name: name)
        var calls = 0
        signal.start { calls += 1 }
        defer { signal.stop() }

        let userInfo: [AnyHashable: Any]? = switch kind {
        case "missing": ["Name": "x"]
        case "notAString": ["Player State": 1]
        case "noUserInfo": nil
        default: ["Player State": kind]
        }
        Self.post(name, userInfo: userInfo)

        #expect(await Self.waitDelivered { calls == 1 }, "\(kind) 應觸發讀取")
    }

    @Test func noopSignalNeverCallsBack() {
        let signal = NoopPlayerChangeSignal()
        var calls = 0
        signal.start { calls += 1 }
        signal.stop()
        #expect(calls == 0)
    }
}
