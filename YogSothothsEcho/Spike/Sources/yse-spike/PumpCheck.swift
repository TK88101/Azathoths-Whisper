import AppKit
import Foundation

// EventPump 分派語意的自檢（s0-offline-2026-10-15.md T1）。不碰 Music、不模擬滑鼠鍵盤：
// 只對本程序投遞 applicationDefined 事件、收自己或外部（test_pumpcheck.py）發的分散式通知。
// 放在真正的 CLI 程序裡跑，是因為 swift-testing 的 runner 程序中 AppKit 事件與分散式通知的行為
// 與 CLI 不同（2026-10-15 實測：runner 會在投遞事件的測試後退出、自發通知收不到；原因 TBD）。
@MainActor
enum PumpCheck {
    static let selfName = Notification.Name("yse-spike.selftest")
    static let externalName = Notification.Name("yse-spike.selftest.external")
    private static let eventSubtype: Int16 = 0x5953

    static func run() -> Bool {
        let results = [
            ("single-event", countDispatched(posting: 1) == 1),
            ("all-queued-events", countDispatched(posting: 3) == 3),
            ("idle-deadline", idleReturnsNearDeadline()),
            ("busy-deadline", busyReturnsByDeadline()),
            ("self-notification", selfNotificationArrives()),
            ("external-notification", externalNotificationArrives()),
        ]
        for (name, passed) in results { print(passed ? "ok" : "FAIL", name) }
        return results.allSatisfy(\.1)
    }

    private static func post() {
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: eventSubtype, data1: 0, data2: 0)
        if let event { NSApp.postEvent(event, atStart: false) }
    }

    private static func countDispatched(posting count: Int) -> Int {
        let pump = EventPump(notificationName: selfName)
        var seen = 0
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { event in
            seen += 1
            return event
        }
        defer { monitor.map(NSEvent.removeMonitor) }
        (0..<count).forEach { _ in post() }
        pump.pump(0.2)
        return seen
    }

    private static func idleReturnsNearDeadline() -> Bool {
        let pump = EventPump(notificationName: selfName)
        let started = Date()
        pump.pump(0.05)
        let elapsed = Date().timeIntervalSince(started)
        return elapsed >= 0.04 && elapsed < 0.5
    }

    /// 每分派一個就再投一個：事件永不間斷時 pump 仍要在 deadline 附近返回
    private static func busyReturnsByDeadline() -> Bool {
        let pump = EventPump(notificationName: selfName)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { event in
            post()
            return event
        }
        defer {
            monitor.map(NSEvent.removeMonitor)
            while NSApp.nextEvent(matching: .applicationDefined, until: Date(), inMode: .default, dequeue: true) != nil {}
        }
        post()
        let started = Date()
        pump.pump(0.05)
        return Date().timeIntervalSince(started) < 0.5
    }

    private static func selfNotificationArrives() -> Bool {
        let pump = EventPump(notificationName: selfName)
        pump.startNotifications()
        defer { pump.stop() }
        let mark = Mach.now()
        DistributedNotificationCenter.default().postNotificationName(selfName, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        return waitForNotification(pump, after: mark, seconds: 3)
    }

    /// 印出 READY 後等外部程序發通知（由 test_pumpcheck.py 發）
    private static func externalNotificationArrives() -> Bool {
        let pump = EventPump(notificationName: externalName)
        pump.startNotifications()
        defer { pump.stop() }
        let mark = Mach.now()
        print("READY external", externalName.rawValue)
        fflush(stdout)
        return waitForNotification(pump, after: mark, seconds: 15)
    }

    private static func waitForNotification(_ pump: EventPump, after mark: UInt64, seconds: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while pump.notifications(after: mark).isEmpty, Date() < deadline { pump.pump(0.05) }
        return pump.notifications(after: mark).count == 1
    }
}

// mousecheck：使用者在場時 15 秒內點一下，確認全域左鍵監聽是否收得到（B4 修復候選的現場驗收）
@MainActor
enum MouseCheck {
    static let consentFlag = "--consent-click-monitor"
    static let duration: TimeInterval = 15

    static func run(arguments: [String]) -> Bool {
        guard arguments.contains(consentFlag) else {
            print("mousecheck 會在 \(Int(duration)) 秒內監聽全域左鍵按下（只記次數，不記座標與內容）。同意請加 \(consentFlag)")
            return false
        }
        print("接下來 \(Int(duration)) 秒監聽左鍵按下，只記次數與時間，不記座標與內容。請在任意視窗點一下。")
        let pump = EventPump()
        pump.startMouse()
        defer { pump.stop() }
        let mark = Mach.now()
        let deadline = Date(timeIntervalSinceNow: duration)
        while Date() < deadline, !Session.interruptRequested { pump.pump(0.05) }
        let count = pump.clickCount(after: mark)
        print("收到左鍵按下 \(count) 次")
        return count > 0
    }
}
