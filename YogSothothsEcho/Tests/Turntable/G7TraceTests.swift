import Foundation
import Testing

@testable import YogSothothsEcho

// CR-039 階段 A（yse-g7-hitch-fix.md v0.4 §4.4）：G7 signpost——每次轉場一個 interval、相位 event、end 冪等

@MainActor
final class SpyG7Sink: G7TraceSink {
    private(set) var log: [String] = []
    func begin(_ id: UInt64) { log.append("begin \(id)") }
    func phase(_ id: UInt64, _ name: String) { log.append("phase \(id) \(name)") }
    func end(_ id: UInt64, note: String) { log.append(note.isEmpty ? "end \(id)" : "end \(id) \(note)") }
}

/// 轉場觀察者替身（§11 S2：LabelPrintStore 在 G7 begin／end 收到通知，end 回傳 note）
@MainActor
final class SpyG7Observer: G7TransitionObserver {
    private(set) var log: [String] = []
    var note = "misses=0 reasons=absent:0,pending:0,rendering:0,failed:0"
    /// 記下 closed 當下 sink 的最後一筆：用來驗證「signpost end 之後才 closed」（pending 遮罩在 closed 才畫，不算進 G7）
    weak var sink: SpyG7Sink?
    func transitionBegan() { log.append("began") }
    func transitionEnded() -> String { log.append("ended"); return note }
    func transitionClosed() { log.append("closed after \(sink?.log.last ?? "-")") }
}

/// 轉場值與 trace 一起推進的小 harness（每次變更都交給 trace 比對前後值）
@MainActor
private struct Harness {
    let sink: SpyG7Sink
    let trace: G7Trace
    var swipe = SwipeTransition(displayScale: 2)

    init(observer: (any G7TransitionObserver)? = nil) {
        let sink = SpyG7Sink()
        self.sink = sink
        trace = G7Trace(sink: sink, observer: observer)
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

    /// §11 S2：觀察者在 begin 前收到 began、在 end 時給 note（寫進 signpost end）；取消路徑同樣收尾
    @Test func observerIsNotifiedAndEndCarriesNote() {
        let observer = SpyG7Observer()
        var h = Harness(observer: observer)
        observer.sink = h.sink
        h.send()
        #expect(observer.log == ["began"])
        h.step { $0.cancel() }
        let end = "end 1 misses=0 reasons=absent:0,pending:0,rendering:0,failed:0"
        #expect(observer.log == ["began", "ended", "closed after \(end)"])
        #expect(h.sink.log == ["begin 1", "phase 1 lifting", end])
        h.step { $0.cancel() }
        #expect(observer.log == ["began", "ended", "closed after \(end)"])
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
