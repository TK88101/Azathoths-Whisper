import Foundation
import Testing

@testable import YogSothothsEcho

// CR-039 階段 A（yse-g7-hitch-fix.md v0.4 §4.1／§4.4）：唱片計時器依相位停表、凍結角度共讀、G7 signpost

struct RecordTimelinePolicyTests {
    private static let allPhases: [SwipeTransition.Phase] = [
        .idle, .ignoringVertical, .dragging(dx: -20), .returning,
        .lifting(.next, ready: false), .lifting(.previous, ready: true), .awaiting(.next),
        .relabeling, .crossfading,
        .clearing(.next), .sheathing(.next), .exchanging(.next), .drawing(.next), .placing(.next),
    ]

    /// 播放中：唱片還在轉（含煞停中的 lifting、Reduce Motion 的 crossfading）才 tick；煞停後的相位停表
    @Test func playingTicksOnlyWhileTheRecordMoves() {
        for phase in Self.allPhases {
            let expected: Bool
            switch phase {
            case .idle, .ignoringVertical, .dragging, .returning, .lifting, .crossfading: expected = true
            case .awaiting, .relabeling, .clearing, .sheathing, .exchanging, .drawing, .placing: expected = false
            }
            #expect(RecordTimelinePolicy.needsTicks(isPlaying: true, phase: phase, reduceMotion: false) == expected, "\(phase)")
        }
    }

    /// Reduce Motion 不煞停（armLifted＝false）：播放中所有相位都 tick，awaiting 也不能停在半空
    @Test func reduceMotionNeverFreezesAPlayingRecord() {
        for phase in Self.allPhases {
            #expect(RecordTimelinePolicy.needsTicks(isPlaying: true, phase: phase, reduceMotion: true), "\(phase)")
        }
    }

    @Test func notPlayingNeverTicks() {
        for phase in Self.allPhases {
            for reduceMotion in [false, true] {
                #expect(!RecordTimelinePolicy.needsTicks(isPlaying: false, phase: phase, reduceMotion: reduceMotion), "\(phase)")
            }
        }
    }

    /// render 分支：不 tick 且有靜止角＝讀靜止角、不呼叫有副作用的即時角；其餘走即時角
    @Test func displayAngleUsesRestingAngleWithoutTouchingTheLiveSource() {
        var liveCalls = 0
        let frozen = RecordTimelinePolicy.displayAngle(needsTicks: false, resting: 42) { liveCalls += 1; return 7 }
        #expect(frozen == 42 && liveCalls == 0)
        #expect(RecordTimelinePolicy.displayAngle(needsTicks: true, resting: 42) { liveCalls += 1; return 7 } == 7)
        // 停表但沒有靜止角（例如剛按暫停、spin 還在轉動狀態）＝退回即時路徑，讓 spin 收斂到 still
        #expect(RecordTimelinePolicy.displayAngle(needsTicks: false, resting: nil) { liveCalls += 1; return 9 } == 9)
        #expect(liveCalls == 2)
    }
}

struct RecordSpinRestingAngleTests {
    @Test func stillRestsAtItsBase() {
        var spin = RecordSpin()
        spin.update(.spinning, at: 0)
        spin.update(.still, at: 2)
        #expect(spin.restingAngle == 36)
    }

    @Test func spinningHasNoRestingAngle() {
        var spin = RecordSpin()
        spin.update(.spinning, at: 0)
        #expect(spin.restingAngle == nil)
    }

    /// 煞停中：靜止角＝煞停 0.35 s 之後任意時刻的角度
    @Test func brakingRestsAtTheBrakeEndAngle() {
        var spin = RecordSpin()
        spin.update(.spinning, at: 0)
        spin.update(.braking, at: 1)
        let resting = spin.restingAngle
        #expect(resting != nil)
        for t in [1.35, 1.4, 3, 100] {
            #expect(abs(spin.angle(at: t) - resting!) < 1e-9, "t \(t)")
        }
    }

    /// 恢復轉動：從靜止角接續（角度連續），之後 18°/s
    @Test func resumingContinuesFromTheRestingAngle() {
        var spin = RecordSpin()
        spin.update(.spinning, at: 0)
        spin.update(.braking, at: 1)
        let resting = spin.restingAngle!
        spin.update(.spinning, at: 5)
        #expect(abs(spin.angle(at: 5) - resting) < 1e-9)
        #expect(abs(spin.angle(at: 6) - (resting + RecordSpin.degreesPerSecond).truncatingRemainder(dividingBy: 360)) < 1e-9)
    }
}

@MainActor
final class SpyG7Sink: G7TraceSink {
    private(set) var log: [String] = []
    func begin(_ id: UInt64) { log.append("begin \(id)") }
    func phase(_ id: UInt64, _ name: String) { log.append("phase \(id) \(name)") }
    func end(_ id: UInt64) { log.append("end \(id)") }
}

@MainActor
struct G7TraceTests {
    private func sent() -> SwipeTransition {
        var swipe = SwipeTransition(displayScale: 2)
        swipe.dragChanged(CGSize(width: -5, height: 0))
        _ = swipe.dragEnded(CGSize(width: -80, height: 0), canSend: true, reduceMotion: false)
        return swipe
    }

    /// 正常完成（newAlbum）：一次 begin、每個相位一個 event（lifting ready 變化不重複）、回 idle 一次 end，ID 一致
    @Test func fullTransitionIsOneIntervalWithPhaseEvents() {
        let sink = SpyG7Sink(), trace = G7Trace(sink: sink)
        var swipe = SwipeTransition(displayScale: 2)
        func step(_ change: (inout SwipeTransition) -> Void) { let old = swipe; change(&swipe); trace.observe(from: old, to: swipe) }
        step { $0.dragChanged(CGSize(width: -5, height: 0)) }
        step { _ = $0.dragEnded(CGSize(width: -80, height: 0), canSend: true, reduceMotion: false) }
        step { _ = $0.ready() }
        step { $0.decide(.newAlbum) }
        for _ in 0..<5 { step { _ = $0.timerFinished() } }
        #expect(swipe.phase == .idle)
        #expect(sink.log == ["begin 1", "phase 1 lifting", "phase 1 clearing", "phase 1 sheathing", "phase 1 exchanging",
                             "phase 1 drawing", "phase 1 placing", "end 1"])
    }

    /// 取消（關唱機／斷線都走 cancel）：end 一次；重複取消不再 end；下一次轉場是新 ID
    @Test func cancelEndsOnceAndIsIdempotent() {
        let sink = SpyG7Sink(), trace = G7Trace(sink: sink)
        var swipe = SwipeTransition(displayScale: 2)
        trace.observe(from: swipe, to: sent())
        swipe = sent()
        var cancelled = swipe
        cancelled.cancel()
        trace.observe(from: swipe, to: cancelled)
        var again = cancelled
        again.cancel()
        trace.observe(from: cancelled, to: again)
        trace.observe(from: again, to: sent())
        #expect(sink.log == ["begin 1", "phase 1 lifting", "end 1", "begin 2", "phase 2 lifting"])
    }

    /// 拖動、回彈不是轉場：不發 signpost
    @Test func draggingAndReturningAreNotTraced() {
        let sink = SpyG7Sink(), trace = G7Trace(sink: sink)
        var swipe = SwipeTransition(displayScale: 2)
        func step(_ change: (inout SwipeTransition) -> Void) { let old = swipe; change(&swipe); trace.observe(from: old, to: swipe) }
        step { $0.dragChanged(CGSize(width: -5, height: 0)) }
        step { _ = $0.dragEnded(CGSize(width: -10, height: 0), canSend: true, reduceMotion: false) }
        step { _ = $0.timerFinished() }
        #expect(swipe.phase == .idle)
        #expect(sink.log.isEmpty)
    }
}
