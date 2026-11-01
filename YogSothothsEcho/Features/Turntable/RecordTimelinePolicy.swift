import Foundation
import os

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

    /// render 分支：停表且有靜止角＝兩盤共讀靜止角（不呼叫有副作用的即時角）；否則走即時角
    static func displayAngle(needsTicks: Bool, resting: Double?, live: () -> Double) -> Double {
        if !needsTicks, let resting { return resting }
        return live()
    }
}

/// G7 signpost 的輸出端（Release 也保留；只有遞增 ID 與相位名，不含曲名等使用者資料）
@MainActor
protocol G7TraceSink: AnyObject {
    func begin(_ id: UInt64)
    func phase(_ id: UInt64, _ name: String)
    func end(_ id: UInt64)
}

/// CR-039 §4.4：每次轉場一個 interval（送出 → 回 idle／取消），其內每次相位變更一個 event。
/// 由 `swipe` 的前後值判斷，所以任何結束路徑（完成、關唱機、斷線）都會收尾；end 只發一次（冪等）
@MainActor
final class G7Trace {
    private let sink: G7TraceSink
    private var activeID: UInt64?
    private var nextID: UInt64 = 0

    init(sink: G7TraceSink) {
        self.sink = sink
    }

    func observe(from old: SwipeTransition, to new: SwipeTransition) {
        if new.isTransitioning {
            if let id = activeID {
                if old.phase.traceName != new.phase.traceName { sink.phase(id, new.phase.traceName) }
            } else {
                nextID += 1
                activeID = nextID
                sink.begin(nextID)
                sink.phase(nextID, new.phase.traceName)
            }
        } else if let id = activeID {
            activeID = nil
            sink.end(id)
        }
    }
}

/// 實機 xctrace 用：Points of Interest 以外的獨立分類，Animation Hitches／Time Profiler 錄製時可疊加 os_signpost
@MainActor
final class OSG7TraceSink: G7TraceSink {
    private let signposter = OSSignposter(subsystem: "com.ibridgezhao.yogsothothsecho", category: "TurntableG7")
    private var intervals: [UInt64: OSSignpostIntervalState] = [:]

    func begin(_ id: UInt64) {
        intervals[id] = signposter.beginInterval("G7", id: signposter.makeSignpostID(), "\(id, privacy: .public)")
    }

    func phase(_ id: UInt64, _ name: String) {
        signposter.emitEvent("phase", "\(id, privacy: .public) \(name, privacy: .public)")
    }

    func end(_ id: UInt64) {
        guard let state = intervals.removeValue(forKey: id) else { return }
        signposter.endInterval("G7", state, "\(id, privacy: .public)")
    }
}

extension SwipeTransition.Phase {
    /// signpost 用的相位名（不含方向等關聯值，lifting 的 ready 變化不算新相位）
    var traceName: String {
        switch self {
        case .idle: "idle"
        case .ignoringVertical: "ignoringVertical"
        case .dragging: "dragging"
        case .returning: "returning"
        case .lifting: "lifting"
        case .awaiting: "awaiting"
        case .relabeling: "relabeling"
        case .crossfading: "crossfading"
        case .clearing: "clearing"
        case .sheathing: "sheathing"
        case .exchanging: "exchanging"
        case .drawing: "drawing"
        case .placing: "placing"
        }
    }
}
