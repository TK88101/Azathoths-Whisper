import AppKit
import Foundation

// 命令列程式沒有 AppKit 事件迴圈：要先建立 NSApplication，再以 nextEvent＋sendEvent 手動分派。
// 2026-10-15 實證：只推 RunLoop 時本程序的 AppKit 事件不會被分派（scratchpad b4probe）；
// 全域滑鼠監聽是否因此收不到仍是推測，修正只算候選，由 mousecheck／B4 現場驗收。
// 只記時間戳（mach_continuous_time），不記座標、按鍵、通知內容以外的任何資料。
@MainActor
final class EventPump {
    static let musicPlayerInfo = Notification.Name("com.apple.Music.playerInfo")

    private(set) var notifications: [(at: UInt64, stopped: Bool)] = []
    private(set) var clicks: [(at: UInt64, musicFrontmost: Bool)] = []
    private var observer: NSObjectProtocol?
    private var mouseMonitor: Any?
    private let notificationName: Notification.Name

    var isMonitoringClicks: Bool { mouseMonitor != nil }

    /// 量測時聽 Music 的 playerInfo；測試改聽自訂名稱
    init(notificationName: Notification.Name = EventPump.musicPlayerInfo) {
        self.notificationName = notificationName
        // .prohibited：不出 Dock 圖示、不搶前景
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    func startNotifications() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName, object: nil, queue: nil
        ) { [weak self] note in
            let stopped = (note.userInfo?["Player State"] as? String) == "Stopped"
            MainActor.assumeIsolated { self?.notifications.append((Mach.now(), stopped)) }
        }
    }

    /// 經使用者同意才呼叫；只聽左鍵按下，不攔截、不模擬。
    /// 前景檢查不在這裡做：2026-10-15 實測回呼內讀 frontmostApplication 恆為非 Music（Music 確在最前面），
    /// 改由出題前確認 Music 在前景（B4 waitForMusicFrontmost）。點錯地方的後果是該筆讀不到期待狀態＝未達標，偏保守。
    func startMouse() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.clicks.append((Mach.now(), true)) }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        observer = nil
        mouseMonitor = nil
    }

    /// 推動一小段：deadline 前分派所有排隊的 AppKit 事件；無事件時等到 deadline。
    /// 分散式通知由 nextEvent 內部跑 run loop（.default mode，CLI 工具的限制）送達。
    func pump(_ seconds: TimeInterval = 0.01) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while Date() < deadline,
              let event = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }

    func notifications(after mark: UInt64) -> [(at: UInt64, stopped: Bool)] {
        notifications.filter { $0.at > mark }
    }

    func clickCount(after mark: UInt64) -> Int {
        clicks.filter { $0.at > mark }.count
    }

    func firstClick(after mark: UInt64) -> (at: UInt64, musicFrontmost: Bool)? {
        clicks.first { $0.at > mark }
    }
}
