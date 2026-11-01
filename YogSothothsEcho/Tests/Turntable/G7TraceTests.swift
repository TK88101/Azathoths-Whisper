import Foundation
import Testing

@testable import YogSothothsEcho

// CR-039 階段 A（yse-g7-hitch-fix.md v0.4 §4.4）：G7 signpost——每次轉場一個 interval、相位 event、end 冪等

@MainActor
final class SpyG7Sink: G7TraceSink {
    private(set) var log: [String] = []
    func begin(_ id: UInt64) { log.append("begin \(id)") }
    func phase(_ id: UInt64, _ name: String) { log.append("phase \(id) \(name)") }
    func end(_ id: UInt64) { log.append("end \(id)") }
}

/// 轉場值與 trace 一起推進的小 harness（每次變更都交給 trace 比對前後值）
@MainActor
private struct Harness {
    let sink: SpyG7Sink
    let trace: G7Trace
    var swipe = SwipeTransition(displayScale: 2)

    init() {
        let sink = SpyG7Sink()
        self.sink = sink
        trace = G7Trace(sink: sink)
    }

    mutating func step(_ change: (inout SwipeTransition) -> Void) {
        let old = swipe
        change(&swipe)
        trace.observe(from: old, to: swipe)
    }

    /// 拖過閾值並送出（進入 lifting）
    mutating func send() {
        step { $0.dragChanged(CGSize(width: -5, height: 0)) }
        step { _ = $0.dragEnded(CGSize(width: -80, height: 0), canSend: true, reduceMotion: false) }
    }
}

@MainActor
struct G7TraceTests {
    /// 正常完成（newAlbum）：一次 begin、每個相位一個 event（lifting 的 ready 變化不重複）、回 idle 一次 end，ID 一致
    @Test func fullTransitionIsOneIntervalWithPhaseEvents() {
        var h = Harness()
        h.send()
        h.step { _ = $0.ready() }
        h.step { $0.decide(.newAlbum) }
        for _ in 0..<5 { h.step { _ = $0.timerFinished() } }
        #expect(h.swipe.phase == .idle)
        #expect(h.sink.log == ["begin 1", "phase 1 lifting", "phase 1 clearing", "phase 1 sheathing", "phase 1 exchanging",
                               "phase 1 drawing", "phase 1 placing", "end 1"])
    }

    /// 取消（關唱機／斷線都走 cancel）：end 一次；重複取消不再 end；下一次轉場是新 ID
    @Test func cancelEndsOnceAndIsIdempotent() {
        var h = Harness()
        h.send()
        h.step { $0.cancel() }
        h.step { $0.cancel() }
        h.send()
        #expect(h.sink.log == ["begin 1", "phase 1 lifting", "end 1", "begin 2", "phase 2 lifting"])
    }

    /// 拖動、回彈不是轉場：不發 signpost
    @Test func draggingAndReturningAreNotTraced() {
        var h = Harness()
        h.step { $0.dragChanged(CGSize(width: -5, height: 0)) }
        h.step { _ = $0.dragEnded(CGSize(width: -10, height: 0), canSend: true, reduceMotion: false) }
        h.step { _ = $0.timerFinished() }
        #expect(h.swipe.phase == .idle)
        #expect(h.sink.log.isEmpty)
    }
}
