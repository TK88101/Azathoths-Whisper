import Foundation
import Testing
@testable import yse_spike

// EventPump 在 swift-testing runner 中能可靠驗證的部分。投遞 AppKit 事件與分散式通知的檢查
// 在 runner 程序中行為與 CLI 不同（2026-10-15 實測），改由 `yse-spike pumpcheck`＋test_pumpcheck.py 在真正的 CLI 程序裡驗。
@MainActor
@Suite(.serialized)
struct EventPumpTests {
    @Test func pumpWithoutEventsReturnsAroundItsDeadline() {
        let pump = EventPump(notificationName: PumpCheck.selfName)
        let started = Date()
        pump.pump(0.05)
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed >= 0.04 && elapsed < 0.5)
    }

    @Test func stopRemovesTheClickMonitor() {
        let pump = EventPump(notificationName: PumpCheck.selfName)
        pump.startMouse()
        #expect(pump.isMonitoringClicks)
        pump.stop()
        #expect(!pump.isMonitoringClicks)
    }
}
