import AppKit
import Foundation
import SpikeCore

// B4（手動操作後的狀態讀取）與 B6（Azathoth 換歌偵測延遲）。sprint-0-detail.md §4.3.1、§4.5。
@MainActor
extension Experiments {
    static let b4GiveUp: TimeInterval = 10
    static let maxInvalidPerItem = 10

    // MARK: B4

    struct B4Record: Encodable {
        let interval: Double
        let events: [B4Event]
        let invalidSamples: Int
    }

    /// 判定事件＝手動暫停 10、手動按下一首 10；暫停後由工具送 playpause 復位（不判定）
    static func b4(interval: Double, useMouse: Bool) async -> Bool {
        await run("b4-\(Int(interval * 1000))ms", budget: .b4) { session in
            let (oracle, identity) = try await prepare(session)
            try await resetToStart(session, oracle: oracle)
            let pump = EventPump()
            pump.startNotifications()
            if useMouse { pump.startMouse() }
            defer { pump.stop() }
            try await waitForMusicFrontmost(pump)
            var events: [B4Event] = []
            var invalid = 0
            let plan = Array(repeating: "暫停", count: 10) + Array(repeating: "下一首", count: 10)
            var index = 0
            while index < plan.count {
                guard invalid <= maxInvalidPerItem else { throw Session.Stop.precondition("無效樣本過多") }
                let action = plan[index]
                let expectation = try b4Expectation(session, action: action, oracle: oracle, identity: identity)
                print("[\(index + 1)/20] 請在 Music 按「\(action)」一次", useMouse ? "" : "（先按 Enter，再立刻去按）")
                // 無效（前置條件不成立）＝記數並重做同一個樣本，不跳過（§4.3.1）
                guard let event = await observe(session, pump: pump, useMouse: useMouse, interval: interval,
                                                accept: expectation) else {
                    invalid += 1
                    // 無效的那一下可能仍按到了按鈕：先由工具把前態恢復成播放，再請使用者重按
                    try await ensurePlaying(session)
                    try await waitForMusicFrontmost(pump)
                    print("這一次無效（按下時 Music 不在最前面），請再按一次")
                    continue
                }
                events.append(event)
                if action == "暫停" { _ = try await session.command { session.bridge.playPause() } }
                index += 1
            }
            print("B4 判定：", B4Verdict.judge(events).rawValue)
            return [B4Record(interval: interval, events: events, invalidSamples: invalid)]
        }
    }

    /// 從終端機啟動時最前面的是終端機：先等使用者把 Music 叫到前景，否則第一下會被當成無效（2026-10-15 實測）
    private static func waitForMusicFrontmost(_ pump: EventPump) async throws {
        var prompted = false
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != MusicBridge.bundleIdentifier {
            guard !Session.interruptRequested else { throw Session.Stop.userAborted }
            if !prompted {
                print("請先點一下 Music 視窗的空白處（不要點按鈕），讓 Music 到最前面")
                prompted = true
            }
            pump.pump(0.1)
        }
        pump.pump(0.3)
    }

    private static func b4Expectation(_ session: Session, action: String, oracle: PlaybackOracle,
                                      identity: String) throws -> (String?, PlayerStateValue) -> Bool {
        try assertContext(session, identity: identity)
        let current = session.bridge.currentTrackID().value
        guard session.bridge.state().value == .playing else { throw Session.Stop.precondition("前態不是播放中") }
        if action == "暫停" { return { $0 == current && $1 == .paused } }
        let next = current.flatMap(oracle.expectedNext)
        return { id, _ in id == next }
    }

    /// 起點＝提示後第一次左鍵按下（Music 在前景）或按 Enter；終點＝通知或輪詢讀到期待狀態。無效回 nil。
    private static func observe(_ session: Session, pump: EventPump, useMouse: Bool, interval: Double,
                                accept: (String?, PlayerStateValue) -> Bool) async -> B4Event? {
        let mark = Mach.now()
        var start: UInt64?
        if !useMouse {
            _ = readLine()
            start = Mach.now()
        }
        var lastPoll = Mach.now()
        let deadline = Date(timeIntervalSinceNow: b4GiveUp + 30)
        while Date() < deadline, !Session.interruptRequested {
            pump.pump()
            if start == nil, let click = pump.firstClick(after: mark) {
                guard click.musicFrontmost else { return nil }
                start = click.at
            }
            guard let begun = start else { continue }
            let notified = pump.notifications(after: max(begun, lastPoll)).contains { !$0.stopped }
            let pollDue = Mach.seconds(Mach.now()) - Mach.seconds(lastPoll) >= interval
            guard notified || pollDue else { continue }
            lastPoll = Mach.now()
            if accept(session.bridge.currentTrackID().value, session.bridge.state().value) {
                return B4Event(start: Mach.seconds(begun), detectedAt: Mach.seconds(Mach.now()),
                               startSource: useMouse ? .mouseDown : .enterKey, trigger: notified ? .notification : .poll)
            }
            if Mach.seconds(Mach.now()) - Mach.seconds(begun) > b4GiveUp {
                return B4Event(start: Mach.seconds(begun), detectedAt: nil,
                               startSource: useMouse ? .mouseDown : .enterKey, trigger: nil)
            }
        }
        return nil
    }
}
