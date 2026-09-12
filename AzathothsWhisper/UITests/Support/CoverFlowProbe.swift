import AppKit
import XCTest

/// H-02 UI 測試閘門的量測殼（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.6）。
///
/// **只量、不判**：AX frame、label、像素、軌跡都在這裡讀；紅綠一律交給 `CoverFlowGateLogic`
/// （與 app 同編、已有單元測試）。這樣判定邏輯不會只在真機 UI 上「碰運氣」地被驗證。
/// `@MainActor`：XCUI 型別皆為主 actor 隔離，`XCUIElementSnapshot` 不是 Sendable，不能跨隔離回傳
@MainActor
final class CoverFlowProbe {
    private typealias Fixture = CoverFlowUITestFixture

    struct State {
        let stripFrame: CGRect
        let label: String?
        let cards: [GateCard]
        let windowFrame: CGRect

        var reading: GateReading { GateReading(label: label, cards: cards, stripMidX: stripFrame.midX) }
        var stabilityKey: GateStabilityKey {
            CoverFlowGateLogic.stabilityKey(
                label: label, cards: cards, stripFrame: stripFrame, windowFrame: windowFrame
            )
        }
        var labelIndex: Int? { label.flatMap(CoverFlowUITestFixture.index(of:)) }
    }

    enum Settle {
        case settled(State)
        /// AX 可讀、frame 一直在變（產品：不收斂）
        case neverSettles(State)
        /// AX 讀不到（探針）
        case axUnreadable
    }

    // MARK: 凍結參數（S 階段校準後寫進計劃 §11，閘門期間不得改）

    /// 未旋轉卡片外框高／寬＝**2.0**（S1 實測：中心卡 260×520；倒影元素回報的是未裁剪高度，
    /// 不是由 0.45 倒影比例推得的 1.45）。兩側實測 2.356（247×582）與 3.487（177×619），區分力充足
    static let unrotatedAspect: CGFloat = 2.0
    static let colourThreshold = 0.35
    static let pollInterval: TimeInterval = 0.1
    static let settleReadings = 4
    static let settleTimeout: TimeInterval = 10
    static let holdDuration: TimeInterval = 1.5
    static let traceQuiet: TimeInterval = 0.5
    static let stableRetries = 3

    static let config = GateConfig(
        itemWidth: Fixture.itemWidth, stride: Fixture.stride,
        unrotatedAspect: unrotatedAspect, trackCount: Fixture.trackCount
    )

    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var strip: XCUIElement { app.descendants(matching: .any)["coverflow-strip"].firstMatch }
    var label: XCUIElement { app.descendants(matching: .any)["coverflow-center-label"].firstMatch }

    // MARK: 讀

    /// 一次 snapshot（原子）：strip 外框、label 值、全部卡片外框
    func readState() -> State? {
        let window = app.windows.firstMatch
        guard let root = try? window.snapshot() else { return nil }
        var stripFrame: CGRect?
        var labelValue: String?
        var frames: [Int: CGRect] = [:]
        Self.walk(root) { node in
            let identifier = node.identifier
            if identifier == "coverflow-strip" {
                stripFrame = node.frame
            } else if identifier == "coverflow-center-label" {
                labelValue = node.value as? String
            } else if identifier.hasPrefix("coverflow-item-"),
                      let index = Fixture.index(of: String(identifier.dropFirst("coverflow-item-".count))) {
                // 同一張卡若被拆成多個元素（例如正面／倒影），取聯集＝整張卡的外框
                frames[index] = frames[index].map { $0.union(node.frame) } ?? node.frame
            }
        }
        guard let stripFrame else { return nil }
        let cards = frames.map { GateCard(index: $0.key, frame: $0.value) }.sorted { $0.index < $1.index }
        return State(stripFrame: stripFrame, label: labelValue, cards: cards, windowFrame: root.frame)
    }

    /// snapshot → 截圖 → snapshot，兩次**全部幾何**一致才採用：frame 與像素必須是同一個畫面（TV6）。
    /// 單次讀取失敗也用掉一次重試（而不是直接放棄），否則瞬時 AX 失敗會變成不必要的 PROBE 紅燈
    func readStable() -> (State, CGImage)? {
        for _ in 0..<Self.stableRetries {
            guard let before = readState() else { continue }
            let image = app.windows.firstMatch.screenshot().image
            guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let after = readState()
            else { continue }
            if before.stabilityKey == after.stabilityKey { return (after, pixels) }
        }
        return nil
    }

    /// 落定：連續 `settleReadings` 次相同讀數。streak 與逾時分流都在 `GateSettleTracker`（純邏輯、有單測）；
    /// 讀取失敗會清空 streak，不會把斷續的成功拼成「連續」
    func waitForStableCenter() -> Settle {
        var tracker = GateSettleTracker(required: Self.settleReadings)
        var last: State?
        let deadline = Date().addingTimeInterval(Self.settleTimeout)
        while Date() < deadline {
            let state = readState()
            if let state { last = state }
            tracker = tracker.observing(state?.reading)
            if tracker.isSettled, let state { return .settled(state) }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        guard tracker.outcome == .neverSettles, let last else { return .axUnreadable }
        return .neverSettles(last)
    }

    /// 捲動：走**座標式**而非元素式。S4 實測 `strip.scroll(byDeltaX:)` 報
    /// `Unable to find hit point for ScrollView`（元素式要先解 hit point，被上層覆蓋層擋掉）；
    /// 座標式直接用絕對座標，不需 hit-test（計劃 §4 的 S4 預登記備案）
    func scroll(byDeltaX deltaX: CGFloat) {
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .scroll(byDeltaX: deltaX, deltaY: 0)
    }

    /// 螢幕座標的點 → 視窗截圖的像素（5×5 平均，轉 sRGB）→ 在候選卡與背景之間分類
    func pixelClassifier(image: CGImage, windowFrame: CGRect) -> (CGPoint, [Int]) -> GatePixelClass {
        let scale = CGFloat(image.width) / max(windowFrame.width, 1)
        return { point, candidates in
            let pixel = CGPoint(x: (point.x - windowFrame.minX) * scale, y: (point.y - windowFrame.minY) * scale)
            let rect = CGRect(x: pixel.x - 2, y: pixel.y - 2, width: 5, height: 5)
            guard let sample = CoverFlowGateLogic.averageSRGB(of: image, pixelRect: rect) else { return .uncertain }
            return CoverFlowGateLogic.classify(sample, candidates: candidates, threshold: Self.colourThreshold)
        }
    }

    // MARK: 判定與回報

    /// 跑落定契約並回報：一行 `GATE{…}`（stdout）＋ 文字報告與視窗截圖附件 ＋ 每條違反一個 XCTFail。
    /// `extra`＝路徑專屬條款（C4 軌跡、C5 重建保持），併入同一步驟的判決
    @discardableResult
    func assertContract(
        step: String, want: Int?, extra: [GateFinding] = [], notes: [String] = [], in testCase: XCTestCase,
        file: StaticString = #filePath, line: UInt = #line
    ) -> GateVerdict? {
        guard let (state, image) = readStable() else {
            let unstable = GateVerdict(
                step: step, findings: [GateFinding(code: "PROBE-UNSTABLE", detail: "")], notes: notes
            )
            report(unstable, state: nil, image: nil, in: testCase, file: file, line: line)
            return nil
        }
        let measurement = GateMeasurement(
            step: step, stripMidX: state.stripFrame.midX, label: state.label, cards: state.cards,
            wantIndex: want, pixelAt: pixelClassifier(image: image, windowFrame: state.windowFrame)
        )
        let evaluated = CoverFlowGateLogic.evaluate(measurement, config: Self.config)
        let verdict = GateVerdict(
            step: step, findings: evaluated.findings + extra, notes: evaluated.notes + notes
        )
        report(verdict, state: state, image: image, in: testCase, file: file, line: line)
        return verdict
    }

    /// 不走契約的單一判決（探針前置失敗、C6 不收斂等）也用同一格式回報，腳本才數得到
    func reportSingle(
        step: String, code: String, detail: String, in testCase: XCTestCase,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let verdict = GateVerdict(step: step, findings: [GateFinding(code: code, detail: detail)], notes: [])
        report(verdict, state: readState(), image: nil, in: testCase, file: file, line: line)
    }

    private func report(
        _ verdict: GateVerdict, state: State?, image: CGImage?, in testCase: XCTestCase,
        file: StaticString, line: UInt
    ) {
        print(verdict.gateLine)
        let text = Self.describe(verdict, state: state)
        print(text)
        let textAttachment = XCTAttachment(string: text)
        textAttachment.name = "\(verdict.step)-report"
        textAttachment.lifetime = .keepAlways
        testCase.add(textAttachment)
        if let image {
            // `app.windows.firstMatch.screenshot()`：只含本 app 視窗，不含使用者的其他畫面
            let shot = XCTAttachment(image: NSImage(cgImage: image, size: .zero))
            shot.name = "\(verdict.step)-window"
            shot.lifetime = .keepAlways
            testCase.add(shot)
        }
        let previous = testCase.continueAfterFailure
        testCase.continueAfterFailure = true
        defer { testCase.continueAfterFailure = previous }
        for message in verdict.failureMessages {
            XCTFail(message, file: file, line: line)
        }
    }

    private static func describe(_ verdict: GateVerdict, state: State?) -> String {
        var lines = ["step=\(verdict.step) findings=\(verdict.findings.count) notes=\(verdict.notes)"]
        if let state {
            lines.append("window=\(state.windowFrame) strip=\(state.stripFrame) label=\(state.label ?? "nil")")
            for card in state.cards {
                let aspect = card.frame.height / max(card.frame.width, 1)
                lines.append(String(
                    format: "  %@ midX=%.1f dx=%.1f %.1fx%.1f aspect=%.3f",
                    Fixture.persistentID(at: card.index), card.frame.midX,
                    card.frame.midX - state.stripFrame.midX, card.frame.width, card.frame.height, aspect
                ))
            }
        }
        lines += verdict.failureMessages.map { "  ! \($0)" }
        return lines.joined(separator: "\n")
    }

    private static func walk(_ node: XCUIElementSnapshot, _ visit: (XCUIElementSnapshot) -> Void) {
        visit(node)
        for child in node.children { walk(child, visit) }
    }
}

// MARK: - 軌跡（計劃 §3.5：runner 只讀水位之後的行，不截斷檔案）

struct CoverFlowTraceSession {
    let path: String

    /// 水位＝**最後一個完整行**之後的位移（不是檔案大小）：半行或殘尾若被算進水位，
    /// 下一段就會從行中間讀起，那些位元組永遠不會被檢查
    func watermark() -> UInt64 {
        read(from: 0)?.endOffset ?? 0
    }

    func read(from offset: UInt64) -> CoverFlowTraceFormat.Snapshot? {
        try? CoverFlowTraceFormat.read(path: path, fromOffset: offset)
    }

    func header() -> CoverFlowTraceFormat.Header? {
        read(from: 0)?.header
    }

    /// 全檔 audit（從 0 重讀）：水位讀取會永久跳過前綴裡的問題，每條測試結束前必須補這一次
    func audit() -> [String] {
        CoverFlowTraceFormat.audit(path: path)
    }

    /// 讀到軌跡靜止（`quiet` 內無新行，最多等 `limit`）為止；回傳水位之後的全部記錄
    func readUntilQuiet(
        from offset: UInt64, quiet: TimeInterval, limit: TimeInterval = 5
    ) -> CoverFlowTraceFormat.Snapshot? {
        let deadline = Date().addingTimeInterval(limit)
        var lastOffset: UInt64?
        var lastChange = Date()
        while Date() < deadline {
            guard let snapshot = read(from: offset) else { return nil }
            // 以位移（不是記錄數）判活動：錯誤行／壞行也是新資料，不能被當成「靜止」
            if snapshot.endOffset != lastOffset {
                lastOffset = snapshot.endOffset
                lastChange = Date()
            } else if Date().timeIntervalSince(lastChange) >= quiet {
                return snapshot
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return read(from: offset)
    }

    /// binding 回寫值 → fixture 索引；非 fixture 值（含 SwiftUI 回寫的 nil）記為 nil
    static func bindIndices(_ snapshot: CoverFlowTraceFormat.Snapshot) -> [Int?] {
        snapshot.records.filter { $0.kind == .bind }.map { CoverFlowUITestFixture.index(of: $0.payload) }
    }
}
