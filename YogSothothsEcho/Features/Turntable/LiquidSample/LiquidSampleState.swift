#if LIQUID_SAMPLE
import Foundation
import Observation

// CR-038 液態黑膠小樣（yse-liquid-vinyl-sample.md v0.4 §4.2／§4.4）：預覽四態驅動器、每張唱片的液體狀態、小樣開關。
// 全部只存記憶體（App 重開即關）

/// 預覽畫布四態：盤速（°/s）與自動循環時長（s）
enum LiquidPreviewPhase: String, CaseIterable, Identifiable {
    case still, slow, normal, justStopped

    var id: Self { self }

    var speed: Double {
        switch self {
        case .still, .justStopped: 0
        case .slow: 4.5
        case .normal: RecordSpin.degreesPerSecond
        }
    }

    var duration: Double {
        switch self {
        case .still: 3
        case .slow: 6
        case .normal: 8
        case .justStopped: 6
        }
    }

    var next: LiquidPreviewPhase {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// 預覽畫布的盤角來源（不碰真實播放）：自動循環或手動停在某一態；起停瞬間完成（與 App 的暫停一致）
struct LiquidPreviewDriver: Equatable {
    private(set) var phase: LiquidPreviewPhase = .still
    private(set) var isAuto = true
    private(set) var discAngle = 0.0
    private var phaseStart: Double
    private var lastTime: Double
    /// 停著時點「剛停」：先正常轉一段，這個時刻再停
    private var pendingStopAt: Double?

    init(at now: Double) {
        phaseStart = now
        lastTime = now
    }

    /// 推進到 now，回傳連續盤角；一幀跨過相位邊界時分段積分
    mutating func tick(at now: Double) -> Double {
        guard now > lastTime else { return discAngle }
        var t = lastTime
        while t < now {
            let boundary = nextBoundary()
            let end = min(now, boundary ?? now)
            discAngle += phase.speed * (end - t)
            t = end
            if let boundary, end >= boundary { advancePhase(at: boundary) }
        }
        lastTime = now
        return discAngle
    }

    mutating func select(_ target: LiquidPreviewPhase, at now: Double) {
        _ = tick(at: now)
        isAuto = false
        pendingStopAt = nil
        if target == .justStopped, phase.speed == 0 {
            phase = .normal
            pendingStopAt = now + LiquidPreviewPhase.normal.duration
        } else {
            phase = target
        }
        phaseStart = now
    }

    mutating func setAuto(_ on: Bool, at now: Double) {
        _ = tick(at: now)
        isAuto = on
        pendingStopAt = nil
        phaseStart = now
    }

    private func nextBoundary() -> Double? {
        if let pendingStopAt { return pendingStopAt }
        return isAuto ? phaseStart + phase.duration : nil
    }

    private mutating func advancePhase(at time: Double) {
        if pendingStopAt != nil {
            pendingStopAt = nil
            phase = .justStopped
        } else {
            phase = phase.next
        }
        phaseStart = time
    }
}

/// 每張視覺唱片（以 trackID 為鍵）各一份液體狀態；G7 舊新兩盤共用同一個盤角輸入、狀態各自獨立，並存 ≤ 2。
/// `animatingKeys` 是唯一被觀察的狀態（決定 TimelineView 能否暫停）；它的轉換一律經 schedule 送出，不在 body 求值中直接改
@MainActor
@Observable
final class LiquidMotionStore {
    static let shared = LiquidMotionStore(schedule: { op in Task { @MainActor in op() } })
    static let capacity = 2

    private struct Entry {
        var motion: LiquidMotion
        var unwrapper: AngleUnwrapper
        var lastUse: Int
    }

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var useCounter = 0
    @ObservationIgnored private let schedule: (@escaping @MainActor () -> Void) -> Void
    private var animatingKeys: Set<String> = []

    init(schedule: @escaping (@escaping @MainActor () -> Void) -> Void) {
        self.schedule = schedule
    }

    var count: Int { entries.count }
    func contains(_ key: String) -> Bool { entries[key] != nil }
    func isAnimating(_ key: String) -> Bool { animatingKeys.contains(key) }

    func release(_ key: String) {
        entries[key] = nil
        schedule { [weak self] in self?.animatingKeys.remove(key) }
    }

    func frame(for key: String, rawAngle: Double, at now: Double, preset: LiquidPreset, reduceMotion: Bool) -> LiquidFrame {
        useCounter += 1
        var entry = entries[key] ?? makeEntry(rawAngle: rawAngle, at: now, preset: preset)
        let disc = entry.unwrapper.unwrap(rawAngle)
        if entry.motion.preset != preset {
            entry.motion = LiquidMotion(preset: preset, discAngle: disc, at: now)
        } else {
            entry.motion.advance(to: disc, at: now)
        }
        entry.lastUse = useCounter
        entries[key] = entry
        let animating = !entry.motion.isSettled
        if animating != animatingKeys.contains(key) {
            schedule { [weak self] in
                guard let self, self.entries[key] != nil else { return }
                if animating { self.animatingKeys.insert(key) } else { self.animatingKeys.remove(key) }
            }
        }
        return entry.motion.frame(reduceMotion: reduceMotion)
    }

    private func makeEntry(rawAngle: Double, at now: Double, preset: LiquidPreset) -> Entry {
        if entries.count >= Self.capacity, let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
            release(oldest)
        }
        var unwrapper = AngleUnwrapper()
        let disc = unwrapper.unwrap(rawAngle)
        return Entry(motion: LiquidMotion(preset: preset, discAngle: disc, at: now), unwrapper: unwrapper, lastUse: useCounter)
    }
}

/// 小樣的開關與選項（浮層 DEBUG 區與預覽畫布共用）
@MainActor
@Observable
final class LiquidSample {
    static let shared = LiquidSample()

    var preset: LiquidPreset = .liquid
    var isLive = false
    var reduceMotionPreview = false
    var isPreviewPresented = false
}
#endif

#if LIQUID_SAMPLE
import os
import QuartzCore

/// G7 甩動起點：DisplayLink 量測的分段（TurntableMeasurement）＋xctrace 的 Points of Interest（liquid_hitches.py 分段）
@MainActor
enum LiquidSwipeMarker {
    static let signposter = OSSignposter(subsystem: "com.ibridgezhao.yogsothothsecho", category: .pointsOfInterest)

    static func mark() {
        signposter.emitEvent("G7 swipe")
        TurntableMeasurement.shared.markSwipe()
    }
}
#endif
