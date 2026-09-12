// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import CoreGraphics
import Foundation

// H-02 UI 測試閘門的判定純邏輯（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.6–3.7）。
//
// UITest 只負責「量」（AX frame、label、像素），紅綠一律由這裡決定——
// 判定因此能在單元測試裡用假畫面逐條驗證，而不是只在真機 UI 上碰運氣。
// app 與 UITests 兩個 target 同編此檔（見 project.yml）。

/// AX 樹上的一張卡：fixture 索引 ＋ 變換後的外接矩形（螢幕座標）
struct GateCard: Equatable, Sendable {
    let index: Int
    let frame: CGRect
}

/// 取樣點的分類。只在「給定候選卡 ＋ 背景」之間判；落在其他卡色上＝`uncertain`
enum GatePixelClass: Equatable, Sendable {
    case card(Int)
    case background
    case uncertain
}

struct GateConfig: Sendable {
    let itemWidth: CGFloat
    let stride: CGFloat
    /// 未旋轉卡片外框的高／寬（含倒影），由 S1 實測後凍結
    let unrotatedAspect: CGFloat
    let trackCount: Int
    var centerTolerance: CGFloat = 3
    var widthTolerance: CGFloat = 0.03
    var aspectTolerance: CGFloat = 0.05
}

/// 一個落定步驟的量測。`pixelAt(點, 候選卡索引)` 由 UITest 以截圖實作，單元測試以假畫面實作
struct GateMeasurement {
    let step: String
    let stripMidX: CGFloat
    /// label 的 AX value（＝VM 的 centerID）；空字串或 nil 表示沒有中心
    let label: String?
    let cards: [GateCard]
    /// 本步驟的命令目標（C3）；nil＝本步驟沒有命令目標
    let wantIndex: Int?
    let pixelAt: (CGPoint, [Int]) -> GatePixelClass
}

struct GateFinding: Equatable, Sendable {
    let code: String
    let detail: String

    /// 探針碼不計入閘門判決（計劃 §3.7）
    var isProbe: Bool { code.hasPrefix("PROBE-") }
}

struct GateVerdict: Equatable, Sendable {
    let step: String
    let findings: [GateFinding]
    let notes: [String]

    var isPass: Bool { findings.isEmpty }

    /// 每個落定步驟一行，供 Scripts/h02_gate_eval.py 逐步驟判定
    var gateLine: String {
        guard !isPass else { return "GATE{\(step)|PASS}" }
        let codes = Set(findings.map(\.code)).sorted().joined(separator: ",")
        return "GATE{\(step)|FAIL|\(codes)}"
    }

    /// XCTFail 的訊息。產品碼以 `SIG{` 開頭、探針碼以 `[PROBE-` 開頭——腳本靠這兩個前綴分類
    var failureMessages: [String] {
        findings.map { finding in
            if finding.isProbe {
                return "[\(finding.code)] \(step)" + (finding.detail.isEmpty ? "" : " \(finding.detail)")
            }
            return "SIG{\(step)|\(finding.code)" + (finding.detail.isEmpty ? "" : "|\(finding.detail)") + "}"
        }
    }
}

/// 落定輪詢的一次讀數：label、幾何中心卡、其外框（取 0.5pt 精度，濾掉次像素抖動）
struct GateReading: Equatable, Sendable {
    let label: String?
    let centerIndex: Int?
    let frameKey: [Int]
}

/// 截圖前後的穩定鍵（TV6）：**全部**幾何都要是同一個畫面——只比中心卡的話，鄰張在
/// snapshot 與截圖之間移動仍會被當成穩定，於是用 A 時刻的 frame 去取 B 時刻的像素，產生假 C2
struct GateStabilityKey: Equatable, Sendable {
    let label: String?
    let strip: [Int]
    let window: [Int]
    let cards: [[Int]]
}

/// 落定輪詢逾時後的分流（§3.6 TV4）
enum GateSettleOutcome: Equatable, Sendable {
    case settled
    /// AX 可讀、frame 仍在變 → 產品 `C6-NEVER-SETTLES`
    case neverSettles
    /// AX 讀不到（最後一次讀失敗、樣本不足、或中心卡讀不到）→ 探針 `[PROBE-AX]`
    case axUnreadable
}

/// 落定輪詢的狀態（§3.6）：連續 `required` 次相同讀數＝落定。
/// **讀取失敗即清空 streak**（R5-4 Round 2 P1 ①）——否則「成功×3＋失敗＋成功」會被當成連續四次而提前落定，
/// 繞過逾時分流。逾時分流另看**全部**成功樣本（不清空）：一次晚期讀取失敗不得把真正在動的產品 C6 降成探針碼
/// （2026-09-12 對抗核查）。不可變：每次觀察回傳新值
struct GateSettleTracker: Equatable, Sendable {
    let required: Int
    /// 連續成功讀數（讀取失敗即清空）——只決定「是否落定」
    private(set) var streak: [GateReading] = []
    /// 全部成功讀數（不清空）——逾時分流用
    private(set) var samples: [GateReading] = []
    private(set) var lastReadFailed = true

    init(required: Int) {
        self.required = required
    }

    func observing(_ reading: GateReading?) -> GateSettleTracker {
        var next = self
        guard let reading else {
            next.streak = []
            next.lastReadFailed = true
            return next
        }
        next.streak = streak + [reading]
        next.samples = samples + [reading]
        next.lastReadFailed = false
        return next
    }

    var isSettled: Bool { CoverFlowGateLogic.isSettled(streak, required: required) }

    var outcome: GateSettleOutcome {
        isSettled
            ? .settled
            : CoverFlowGateLogic.timeoutOutcome(samples: samples, required: required, lastReadFailed: lastReadFailed)
    }
}

extension GateReading {
    init(label: String?, cards: [GateCard], stripMidX: CGFloat) {
        let center = CoverFlowGateLogic.geometricCenter(of: cards, stripMidX: stripMidX)
        let key = center.map { card in
            [card.frame.minX, card.frame.minY, card.frame.width, card.frame.height]
                .map { Int(($0 * 2).rounded()) }
        } ?? []
        self.init(label: label, centerIndex: center?.index, frameKey: key)
    }
}

enum CoverFlowGateLogic {
    private enum Side: CaseIterable {
        case left, right

        var delta: Int { self == .left ? -1 : 1 }
        var code: String { self == .left ? "L" : "R" }
    }

    private static let black = GateRGB(red: 0, green: 0, blue: 0)

    private static func id(_ index: Int) -> String {
        CoverFlowUITestFixture.persistentID(at: index)
    }

    // MARK: 原語

    static func distance(_ a: GateRGB, _ b: GateRGB) -> Double {
        let dr = a.red - b.red, dg = a.green - b.green, db = a.blue - b.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// 在候選卡色與背景（近黑）之間取最近者；最近者也超過閾值＝不確定
    static func classify(_ sample: GateRGB, candidates: [Int], threshold: Double) -> GatePixelClass {
        var best = (GatePixelClass.background, distance(sample, black))
        for index in candidates {
            let d = distance(sample, CoverFlowUITestFixture.color(at: index))
            if d < best.1 { best = (.card(index), d) }
        }
        return best.1 <= threshold ? best.0 : .uncertain
    }

    /// 影像某像素矩形的平均色，**轉成 sRGB**（原點左上、像素單位）。
    ///
    /// 經 CoreGraphics 把裁切區畫進 sRGB 位圖再讀位元組，由 CG 做色彩匹配。
    /// 不用 `NSBitmapImageRep.colorAt(...).usingColorSpace(.sRGB)`：那條路徑會再套一次裝置描述檔，
    /// 實測把色板色推偏 0.08–0.16（CoverFlowUITestMusicTests 抓到的）。矩形超出影像＝nil
    static func averageSRGB(of image: CGImage, pixelRect: CGRect) -> GateRGB? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = pixelRect.integral
        guard bounds.contains(rect), !rect.isEmpty,
              let crop = image.cropping(to: rect),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let width = Int(rect.width), height = Int(rect.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var sums = (0.0, 0.0, 0.0)
        for offset in Swift.stride(from: 0, to: bytes.count, by: 4) {
            sums.0 += Double(bytes[offset])
            sums.1 += Double(bytes[offset + 1])
            sums.2 += Double(bytes[offset + 2])
        }
        let scale = Double(width * height) * 255
        return GateRGB(red: sums.0 / scale, green: sums.1 / scale, blue: sums.2 / scale)
    }

    /// 正面朝人：滿寬（scale 1.0）且外框長寬比等於未旋轉基準（任何側轉都會縮寬增高）
    static func isFacing(_ size: CGSize, config: GateConfig) -> Bool {
        guard size.width > 0, config.itemWidth > 0 else { return false }
        return abs(size.width / config.itemWidth - 1) <= config.widthTolerance
            && abs(size.height / size.width - config.unrotatedAspect) < config.aspectTolerance
    }

    static func strideBucket(offset: CGFloat, stride: CGFloat) -> Int {
        guard stride > 0 else { return 0 }
        return Int((offset / stride).rounded())
    }

    static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    static func geometricCenter(of cards: [GateCard], stripMidX: CGFloat) -> GateCard? {
        cards.min { abs($0.frame.midX - stripMidX) < abs($1.frame.midX - stripMidX) }
    }

    /// 卡面帶：正對觀者那張的正面中線（外框含倒影，正面是上方的 width×width）
    static func faceBandY(of centre: CGRect) -> CGFloat {
        centre.minY + centre.width / 2
    }

    /// 兩外框水平交集的中點；不交＝nil（負間距下相鄰卡必然交疊，不交是佈局錯）
    static func overlapSamplePoint(centre: CGRect, neighbour: CGRect) -> CGPoint? {
        let low = max(centre.minX, neighbour.minX)
        let high = min(centre.maxX, neighbour.maxX)
        guard high > low else { return nil }
        return CGPoint(x: (low + high) / 2, y: faceBandY(of: centre))
    }

    /// 鄰張的無遮擋參考點：中心卡外緣與再下一張內緣之間的中點；該區間不存在＝nil
    static func neighbourReferencePoint(centre: CGRect, neighbour: CGRect, beyond: CGRect?) -> CGPoint? {
        let isRight = neighbour.midX > centre.midX
        let low = isRight ? centre.maxX : (beyond?.maxX ?? neighbour.minX)
        let high = isRight ? (beyond?.minX ?? neighbour.maxX) : centre.minX
        guard high > low else { return nil }
        return CGPoint(x: (low + high) / 2, y: faceBandY(of: centre))
    }

    static func isSettled(_ readings: [GateReading], required: Int) -> Bool {
        guard required > 0, readings.count >= required else { return false }
        let tail = readings.suffix(required)
        guard let first = tail.first, first.centerIndex != nil else { return false }
        return tail.allSatisfy { $0 == first }
    }

    static func settleOutcome(readings: [GateReading], required: Int, lastReadFailed: Bool) -> GateSettleOutcome {
        isSettled(readings, required: required)
            ? .settled
            : timeoutOutcome(samples: readings, required: required, lastReadFailed: lastReadFailed)
    }

    /// 逾時後判「產品不收斂」還是「探針讀不到」：只有 AX 一路可讀（最後一次也成功、樣本夠、尾段讀得到中心卡）
    /// **且尾段確實仍在變**才算產品 C6——尾段全同卻從未連續四次成功＝AX 斷續失敗，是探針問題，
    /// 不得掛到產品頭上（§3.6 TV4）
    static func timeoutOutcome(samples: [GateReading], required: Int, lastReadFailed: Bool) -> GateSettleOutcome {
        let tail = samples.suffix(required)
        guard !lastReadFailed, samples.count >= required, tail.allSatisfy({ $0.centerIndex != nil }),
              tail.contains(where: { $0 != tail.first })
        else { return .axUnreadable }
        return .neverSettles
    }

    /// TV6 穩定鍵：strip、視窗與**每一張**卡的外框都取 0.5pt 精度
    static func stabilityKey(
        label: String?, cards: [GateCard], stripFrame: CGRect, windowFrame: CGRect
    ) -> GateStabilityKey {
        GateStabilityKey(
            label: label,
            strip: frameKey(stripFrame),
            window: frameKey(windowFrame),
            cards: cards.sorted { $0.index < $1.index }.map { [$0.index] + frameKey($0.frame) }
        )
    }

    /// C5：切 tab 往返後 label 不得改變（§3.7）。任一側為 nil（AX 讀不到；空字串是產品狀態，交 C1 判）＝量測失敗 → 探針碼，
    /// 不得把 AX 失敗寫成 `C5-DRIFT`（R5-4 Round 2 P1 ④）
    static func driftFindings(before: String?, after: String?) -> [GateFinding] {
        guard let before, let after else {
            let detail = "label-unreadable|before=\(before ?? "nil")|after=\(after ?? "nil")"
            return [GateFinding(code: "PROBE-AX", detail: detail)]
        }
        return before == after ? [] : [GateFinding(code: "C5-DRIFT", detail: "before=\(before)|after=\(after)")]
    }

    private static func frameKey(_ frame: CGRect) -> [Int] {
        [frame.minX, frame.minY, frame.width, frame.height].map { Int(($0 * 2).rounded()) }
    }

    // MARK: C4：捲動回寫軌跡

    /// - Parameters:
    ///   - start: 捲動前的 label 索引
    ///   - gesture: 事件發送至落定之間，binding 收到的回寫值（索引；nil＝SwiftUI 回寫了 nil）
    ///   - hold: 落定後保持期內的回寫值
    ///   - settled: 落定時的 label 索引
    static func writebackFindings(start: Int, gesture: [Int?], hold: [Int?], settled: Int?) -> [GateFinding] {
        var sequence = [start]
        for value in gesture.compactMap({ $0 }) where value != sequence.last {
            sequence.append(value)
        }
        var findings: [GateFinding] = []
        if sequence.count == 1 {
            findings.append(GateFinding(code: "C4-NO-WRITEBACK", detail: ""))
        } else if hasReversal(sequence) {
            let seq = sequence.map(id).joined(separator: ">")
            findings.append(GateFinding(code: "C4-REVERSAL", detail: "seq=\(seq)"))
        }
        if let settled, let moved = hold.compactMap({ $0 }).first(where: { $0 != settled }) {
            findings.append(GateFinding(code: "C4-SNAPBACK", detail: "from=\(id(settled))|to=\(id(moved))"))
        }
        return findings
    }

    private static func hasReversal(_ sequence: [Int]) -> Bool {
        var direction = 0
        for (a, b) in zip(sequence, sequence.dropFirst()) {
            let step = (b - a).signum()
            if direction == 0 {
                direction = step
            } else if step != 0, step != direction {
                return true
            }
        }
        return false
    }

    // MARK: 落定契約

    static func evaluate(_ m: GateMeasurement, config: GateConfig) -> GateVerdict {
        guard let g = geometricCenter(of: m.cards, stripMidX: m.stripMidX) else {
            return GateVerdict(step: m.step, findings: [GateFinding(code: "PROBE-AX", detail: "cards=0")], notes: [])
        }
        let labelIndex = m.label.flatMap(CoverFlowUITestFixture.index(of:))
        var findings = centeringFindings(m, g: g, labelIndex: labelIndex, config: config)
        if let want = m.wantIndex, labelIndex != want {
            let got = labelIndex.map(id) ?? "none"
            findings.append(GateFinding(code: "C3-TARGET-MISS", detail: "want=\(id(want))|got=\(got)"))
        }
        let facing = isFacing(g.frame.size, config: config)
        let notes = facing ? [] : ["C2-NA|G=\(id(g.index))"]
        // 中心卡參考點兩側共用，只量一次：nil＝未量、.some(nil)＝通過、.some(finding)＝失敗
        var centreReference: GateFinding??
        for side in Side.allCases {
            findings += sideFindings(
                m, g: g, side: side, facing: facing, config: config, centreReference: &centreReference
            )
        }
        return GateVerdict(step: m.step, findings: unique(findings), notes: notes)
    }

    /// C1：label 所指的卡必須就是對正且正對的那張
    private static func centeringFindings(
        _ m: GateMeasurement, g: GateCard, labelIndex: Int?, config: GateConfig
    ) -> [GateFinding] {
        guard let labelIndex else {
            let raw = m.label.flatMap { $0.isEmpty ? nil : $0 } ?? "none"
            return [GateFinding(code: "C1-LABEL-CARD-MISSING", detail: "label=\(raw)")]
        }
        let offset = GateFinding(
            code: "C1-OFFSET",
            detail: "label=\(id(labelIndex))|centered=\(id(g.index))|strides=\(signed(labelIndex - g.index))"
        )
        guard labelIndex == g.index else { return [offset] }
        if abs(g.frame.midX - m.stripMidX) > config.centerTolerance { return [offset] }
        if !isFacing(g.frame.size, config: config) {
            return [GateFinding(code: "C1-NOT-FACING", detail: "label=\(id(labelIndex))")]
        }
        return []
    }

    /// C0 ＋ C2：單側。端點外側沒有鄰張是正常的
    private static func sideFindings(
        _ m: GateMeasurement, g: GateCard, side: Side, facing: Bool, config: GateConfig,
        centreReference: inout GateFinding??
    ) -> [GateFinding] {
        let nIndex = g.index + side.delta
        guard (0..<config.trackCount).contains(nIndex) else { return [] }
        guard let n = m.cards.first(where: { $0.index == nIndex }) else {
            return missingNeighbourFindings(m, g: g, nIndex: nIndex, side: side, config: config)
        }
        guard facing else { return [] }
        let sideDetail = "G=\(id(g.index))|side=\(side.code)"
        guard let overlap = overlapSamplePoint(centre: g.frame, neighbour: n.frame) else {
            return [GateFinding(code: "C2-GAP", detail: sideDetail)]
        }
        let candidates = [g.index, nIndex]
        if centreReference == nil {
            let point = CGPoint(x: g.frame.midX, y: faceBandY(of: g.frame))
            centreReference = .some(referenceFinding(m, card: g.index, at: point, candidates: candidates))
        }
        if let failed = centreReference ?? nil { return [failed] }
        let beyond = m.cards.first(where: { $0.index == nIndex + side.delta })?.frame
        guard let reference = neighbourReferencePoint(centre: g.frame, neighbour: n.frame, beyond: beyond) else {
            return [GateFinding(code: "PROBE-REF", detail: "no-unoccluded|\(sideDetail)")]
        }
        if let failed = referenceFinding(m, card: nIndex, at: reference, candidates: candidates) {
            return [failed]
        }
        switch m.pixelAt(overlap, candidates) {
        case .card(g.index):
            return []
        case .card:
            return [GateFinding(code: "C2-STACK", detail: "G=\(id(g.index))|over=\(id(nIndex))|side=\(side.code)")]
        case .background:
            return [GateFinding(code: "C2-GAP", detail: sideDetail)]
        case .uncertain:
            return [GateFinding(code: "PROBE-OFFCARD", detail: "point=\(format(overlap))")]
        }
    }

    /// 參考點必須分類為該卡本色；背景＝卡片缺位（產品），別的色＝取樣位置錯（探針）
    private static func referenceFinding(
        _ m: GateMeasurement, card: Int, at point: CGPoint, candidates: [Int]
    ) -> GateFinding? {
        switch m.pixelAt(point, candidates) {
        case .card(card): return nil
        case .background: return GateFinding(code: "C0-BLANK-CARD", detail: "card=\(id(card))")
        default: return GateFinding(code: "PROBE-REF", detail: "point=\(format(point))")
        }
    }

    /// C0：AX 樹缺鄰張時看像素——背景＝那一側真的空了（產品）；有卡＝AX 裁剪（探針）
    private static func missingNeighbourFindings(
        _ m: GateMeasurement, g: GateCard, nIndex: Int, side: Side, config: GateConfig
    ) -> [GateFinding] {
        let point = CGPoint(x: g.frame.midX + CGFloat(side.delta) * config.stride, y: faceBandY(of: g.frame))
        let detail = "G=\(id(g.index))|side=\(side.code)"
        switch m.pixelAt(point, [g.index, nIndex]) {
        case .background: return [GateFinding(code: "C0-BLANK-SIDE", detail: detail)]
        default: return [GateFinding(code: "PROBE-AX-CULL", detail: detail)]
        }
    }

    private static func format(_ point: CGPoint) -> String {
        String(format: "%.1f,%.1f", point.x, point.y)
    }

    private static func unique(_ findings: [GateFinding]) -> [GateFinding] {
        var seen: [GateFinding] = []
        for finding in findings where !seen.contains(finding) { seen.append(finding) }
        return seen
    }
}
#endif
