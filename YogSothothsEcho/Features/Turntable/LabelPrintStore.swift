import CoreGraphics
import Observation
import OSLog
import SwiftUI

/// CR-039 §11 S2：標籤固定印字的快取鍵。印字內容只有條碼數字會因 build 而變；顏色不進鍵（遮罩只存透明度，顯示時套色）
struct LabelPrintKey: Hashable, Sendable {
    /// renderer／版面版次：`contentSignature` 任何一項改變都要加 1（測試以「每個 schema 一份簽章」鎖）
    static let currentSchema = 1
    static let contentSignature = "ring=\(LabelLayout.ringText)|wordmark=\(LabelLayout.wordmark)|ringRadius=\(LabelLayout.ringRadius)|"
        + "ringFont=\(LabelLayout.ringFont)|ringStep=\(LabelLayout.ringStep)|rim=\(LabelLayout.rimDiameter)|"
        + "wordmarkTop=\(LabelLayout.wordmarkTop)|wordmarkFont=\(LabelLayout.wordmarkFont)|wordmarkTracking=\(LabelLayout.wordmarkTracking)|"
        + "barcodeTop=\(LabelLayout.barcodeTop)|barcodeHeight=\(LabelLayout.barcodeHeight)|barcodeWidth=\(LabelLayout.barcodeWidth)|"
        + "guard=\(LabelLayout.guardExtension)|opacity=rim0.25,ring0.8,bar1,wordmark1"

    let schema: Int
    /// 標籤邏輯直徑 ×100（pt）
    let diameterCenti: Int
    let scaleCenti: Int
    /// 條碼模組序列（已驗證）；沒有或不合法＝nil（都不畫條碼）
    let barcode: [Bool]?

    var diameter: CGFloat { CGFloat(diameterCenti) / 100 }
    var scale: CGFloat { CGFloat(scaleCenti) / 100 }

    /// 遮罩畫布邊長（px）：≥ 標籤像素直徑、取偶數——標籤置中時圓心落在整數像素上，顯示不必縮放（縮放會讓字邊偏移）
    var canvasPixels: Int {
        let needed = Int((diameter * scale).rounded(.up))
        return needed.isMultiple(of: 2) ? needed : needed + 1
    }

    /// 畫布邊長（pt）
    var canvasSide: CGFloat { CGFloat(canvasPixels) / scale }

    /// 唯一的計算處：標籤直徑＝`214 × recordSide / 474`（VinylRecordView.labelView 同一公式）
    static func make(recordSide: CGFloat, displayScale: CGFloat, modules: [Bool]?) -> LabelPrintKey {
        let diameter = VinylRecordView.labelDiameter(forSide: recordSide)
        return LabelPrintKey(schema: currentSchema, diameterCenti: Int((diameter * 100).rounded()),
                             scaleCenti: Int((displayScale * 100).rounded()), barcode: modules)
    }
}

enum LabelPrintMissReason: String, CaseIterable, Sendable {
    case absent, pending, rendering, failed
}

enum LabelPrintLookup: Equatable {
    case ready(CGImage)
    case fallback(LabelPrintMissReason)
}

@MainActor
protocol LabelPrintRendering {
    func render(_ key: LabelPrintKey) -> CGImage?
}

/// 以 ImageRenderer 畫**現行** LabelRing（白字、透明底）：字形、字距、反鋸齒與即時路徑同一個引擎（§11.3）。
/// 只能在沒有 G7 時呼叫（store 守）
struct ImageRendererLabelPrint: LabelPrintRendering {
    func render(_ key: LabelPrintKey) -> CGImage? {
        let view = LabelRing(diameter: key.diameter, tint: .white).frame(width: key.canvasSide, height: key.canvasSide)
        let renderer = ImageRenderer(content: view)
        renderer.scale = key.scale
        renderer.isOpaque = false
        return renderer.cgImage
    }
}

/// G7 轉場的開始／結束通知（G7Trace 呼叫）；end 回傳寫進 signpost end 的 note
@MainActor
protocol G7TransitionObserver: AnyObject {
    func transitionBegan()
    func transitionEnded() -> String
    /// G7 signpost 已收尾之後才呼叫：轉場中延後的工作在這裡做，不算進 G7 interval
    func transitionClosed()
}

/// CR-039 §11 S2：標籤印字遮罩的快取。`lookup` 純讀（被觀察，畫好時視圖重繪）；`request` 在沒有 G7 時同步畫一次，
/// G7 進行中只標 pending、G7 結束才畫。非使用中最多 2 張；使用中的不淘汰（可暫時超額）。畫失敗不重試同鍵
@MainActor
@Observable
final class LabelPrintStore: G7TransitionObserver {
    enum Entry {
        case pending
        case ready(CGImage)
        case failed
    }

    static let idleCapacity = 2
    static let shared = LabelPrintStore(renderer: ImageRendererLabelPrint())

    private static let log = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "turntable")
    /// 與 G7 分開的 category（同 category 會被 g7_segments.py 當成 G7 列）；message＝`render=<n>`（n＝renderCount，連號供 parser 查缺號／重複）
    static let renderSignpostCategory = "TurntableLabelPrint"
    static func renderSignpostMessage(ordinal: Int) -> String { "render=\(ordinal)" }
    private static let signposter = OSSignposter(subsystem: "com.ibridgezhao.yogsothothsecho", category: renderSignpostCategory)

    private var entries: [LabelPrintKey: Entry] = [:]
    @ObservationIgnored private let renderer: (any LabelPrintRendering)?
    /// 已就緒的鍵，舊 → 新
    @ObservationIgnored private var recency: [LabelPrintKey] = []
    @ObservationIgnored private var inUse: [LabelPrintKey: Int] = [:]
    @ObservationIgnored private var isTransitioning = false
    /// 本次轉場的 logical miss：同鍵只記一次
    @ObservationIgnored private var misses: [LabelPrintKey: LabelPrintMissReason] = [:]
    /// 實際啟動 renderer 的次數（B8：每次都要有一個 `LabelPrintRender` interval）
    @ObservationIgnored private(set) var renderCount = 0

    init(renderer: (any LabelPrintRendering)?) {
        self.renderer = renderer
    }

    func lookup(_ key: LabelPrintKey) -> LabelPrintLookup {
        switch entries[key] {
        case .ready(let image): .ready(image)
        case .pending: .fallback(.pending)
        case .failed: .fallback(.failed)
        case nil: .fallback(.absent)
        }
    }

    var inUseCount: Int { inUse.values.reduce(0, +) }
    var readyCount: Int { entries.values.filter { if case .ready = $0 { true } else { false } }.count }

    func request(_ key: LabelPrintKey) {
        switch entries[key] {
        case .ready:
            touch(key)
            return
        case .failed:
            return
        case .pending, nil:
            break
        }
        guard !isTransitioning else {
            entries[key] = .pending
            recordMiss(key)
            return
        }
        render(key)
    }

    /// 視圖的作用域：顯示期間登記使用中（不被淘汰）；任務取消（視圖消失、鍵改變）時註銷。
    /// 使用中／最近使用的記帳與 `SwirlArtworkStore.use` 同一套（要抽共用元件時兩邊一起改）
    func use(_ key: LabelPrintKey) async {
        inUse[key, default: 0] += 1
        request(key)
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        let remaining = inUse[key, default: 1] - 1
        inUse[key] = remaining > 0 ? remaining : nil
        evictIdle()
    }

    func transitionBegan() {
        isTransitioning = true
        misses = [:]
        for key in inUse.keys { recordMiss(key) }
    }

    func transitionEnded() -> String {
        isTransitioning = false
        let counts = Dictionary(grouping: misses.values, by: { $0 }).mapValues(\.count)
        misses = [:]
        let reasons = LabelPrintMissReason.allCases.map { "\($0.rawValue):\(counts[$0, default: 0])" }.joined(separator: ",")
        return "misses=\(counts.values.reduce(0, +)) reasons=\(reasons)"
    }

    /// G7 中標成 pending 的鍵在 signpost 收尾後才畫（simcodex r2：在 end 前畫會把 ImageRenderer 算進轉場）
    func transitionClosed() {
        guard !isTransitioning else { return }
        let pending = entries.compactMap { key, entry in if case .pending = entry { key } else { nil } }
        for key in pending { render(key) }
    }

    private func recordMiss(_ key: LabelPrintKey) {
        guard isTransitioning, misses[key] == nil, case .fallback(let reason) = lookup(key) else { return }
        misses[key] = reason
    }

    private func render(_ key: LabelPrintKey) {
        guard let renderer else {
            entries[key] = .failed
            return
        }
        renderCount += 1
        let message = Self.renderSignpostMessage(ordinal: renderCount)
        let state = Self.signposter.beginInterval("LabelPrintRender", id: Self.signposter.makeSignpostID(), "\(message, privacy: .public)")
        let image = renderer.render(key)
        Self.signposter.endInterval("LabelPrintRender", state)
        guard let image else {
            Self.log.error("label print render failed")
            entries[key] = .failed
            return
        }
        entries[key] = .ready(image)
        touch(key)
        evictIdle()
    }

    private func touch(_ key: LabelPrintKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictIdle() {
        var idle = recency.filter { inUse[$0, default: 0] == 0 }
        while idle.count > Self.idleCapacity {
            let victim = idle.removeFirst()
            recency.removeAll { $0 == victim }
            entries[victim] = nil
        }
    }
}
