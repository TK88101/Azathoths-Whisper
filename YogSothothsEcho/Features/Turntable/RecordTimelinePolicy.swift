import Foundation

/// CR-039（yse-g7-hitch-fix.md v0.4 §4.1）：唱片的 TimelineView 何時需要每幀更新。
/// 唱片只在「真的在轉」時 tick：播放中、未轉場，或轉場的 lifting（煞停 0.35 s）；煞停後角度已凍結，舊新兩盤都停表。
/// Reduce Motion 不煞停（`armLifted`＝false），播放中全程照轉。相位以 exhaustive switch 列舉：新增相位時編譯器會逼著決定
enum RecordTimelinePolicy {
    static func needsTicks(isPlaying: Bool, phase: SwipeTransition.Phase, reduceMotion: Bool) -> Bool {
        guard isPlaying else { return false }
        switch phase {
        case .idle, .ignoringVertical, .dragging, .returning, .lifting, .crossfading:
            return true
        case .awaiting, .relabeling, .clearing, .sheathing, .exchanging, .drawing, .placing:
            return reduceMotion
        }
    }
}
