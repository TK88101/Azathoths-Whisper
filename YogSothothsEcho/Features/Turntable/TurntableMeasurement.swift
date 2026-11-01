import Foundation
import QuartzCore
import UIKit

/// N-02 的判定（sprint-5-detail.md §4.8）：以 60 Hz 幀預算計——每個 1 s 滑動視窗 ≥ 58 幀；間隔 > 25 ms（掉 1 幀以上）的幀 ≤ 0.5%；
/// 沒有任何間隔 > 50 ms。少於 1 s 的樣本不判過。CR-038 加 120 Hz 參數組（≥ 116 幀、12.5 ms），不帶參數＝60 Hz
enum TurntableFrameJudge {
    struct Profile: Equatable {
        let name: String
        let minFramesPerSecond: Int
        let droppedInterval: Double
        let maxDroppedRatio: Double
        let hitchInterval: Double

        static let hz60 = Profile(name: "60Hz", minFramesPerSecond: 58, droppedInterval: 0.025, maxDroppedRatio: 0.005, hitchInterval: 0.05)
        static let hz120 = Profile(name: "120Hz", minFramesPerSecond: 116, droppedInterval: 0.0125, maxDroppedRatio: 0.005, hitchInterval: 0.05)
    }

    static let minFramesPerSecond = Profile.hz60.minFramesPerSecond
    static let droppedInterval = Profile.hz60.droppedInterval
    static let maxDroppedRatio = Profile.hz60.maxDroppedRatio
    static let hitchInterval = Profile.hz60.hitchInterval

    struct Result: Equatable, Codable {
        let frames: Int
        let minWindowFrames: Int
        let droppedRatio: Double
        let maxInterval: Double
        let passes: Bool
        var profile = Profile.hz60.name
        /// 由平均幀間隔換算的實際更新率（沒有間隔＝0）
        var actualHz = 0.0
    }

    static func evaluate(_ stamps: [Double], profile: Profile = .hz60) -> Result {
        let intervals = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        let maxInterval = intervals.max() ?? 0
        let droppedRatio = intervals.isEmpty ? 0 : Double(intervals.filter { $0 > profile.droppedInterval }.count) / Double(intervals.count)
        let minWindow = minWindowFrames(stamps)
        let passes = minWindow.map { $0 >= profile.minFramesPerSecond } == true && droppedRatio <= profile.maxDroppedRatio
            && maxInterval <= profile.hitchInterval
        let span = (stamps.last ?? 0) - (stamps.first ?? 0)
        return Result(frames: stamps.count, minWindowFrames: minWindow ?? 0, droppedRatio: droppedRatio, maxInterval: maxInterval,
                      passes: passes, profile: profile.name, actualHz: intervals.isEmpty || span <= 0 ? 0 : Double(intervals.count) / span)
    }

    struct SegmentSummary: Equatable, Codable {
        let segments: [Result]
        let worstMaxInterval: Double
        let worstMinWindowFrames: Int
        let medianMinWindowFrames: Double
        let passes: Bool
    }

    /// CR-038 §4.5-3：每次甩動起 length 秒各判一次（G7）；沒有甩動＝不判過
    static func segments(_ stamps: [Double], starts: [Double], length: Double, profile: Profile) -> SegmentSummary {
        let parts = starts.map { start in evaluate(stamps.filter { $0 >= start && $0 < start + length }, profile: profile) }
        let windows = parts.map(\.minWindowFrames).sorted()
        let median: Double = windows.isEmpty ? 0
            : windows.count.isMultiple(of: 2) ? Double(windows[windows.count / 2 - 1] + windows[windows.count / 2]) / 2 : Double(windows[windows.count / 2])
        return SegmentSummary(segments: parts, worstMaxInterval: parts.map(\.maxInterval).max() ?? 0,
                              worstMinWindowFrames: windows.first ?? 0, medianMinWindowFrames: median,
                              passes: !parts.isEmpty && parts.allSatisfy(\.passes))
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
    /// spin＝N-02（60 Hz）；liquid*＝CR-038 §4.5（要求 120 Hz，60／120 兩組都判，次指標；主指標是 xctrace）
    enum Kind: String, Codable {
        case spin
        case liquidLive, liquidReduceMotion, liquidG7
        case liquidPreviewStill, liquidPreviewSlow, liquidPreviewNormal, liquidPreviewJustStopped

        var isLiquid: Bool { self != .spin }
    }

    static let shared = TurntableMeasurement()
    /// 量測秒數（暖機另計）：live／Reduce Motion 30 s；G7 30 s 內甩 5 次、每次取 2 s；預覽每態 10 s、剛停取停後 6 s
    static let durations: [Kind: Double] = [.spin: 30, .liquidLive: 30, .liquidReduceMotion: 30, .liquidG7: 30,
                                            .liquidPreviewStill: 10, .liquidPreviewSlow: 10, .liquidPreviewNormal: 10,
                                            .liquidPreviewJustStopped: 6]
    static let liquidWarmup = 5.0
    static let g7SegmentSeconds = 2.0

    private(set) var running: Kind?
    private(set) var lastResult: String?
    @ObservationIgnored private var stamps: [Double] = []
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var context: [String: String] = [:]
    @ObservationIgnored private var swipeStarts: [Double] = []
    @ObservationIgnored private var continuation: CheckedContinuation<Void, Never>?

    private struct Record: Codable {
        let kind: Kind
        let context: [String: String]
        /// 60 Hz（N-02）；liquid* 另有 120 Hz 與 G7 分段
        let result: TurntableFrameJudge.Result
        var result120: TurntableFrameJudge.Result?
        var g7: [String: TurntableFrameJudge.SegmentSummary]?
        var swipeOffsets: [Double]?
        let intervals: [Double]
    }

    /// context：素材是否載入、模糊圖是否就緒等（不含曲名）。liquid* 先暖機 5 s（不計），並要求 120 Hz
    func start(_ kind: Kind, context: [String: String]) {
        guard running == nil else { return }
        running = kind
        stamps = []
        swipeStarts = []
        self.context = context.merging(Self.deviceContext) { $1 }.merging(["method": "CADisplayLink", "build": Self.buildCommit]) { $1 }
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick(_:)))
        if kind.isLiquid { link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120) }
        link.add(to: .main, forMode: .common)
        self.link = link
        let warmup = kind.isLiquid && kind != .liquidPreviewJustStopped ? Self.liquidWarmup : 0
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(warmup))
            self?.stamps = []
            try? await Task.sleep(for: .seconds(Self.durations[kind] ?? 10))
            self?.finish()
        }
    }

    /// 量完才返回（預覽畫布依序量四態）
    func measure(_ kind: Kind, context: [String: String]) async {
        guard running == nil else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            start(kind, context: context)
        }
    }

    /// G7 甩動起點（量測進行中才記）
    func markSwipe() {
        guard running == .liquidG7 else { return }
        swipeStarts.append(CACurrentMediaTime())
    }

    private func finish() {
        guard let kind = running else { return }
        link?.invalidate()
        link = nil
        running = nil
        let result = TurntableFrameJudge.evaluate(stamps)
        var record = Record(kind: kind, context: context, result: result, intervals: zip(stamps.dropFirst(), stamps).map { $0 - $1 })
        if kind.isLiquid {
            let result120 = TurntableFrameJudge.evaluate(stamps, profile: .hz120)
            record.result120 = result120
            lastResult = String(format: "%@: %.0f Hz · 120 %@ · 60 %@", kind.rawValue, result120.actualHz,
                                result120.passes ? "pass" : "fail", result.passes ? "pass" : "fail")
        } else {
            lastResult = "\(kind.rawValue): min \(result.minWindowFrames) fps · \(result.passes ? "pass" : "fail")"
        }
        if kind == .liquidG7 {
            let starts = swipeStarts
            record.g7 = [TurntableFrameJudge.Profile.hz120.name: TurntableFrameJudge.segments(stamps, starts: starts, length: Self.g7SegmentSeconds, profile: .hz120),
                         TurntableFrameJudge.Profile.hz60.name: TurntableFrameJudge.segments(stamps, starts: starts, length: Self.g7SegmentSeconds, profile: .hz60)]
            record.swipeOffsets = starts.map { $0 - (stamps.first ?? $0) }
            lastResult = (lastResult ?? "") + " · swipes \(starts.count)"
        }
        MetricsFile.write(try? JSONEncoder().encode(record), name: "turntable-\(kind.rawValue)")
        continuation?.resume()
        continuation = nil
    }

    /// Debug 建置時由建置腳本寫進 Info.plist（YSEBuildCommit）；沒有＝unknown
    private static var buildCommit: String {
        Bundle.main.object(forInfoDictionaryKey: "YSEBuildCommit") as? String ?? "unknown"
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
