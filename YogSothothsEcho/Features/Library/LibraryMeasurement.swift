import Foundation
import SwiftUI
import UIKit

/// 百分位一律 nearest-rank：由小到大第 ⌈p×n⌉ 筆
enum PercentileJudge {
    static func nearestRank(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count) - 1e-9).rounded(.up))   // 0.95×20 在浮點下略大於 19
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

/// 捲動流暢度判定（sprint-3-detail.md §4.11；純函式）。輸入是 CADisplayLink 的幀時間戳（秒，遞增）
enum FrameRateJudge {
    static let window: Double = 1
    static let threshold: Double = 30

    /// 每個 1 秒滑動窗的 FPS＝窗內幀間隔數 ÷ 該窗實際經過時間；回最差值。超過 1 秒的單一卡頓＝1 ÷ 該間隔
    static func worstWindowFPS(_ timestamps: [Double]) -> Double? {
        guard timestamps.count >= 2 else { return nil }
        var worst = Double.infinity
        var end = 0
        for start in timestamps.indices.dropLast() {
            end = max(end, start)
            while end + 1 < timestamps.count, timestamps[end + 1] - timestamps[start] <= window { end += 1 }
            if end == start {
                worst = min(worst, 1 / (timestamps[start + 1] - timestamps[start]))
                continue
            }
            let elapsed = timestamps[end] - timestamps[start]
            guard end + 1 < timestamps.count || elapsed >= window * 0.5 else { continue }   // 尾端過短的窗不計
            worst = min(worst, Double(end - start) / elapsed)
        }
        return worst.isFinite ? worst : nil
    }

    static func longestInterval(_ timestamps: [Double]) -> Double? {
        zip(timestamps.dropFirst(), timestamps).map { $0 - $1 }.max()
    }

    static func slowFrames(_ timestamps: [Double]) -> Int {
        zip(timestamps.dropFirst(), timestamps).filter { $0 - $1 > 1 / threshold }.count
    }

    static func passes(_ timestamps: [Double]) -> Bool { (worstWindowFPS(timestamps) ?? 0) >= threshold }

    /// 幀間隔第 95 百分位（nearest-rank，同 N-01 量測）
    static func p95Interval(_ intervals: [Double]) -> Double? { PercentileJudge.nearestRank(intervals, 0.95) }

    static func intervalsOver(_ intervals: [Double], seconds: Double) -> Int { intervals.filter { $0 > seconds }.count }
}

/// 量測紀錄（只含數值與環境，不含任何名稱）；DEBUG 寫入 Documents/metrics，使用者經 Finder 取出
struct MeasurementRecord: Encodable {
    enum Kind: String, Encodable { case firstScreen, scroll }
    enum Cache: String, Encodable { case cold, warm }
    /// 捲動方向：側封 x、小圖 y（v2）
    enum Axis: String, Encodable, Sendable { case x, y }
    /// 強制作廢（v2）：錄製中切換展示，即使 flick 滿 10 次也作廢
    enum VoidReason: String, Encodable, Sendable { case layoutChanged }

    /// v2（s6-61-g-perf-wear.md §5.5）：加 layout、axis、p95FrameIntervalMs、framesOver100ms、voidReason；v1 欄位全保留、語義不變
    /// （scroll*Offset 依 axis 解讀；分析端讀 v1 時 layout＝spines、axis＝x）
    static let protocolVersion = 2
    static let requiredFlicks = 10
    static let allowedKeys: Set<String> = [
        "protocolVersion", "kind", "trialID", "cache", "device", "osVersion", "build", "firstScreenCells", "firstScreenSeconds",
        "frameIntervals", "worstWindowFPS", "longestIntervalMs", "slowFrames", "passes", "flickCount", "void",
        "scrollStartOffset", "scrollEndOffset", "scrollSeconds", "layout", "axis", "p95FrameIntervalMs", "framesOver100ms", "voidReason",
    ]

    let kind: Kind
    let trialID: Int
    let cache: Cache
    let device: String
    let osVersion: String
    let build: String
    let firstScreenCells: Int?
    let firstScreenSeconds: Double?
    let frameIntervals: [Double]
    let flickCount: Int?
    let scrollStartOffset: Double?
    let scrollEndOffset: Double?
    let scrollSeconds: Double?
    var layout: BrowseLayout?
    var axis: Axis?
    var voidReason: VoidReason?

    /// 手勢規約 v1：flick 次數不是 10 的捲動試次作廢；v2：有強制作廢原因也作廢
    var isVoid: Bool { kind == .scroll && (voidReason != nil || flickCount != Self.requiredFlicks) }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, kind, trialID, cache, device, osVersion, build, firstScreenCells, firstScreenSeconds, frameIntervals
        case worstWindowFPS, longestIntervalMs, slowFrames, passes, flickCount, void, scrollStartOffset, scrollEndOffset, scrollSeconds
        case layout, axis, p95FrameIntervalMs, framesOver100ms, voidReason
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.protocolVersion, forKey: .protocolVersion)
        try c.encode(kind, forKey: .kind)
        try c.encode(trialID, forKey: .trialID)
        try c.encode(cache, forKey: .cache)
        try c.encode(device, forKey: .device)
        try c.encode(osVersion, forKey: .osVersion)
        try c.encode(build, forKey: .build)
        try c.encodeIfPresent(firstScreenCells, forKey: .firstScreenCells)
        try c.encodeIfPresent(firstScreenSeconds, forKey: .firstScreenSeconds)
        try c.encode(frameIntervals, forKey: .frameIntervals)
        let stamps = frameIntervals.reduce(into: [0.0]) { $0.append($0.last! + $1) }
        try c.encodeIfPresent(FrameRateJudge.worstWindowFPS(stamps), forKey: .worstWindowFPS)
        try c.encodeIfPresent(FrameRateJudge.longestInterval(stamps).map { $0 * 1000 }, forKey: .longestIntervalMs)
        try c.encode(FrameRateJudge.slowFrames(stamps), forKey: .slowFrames)
        try c.encode(kind == .firstScreen ? (firstScreenSeconds ?? .infinity) <= 2 : FrameRateJudge.passes(stamps), forKey: .passes)
        try c.encodeIfPresent(flickCount, forKey: .flickCount)
        try c.encode(isVoid, forKey: .void)
        try c.encodeIfPresent(scrollStartOffset, forKey: .scrollStartOffset)
        try c.encodeIfPresent(scrollEndOffset, forKey: .scrollEndOffset)
        try c.encodeIfPresent(scrollSeconds, forKey: .scrollSeconds)
        try c.encodeIfPresent(layout?.rawValue, forKey: .layout)
        try c.encodeIfPresent(axis, forKey: .axis)
        try c.encodeIfPresent(FrameRateJudge.p95Interval(frameIntervals).map { $0 * 1000 }, forKey: .p95FrameIntervalMs)
        try c.encode(FrameRateJudge.intervalsOver(frameIntervals, seconds: 0.1), forKey: .framesOver100ms)
        try c.encodeIfPresent(voidReason, forKey: .voidReason)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static var deviceIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

#if DEBUG
/// DEBUG 才有：冷啟動預約。真機經 iLoader 安裝、帶不了啟動參數，所以由面板預約、下次啟動在建封面快取之前清掉目錄。
/// 不在執行中清：活著的 ArtworkCache 會把記憶體裡的索引寫回去
enum ColdStartRequest {
    static let key = "YSEDebugColdNextLaunch"

    static func request(defaults: UserDefaults = .standard) { defaults.set(true, forKey: key) }
    static func isPending(defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }

    /// 有預約＝刪掉快取目錄、清除預約並回 true（本次啟動標 cold）
    static func consume(directory: URL, defaults: UserDefaults = .standard) -> Bool {
        guard isPending(defaults: defaults) else { return false }
        defaults.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: directory)
        return true
    }
}

/// DEBUG 才有：捲動試次的幀取樣（CADisplayLink）與 JSON 輸出
@MainActor
@Observable
final class FrameRateMonitor {
    static let shared = FrameRateMonitor()

    private(set) var isRecording = false
    private(set) var trialID = 0
    private(set) var flickCount = 0
    private(set) var lastResult: String?
    private(set) var lastVoidReason: MeasurementRecord.VoidReason?
    var cache: MeasurementRecord.Cache = .warm
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var stamps: [Double] = []
    @ObservationIgnored private(set) var trialStartOffset: Double = 0
    /// 兩個方向各自最新的位移（切展示後不沿用另一方向的值）
    @ObservationIgnored private var offsets: [MeasurementRecord.Axis: Double] = [:]
    @ObservationIgnored private var trialLayout: BrowseLayout = .spines
    @ObservationIgnored private var startedAt: Date?

    /// 試次上下文不可缺（v2）：哪種展示、量哪個方向
    func begin(layout: BrowseLayout) {
        trialID += 1
        flickCount = 0
        stamps = []
        trialLayout = layout
        trialStartOffset = offsets[layout.scrollAxis] ?? 0
        startedAt = Date()
        isRecording = true
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func end(voidReason: MeasurementRecord.VoidReason? = nil) {
        guard isRecording else { return }
        link?.invalidate()
        link = nil
        isRecording = false
        lastVoidReason = voidReason
        let intervals = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        let record = MeasurementRecord(kind: .scroll, trialID: trialID, cache: cache, device: MeasurementRecord.deviceIdentifier,
                                       osVersion: UIDevice.current.systemVersion, build: Self.build, firstScreenCells: nil,
                                       firstScreenSeconds: nil, frameIntervals: intervals, flickCount: flickCount,
                                       scrollStartOffset: trialStartOffset, scrollEndOffset: offsets[trialLayout.scrollAxis] ?? 0,
                                       scrollSeconds: startedAt.map { Date().timeIntervalSince($0) }, layout: trialLayout, axis: trialLayout.scrollAxis,
                                       voidReason: voidReason)
        let fps = FrameRateJudge.worstWindowFPS(stamps).map { String(format: "%.1f", $0) } ?? "-"
        lastResult = record.isVoid ? "void (\(voidReason?.rawValue ?? "\(flickCount) flicks"))" : "worst \(fps) fps"
        Self.write(record, name: "scroll-\(trialID)")
    }

    func recordFirstScreen(seconds: Double, cells: Int) {
        let record = MeasurementRecord(kind: .firstScreen, trialID: 0, cache: cache, device: MeasurementRecord.deviceIdentifier,
                                       osVersion: UIDevice.current.systemVersion, build: Self.build, firstScreenCells: cells,
                                       firstScreenSeconds: seconds, frameIntervals: [], flickCount: nil, scrollStartOffset: nil,
                                       scrollEndOffset: nil, scrollSeconds: nil)
        Self.write(record, name: "first-screen")
    }

    func flicked() { if isRecording { flickCount += 1 } }
    func scrolled(to offset: Double, axis: MeasurementRecord.Axis) { offsets[axis] = offset }
    fileprivate func tick(_ timestamp: Double) { stamps.append(timestamp) }

    private static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-" }

    /// Documents 只放 metrics（Debug 開了 UIFileSharingEnabled，Finder 看得到整個 Documents）
    private static func write(_ record: MeasurementRecord, name: String) {
        MetricsFile.write(try? record.encoded(), name: name)
    }

    /// CADisplayLink 會強持有 target：用中介物件避免循環。加在 main run loop，回呼在主執行緒
    @MainActor
    private final class Ticker: NSObject {
        weak var owner: FrameRateMonitor?
        init(_ owner: FrameRateMonitor) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link.timestamp) }
    }
}
#endif

/// 捲動時把 flick 與位移交給量測（DEBUG）；Release 不做任何事。方向＝`BrowseLayout.scrollAxis`（側封 x、小圖 y；g 版 T5 補接）
struct FrameRateTracking: ViewModifier {
    let layout: BrowseLayout

    func body(content: Content) -> some View {
        #if DEBUG
        content
            .onScrollPhaseChange { old, new in
                if old == .interacting, new == .decelerating { FrameRateMonitor.shared.flicked() }
            }
            .onScrollGeometryChange(for: Double.self, of: { Double(layout.scrollAxis == .x ? $0.contentOffset.x : $0.contentOffset.y) }) { _, offset in
                FrameRateMonitor.shared.scrolled(to: offset, axis: layout.scrollAxis)
            }
        #else
        content
        #endif
    }
}

/// DEBUG 量測面板：首頁秒數、試次控制（手勢規約 v1）、快取冷熱。Release 是空的
struct LibraryDebugOverlay: View {
    let model: LibraryViewModel
    var layout: BrowseLayout = .spines

    var body: some View {
        #if DEBUG
        DebugPanel(model: model, layout: layout)
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
private struct DebugPanel: View {
    let model: LibraryViewModel
    let layout: BrowseLayout
    @State private var monitor = FrameRateMonitor.shared
    @State private var reportedFirstScreen = false
    @State private var coldArmed = ColdStartRequest.isPending()

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(verbatim: model.metrics.firstScreenSeconds.map { String(format: "first screen %.2f s", $0) } ?? "first screen …")
                .accessibilityIdentifier(AccessibilityID.libraryFirstScreen)
            Text(verbatim: "albums \(model.albums.count)").accessibilityIdentifier(AccessibilityID.libraryCount)
            Text(verbatim: "trial \(monitor.trialID) · flicks \(monitor.flickCount)/\(MeasurementRecord.requiredFlicks)")
            if let result = monitor.lastResult { Text(verbatim: result) }
            HStack {
                Button { monitor.cache = monitor.cache == .cold ? .warm : .cold } label: {
                    Text(verbatim: monitor.cache == .cold ? "cold" : "warm")
                }
                Button {
                    ColdStartRequest.request()
                    coldArmed = true
                } label: {
                    Text(verbatim: coldArmed ? "cold armed: relaunch" : "cold next launch")
                }
                Button { monitor.isRecording ? monitor.end() : monitor.begin(layout: layout) } label: {
                    Text(verbatim: monitor.isRecording ? "end trial" : "begin trial")
                }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.ultraThinMaterial)
        .onChange(of: model.metrics.firstScreenSeconds) { _, seconds in
            guard let seconds, !reportedFirstScreen else { return }
            reportedFirstScreen = true
            monitor.recordFirstScreen(seconds: seconds, cells: model.metrics.firstScreenCells)
        }
    }
}
#endif
