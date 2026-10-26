import AppKit
import Foundation
import Testing

// 每條測試寫的是「CLI 程序中成立的行為」（scratchpad b4probe/p2、p3 實測）。
// 在 swift-testing runner 中若紅或 runner 中途退出，即重現了 T1 偏離的前提。
// 預期失敗模式（2026-10-15，macOS 27.0.1／Xcode 27.0／Swift 6.4）：見 s0-offline-2026-10-15.md「runner 最小重現」。
@MainActor
@Suite(.serialized)
struct RunnerAppKitTests {
    @Test func appKitEventPostedToSelfIsDispatchedByNextEvent() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var seen = 0
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { event in
            seen += 1
            return event
        }
        defer { monitor.map(NSEvent.removeMonitor) }
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: 0x5953, data1: 0, data2: 0)
        NSApp.postEvent(event!, atStart: false)
        let deadline = Date(timeIntervalSinceNow: 0.2)
        while Date() < deadline,
              let next = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
            NSApp.sendEvent(next)
        }
        FileHandle.standardError.write(Data("repro: dispatched \(seen)\n".utf8))
        #expect(seen == 1)
    }

    @Test func distributedNotificationToSelfArrivesWithinThreeSeconds() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let name = Notification.Name("yse-repro.selftest")
        var got = false
        let observer = DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { got = true }
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        let deadline = Date(timeIntervalSinceNow: 3)
        while !got, Date() < deadline {
            if let next = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.05), inMode: .default,
                                          dequeue: true) { NSApp.sendEvent(next) }
        }
        #expect(got)
    }
}
