import Foundation
import Testing

@testable import YogSothothsEcho

// CR-039 階段 A（yse-g7-hitch-fix.md v0.4 §4.1）：唱片計時器依相位停表、靜止角

struct RecordTimelinePolicyTests {
    /// 播放中仍在轉（含煞停中的 lifting、Reduce Motion 的 crossfading）
    private static let moving: [SwipeTransition.Phase] = [
        .idle, .ignoringVertical, .dragging(dx: -20), .returning, .lifting(.next, ready: false), .lifting(.previous, ready: true),
        .crossfading,
    ]
    /// 煞停後：角度已凍結
    private static let frozen: [SwipeTransition.Phase] = [
        .awaiting(.next), .relabeling, .clearing(.next), .sheathing(.next), .exchanging(.next), .drawing(.next), .placing(.next),
    ]

    @Test func playingTicksOnlyWhileTheRecordMoves() {
        for phase in Self.moving { #expect(RecordTimelinePolicy.needsTicks(isPlaying: true, phase: phase, reduceMotion: false), "\(phase)") }
        for phase in Self.frozen { #expect(!RecordTimelinePolicy.needsTicks(isPlaying: true, phase: phase, reduceMotion: false), "\(phase)") }
    }

    /// Reduce Motion 不煞停（armLifted＝false）：播放中所有相位都 tick，awaiting 也不能停在半空
    @Test func reduceMotionNeverFreezesAPlayingRecord() {
        for phase in Self.moving + Self.frozen {
            #expect(RecordTimelinePolicy.needsTicks(isPlaying: true, phase: phase, reduceMotion: true), "\(phase)")
        }
    }

    @Test func notPlayingNeverTicks() {
        for phase in Self.moving + Self.frozen {
            for reduceMotion in [false, true] {
                #expect(!RecordTimelinePolicy.needsTicks(isPlaying: false, phase: phase, reduceMotion: reduceMotion), "\(phase)")
            }
        }
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
