import Foundation
import Observation
import QuartzCore
import UIKit

/// S-Arm 卡頓修正的兩個做法（CR-034 附錄 F）：A′ 關唱機不釋放已解好的幀、E 解碼優先序。Release 恆開；
/// DEBUG 讀診斷開關（在場對照「舊做法／新做法」用）
@MainActor
enum SpriteStrategy {
    static var keepOnClose: Bool {
        #if DEBUG
        SpriteDiagnostics.shared.keepOnClose
        #else
        true
        #endif
    }

    static var prioritized: Bool {
        #if DEBUG
        SpriteDiagnostics.shared.prioritized
        #else
        true
        #endif
    }
}

#if DEBUG
/// 在場對照用的開關與 trace（只在 DEBUG；唱機浮層的診斷面板操作）
@MainActor
@Observable
final class SpriteDiagnostics {
    static let shared = SpriteDiagnostics()

    var keepOnClose = true
    var prioritized = true
    private(set) var lastSaved: String?
    @ObservationIgnored let trace = SpriteTrace(frameTicks: true)

    /// 寫 Documents/metrics/sprite-trace-*.json（開關狀態＋裝置＋事件；不含曲名），之後清空重記
    func save() {
        let context = ["keepOnClose": "\(keepOnClose)", "prioritized": "\(prioritized)", "device": UIDevice.current.model,
                       "os": UIDevice.current.systemVersion, "maxFPS": "\(UIScreen.main.maximumFramesPerSecond)"]
        let count = trace.events.count
        MetricsFile.write(try? trace.encoded(context: context), name: "sprite-trace")
        trace.reset()
        lastSaved = "trace \(count) events"
    }
}

/// 卡頓診斷（D-lite）：同一單調時鐘記錄解碼開始／發布、釋放、唱臂動畫起訖；動畫期間另記每次取幀（要求幀、實際幀、是否精確）
/// 與 CADisplayLink 幀間隔
@MainActor
final class SpriteTrace {
    struct Event: Codable, Equatable {
        let t: Double
        let kind: String
        var frame: Int?
        var generation: Int?
        var urgent: Bool?
        var requested: Int?
        var exact: Bool?
        var interval: Double?
    }

    /// 執行中 App 的 trace（快取與視圖寫入這一份）
    static var current: SpriteTrace? { SpriteDiagnostics.shared.trace }

    private(set) var events: [Event] = []
    private let clock: () -> Double
    private let frameTicks: Bool
    private var motionUntil = -Double.infinity
    private var link: CADisplayLink?
    private var lastTick: Double?

    init(clock: @escaping () -> Double = { CACurrentMediaTime() }, frameTicks: Bool = false) {
        self.clock = clock
        self.frameTicks = frameTicks
    }

    func decodeStarted(frame: Int, generation: Int, urgent: Bool) {
        events.append(Event(t: clock(), kind: "decodeStart", frame: frame, generation: generation, urgent: urgent))
    }

    func decodePublished(frame: Int, generation: Int) {
        events.append(Event(t: clock(), kind: "published", frame: frame, generation: generation))
    }

    func released(generation: Int) {
        events.append(Event(t: clock(), kind: "release", generation: generation))
    }

    /// 落臂／抬臂開始：之後 `duration` 秒內記錄取幀與幀間隔
    func armMotionStarted(duration: Double) {
        let now = clock()
        events.append(Event(t: now, kind: "armMotionStart", interval: duration))
        motionUntil = now + duration
        guard frameTicks, link == nil else { return }
        lastTick = nil
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func frameRequested(requested: Int, served: Int, exact: Bool) {
        let now = clock()
        guard now <= motionUntil else { return }
        events.append(Event(t: now, kind: "frame", frame: served, requested: requested, exact: exact))
    }

    func reset() {
        events = []
        motionUntil = -.infinity
    }

    func encoded(context: [String: String]) throws -> Data {
        struct Record: Codable {
            let context: [String: String]
            let events: [Event]
        }
        return try JSONEncoder().encode(Record(context: context, events: events))
    }

    fileprivate func tick(_ timestamp: Double) {
        guard timestamp <= motionUntil + 0.1 else {
            link?.invalidate()
            link = nil
            return
        }
        if let lastTick { events.append(Event(t: timestamp, kind: "tick", interval: timestamp - lastTick)) }
        lastTick = timestamp
    }

    @MainActor
    private final class Ticker: NSObject {
        weak var owner: SpriteTrace?
        init(_ owner: SpriteTrace) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link.timestamp) }
    }
}
#endif
