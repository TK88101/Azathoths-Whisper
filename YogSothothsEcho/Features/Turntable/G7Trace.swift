import Foundation
import os

/// G7 signpost 的輸出端（Release 也保留；只有遞增 ID 與相位名，不含曲名等使用者資料）
@MainActor
protocol G7TraceSink: AnyObject {
    func begin(_ id: UInt64)
    func phase(_ id: UInt64, _ name: String)
    /// note＝轉場觀察者給的附註（§11 S2：`misses=<n> reasons=…`；沒有觀察者＝空字串）
    func end(_ id: UInt64, note: String)
}

/// CR-039 §4.4：每次轉場一個 interval（送出 → 回 idle／取消），其內每次相位變更一個 event。
/// 由 `swipe` 的前後值判斷，所以任何結束路徑（完成、關唱機、斷線）都會收尾；end 只發一次（冪等）
@MainActor
final class G7Trace {
    private let sink: G7TraceSink
    private let observer: (any G7TransitionObserver)?
    private var activeID: UInt64?
    private var nextID: UInt64 = 0

    init(sink: G7TraceSink, observer: (any G7TransitionObserver)? = nil) {
        self.sink = sink
        self.observer = observer
    }

    func observe(from old: SwipeTransition, to new: SwipeTransition) {
        guard new.isTransitioning else {
            if let id = activeID {
                activeID = nil
                sink.end(id, note: observer?.transitionEnded() ?? "")
                observer?.transitionClosed()
            }
            return
        }
        if let id = activeID {
            if old.phase.traceName != new.phase.traceName { sink.phase(id, new.phase.traceName) }
            return
        }
        nextID += 1
        activeID = nextID
        observer?.transitionBegan()
        sink.begin(nextID)
        sink.phase(nextID, new.phase.traceName)
    }
}

/// 實機 xctrace 用：Points of Interest 以外的獨立分類，Animation Hitches／Time Profiler 錄製時可疊加 os_signpost
@MainActor
final class OSG7TraceSink: G7TraceSink {
    private let signposter = OSSignposter(subsystem: "com.ibridgezhao.yogsothothsecho", category: "TurntableG7")
    /// G7Trace 同時最多一個進行中的轉場
    private var interval: OSSignpostIntervalState?

    func begin(_ id: UInt64) {
        interval = signposter.beginInterval("G7", id: signposter.makeSignpostID(), "\(id, privacy: .public)")
    }

    func phase(_ id: UInt64, _ name: String) {
        signposter.emitEvent("phase", "\(id, privacy: .public) \(name, privacy: .public)")
    }

    func end(_ id: UInt64, note: String) {
        guard let state = interval else { return }
        interval = nil
        signposter.endInterval("G7", state, "\(id, privacy: .public) \(note, privacy: .public)")
    }
}

extension SwipeTransition.Phase {
    /// signpost 用的相位名（不含方向等關聯值，lifting 的 ready 變化不算新相位）
    fileprivate var traceName: String {
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
