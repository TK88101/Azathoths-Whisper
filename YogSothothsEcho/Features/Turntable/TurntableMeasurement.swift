import Foundation
import QuartzCore
import UIKit

/// N-02 的判定（sprint-5-detail.md §4.8）：以 60 Hz 幀預算計——每個 1 s 滑動視窗 ≥ 58 幀；間隔 > 25 ms（掉 1 幀以上）的幀 ≤ 0.5%；
/// 沒有任何間隔 > 50 ms。少於 1 s 的樣本不判過
enum TurntableFrameJudge {
    static let minFramesPerSecond = 58
    static let droppedInterval = 0.025
    static let maxDroppedRatio = 0.005
    static let hitchInterval = 0.05

    struct Result: Equatable, Codable {
        let frames: Int
        let minWindowFrames: Int
        let droppedRatio: Double
        let maxInterval: Double
        let passes: Bool
    }

    static func evaluate(_ stamps: [Double]) -> Result {
        let intervals = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        let maxInterval = intervals.max() ?? 0
        let droppedRatio = intervals.isEmpty ? 0 : Double(intervals.filter { $0 > droppedInterval }.count) / Double(intervals.count)
        let minWindow = minWindowFrames(stamps)
        let passes = minWindow.map { $0 >= minFramesPerSecond } == true && droppedRatio <= maxDroppedRatio && maxInterval <= hitchInterval
        return Result(frames: stamps.count, minWindowFrames: minWindow ?? 0, droppedRatio: droppedRatio, maxInterval: maxInterval,
                      passes: passes)
    }

    /// 每個起點 t 的 [t, t+1) 內的幀數，只取完整落在樣本範圍內的視窗；沒有完整視窗＝nil
    private static func minWindowFrames(_ stamps: [Double]) -> Int? {
        guard let last = stamps.last else { return nil }
        var best: Int?
        var end = 0
        for (start, time) in stamps.enumerated() where time + 1 <= last {
            while end < stamps.count, stamps[end] < time + 1 { end += 1 }
            best = min(best ?? .max, end - start)
        }
        return best
    }
}

#if DEBUG
/// 唱機量測（DEBUG；#5-1）：旋轉 30 s 記每幀時間戳（唱機不提供拖唱頭，CR-019），判定並連同量測條件寫進 Documents/metrics（Finder 取出）
@MainActor
@Observable
final class TurntableMeasurement {
    enum Kind: String, Codable { case spin }

    static let shared = TurntableMeasurement()
    static let durations: [Kind: Double] = [.spin: 30]

    private(set) var running: Kind?
    private(set) var lastResult: String?
    @ObservationIgnored private var stamps: [Double] = []
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var context: [String: String] = [:]

    private struct Record: Codable {
        let kind: Kind
        let context: [String: String]
        let result: TurntableFrameJudge.Result
        let intervals: [Double]
    }

    /// context：素材是否載入、模糊圖是否就緒等（不含曲名）
    func start(_ kind: Kind, context: [String: String]) {
        guard running == nil else { return }
        running = kind
        stamps = []
        self.context = context.merging(Self.deviceContext) { $1 }
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.durations[kind] ?? 10))
            self?.finish()
        }
    }

    private func finish() {
        guard let kind = running else { return }
        link?.invalidate()
        link = nil
        running = nil
        let result = TurntableFrameJudge.evaluate(stamps)
        lastResult = "\(kind.rawValue): min \(result.minWindowFrames) fps · \(result.passes ? "pass" : "fail")"
        let record = Record(kind: kind, context: context, result: result, intervals: zip(stamps.dropFirst(), stamps).map { $0 - $1 })
        MetricsFile.write(try? JSONEncoder().encode(record), name: "turntable-\(kind.rawValue)")
    }

    private static var deviceContext: [String: String] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return ["device": model, "os": UIDevice.current.systemVersion,
                "maxFPS": "\(UIScreen.main.maximumFramesPerSecond)",
                "thermal": "\(ProcessInfo.processInfo.thermalState.rawValue)",
                "lowPower": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)"]
    }

    fileprivate func tick(_ timestamp: Double) { stamps.append(timestamp) }

    @MainActor
    private final class Ticker: NSObject {
        weak var owner: TurntableMeasurement?
        init(_ owner: TurntableMeasurement) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link.timestamp) }
    }
}
#endif
