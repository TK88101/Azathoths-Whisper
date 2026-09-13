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
    /// runner marks（未設證據目錄時整個物件是 no-op，計劃 §5.7 (10)）
    private let marks: CoverFlowMarks?

    // MARK: 遙測（§5.7 (9)：只增報告輸出，判定一個字都不動）

    /// 最近一次 `readStable` 的截圖窗口
    private var lastShot: CoverFlowReportTelemetry.ShotWindow?
    /// 最近一次 `waitForStableCenter` 的耗時與輪詢次數
    private var lastSettle: CoverFlowReportTelemetry.Settle?

    /// 報告用的量測旁註：與 `GateVerdict` 分開，確保它進不了判定
    struct Telemetry {
        let shot: CoverFlowReportTelemetry.ShotWindow?
        let settle: CoverFlowReportTelemetry.Settle?
        let samples: [CoverFlowReportTelemetry.PixelSample]
    }

    /// `pixelAt` 的呼叫記錄器。**不是** `self`：判定閉包由 `CoverFlowGateLogic.evaluate`（非隔離）呼叫，
    /// 捕獲一個不帶隔離的小物件比捕獲 `@MainActor` 的探針乾淨
    private final class PixelRecorder {
        private(set) var samples: [CoverFlowReportTelemetry.PixelSample] = []

        func record(point: CGPoint, candidates: [Int], classification: GatePixelClass) {
            samples.append(CoverFlowReportTelemetry.PixelSample(
                point: point, candidates: candidates, classification: classification
            ))
        }
    }

    init(app: XCUIApplication, marks: CoverFlowMarks? = nil) {
        self.app = app
        self.marks = marks
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
            // 截圖起訖進 marks 與報告：兩格不一致（T1.s3／T2.s2）要能問「PASS 與 FAIL 之差是否落在這個窗口內」
            marks?.record(.shotBegin)
            let begin = CoverFlowTraceFormat.nowEpochMicroseconds()
            let image = app.windows.firstMatch.screenshot().image
            let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            lastShot = CoverFlowReportTelemetry.ShotWindow(
                beginMicroseconds: begin, endMicroseconds: CoverFlowTraceFormat.nowEpochMicroseconds()
            )
            marks?.record(.shotEnd)
            guard let pixels, let after = readState() else { continue }
            if before.stabilityKey == after.stabilityKey { return (after, pixels) }
        }
        return nil
    }

    /// 落定：連續 `settleReadings` 次相同讀數。streak 與逾時分流都在 `GateSettleTracker`（純邏輯、有單測）；
    /// 讀取失敗會清空 streak，不會把斷續的成功拼成「連續」
    func waitForStableCenter() -> Settle {
        var tracker = GateSettleTracker(required: Self.settleReadings)
        var last: State?
        var polls = 0
        let start = Date()
        let deadline = start.addingTimeInterval(Self.settleTimeout)
        while Date() < deadline {
            polls += 1
            let state = readState()
            if let state { last = state }
            tracker = tracker.observing(state?.reading)
            if tracker.isSettled, let state {
                recordSettle(since: start, polls: polls)
                return .settled(state)
            }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        recordSettle(since: start, polls: polls)
        guard tracker.outcome == .neverSettles, let last else { return .axUnreadable }
        return .neverSettles(last)
    }

    /// 落定耗時與輪詢次數只進報告（F3b (c) 的觀察者效應要比對 ON／OFF 中位數），不進判定
    private func recordSettle(since start: Date, polls: Int) {
        lastSettle = CoverFlowReportTelemetry.Settle(
            milliseconds: Int((Date().timeIntervalSince(start) * 1000).rounded()), polls: polls
        )
    }

    /// 捲動：走**座標式**而非元素式。S4 實測 `strip.scroll(byDeltaX:)` 報
    /// `Unable to find hit point for ScrollView`（元素式要先解 hit point，被上層覆蓋層擋掉）；
    /// 座標式直接用絕對座標，不需 hit-test（計劃 §4 的 S4 預登記備案）
    func scroll(byDeltaX deltaX: CGFloat) {
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .scroll(byDeltaX: deltaX, deltaY: 0)
    }

    /// 螢幕座標的點 → 視窗截圖的像素（5×5 平均，轉 sRGB）→ 在候選卡與背景之間分類
    /// `recorder` 只旁聽（點、候選卡、分類結果進報告）；分類本身與呼叫次序完全不變。
    /// 只有 `assertContract` 用它，故與 `PixelRecorder` 一同收成 private
    private func pixelClassifier(
        image: CGImage, windowFrame: CGRect, recorder: PixelRecorder? = nil
    ) -> (CGPoint, [Int]) -> GatePixelClass {
        let scale = CGFloat(image.width) / max(windowFrame.width, 1)
        return { point, candidates in
            let pixel = CGPoint(x: (point.x - windowFrame.minX) * scale, y: (point.y - windowFrame.minY) * scale)
            let rect = CGRect(x: pixel.x - 2, y: pixel.y - 2, width: 5, height: 5)
            let sample = CoverFlowGateLogic.averageSRGB(of: image, pixelRect: rect)
            let classification = sample.map {
                CoverFlowGateLogic.classify($0, candidates: candidates, threshold: Self.colourThreshold)
            } ?? .uncertain
            recorder?.record(point: point, candidates: candidates, classification: classification)
            return classification
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
            report(unstable, state: nil, image: nil, samples: [], in: testCase, file: file, line: line)
            return nil
        }
        let recorder = PixelRecorder()
        let measurement = GateMeasurement(
            step: step, stripMidX: state.stripFrame.midX, label: state.label, cards: state.cards,
            wantIndex: want,
            pixelAt: pixelClassifier(image: image, windowFrame: state.windowFrame, recorder: recorder)
        )
        let evaluated = CoverFlowGateLogic.evaluate(measurement, config: Self.config)
        let verdict = GateVerdict(
            step: step, findings: evaluated.findings + extra, notes: evaluated.notes + notes
        )
        report(verdict, state: state, image: image, samples: recorder.samples, in: testCase, file: file, line: line)
        return verdict
    }

    /// 不走契約的單一判決（探針前置失敗、C6 不收斂等）也用同一格式回報，腳本才數得到
    func reportSingle(
        step: String, code: String, detail: String, in testCase: XCTestCase,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let verdict = GateVerdict(step: step, findings: [GateFinding(code: code, detail: detail)], notes: [])
        report(verdict, state: readState(), image: nil, samples: [], in: testCase, file: file, line: line)
    }

    private func report(
        _ verdict: GateVerdict, state: State?, image: CGImage?,
        samples: [CoverFlowReportTelemetry.PixelSample], in testCase: XCTestCase,
        file: StaticString, line: UInt
    ) {
        print(verdict.gateLine)
        let telemetry = Telemetry(shot: lastShot, settle: lastSettle, samples: samples)
        let text = Self.describe(verdict, state: state, telemetry: telemetry)
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

    private static func describe(_ verdict: GateVerdict, state: State?, telemetry: Telemetry) -> String {
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
        // §5.7 (9)：只增輸出。行首避開 GATE{／SIG{／[PROBE-，判定腳本的前綴分類不受影響
        lines += [
            CoverFlowReportTelemetry.settleLine(telemetry.settle),
            CoverFlowReportTelemetry.shotLine(telemetry.shot),
        ].compactMap { $0 }
        lines += CoverFlowReportTelemetry.sampleLines(telemetry.samples)
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

    typealias BindSample = CoverFlowTraceFormat.BindSample

    /// binding 回寫值 → 帶時間戳的三型樣本（fixture／字面 nil／unknown；計劃 §5.7 (2)）。
    /// unknown 在 fixture 模式下＝探針故障，由呼叫端記 `PROBE-TRACE`
    static func bindRecords(_ snapshot: CoverFlowTraceFormat.Snapshot) -> [BindSample] {
        CoverFlowTraceFormat.bindSamples(snapshot)
    }

    /// 舊介面的包裝：`writebackFindings` 仍吃 `[Int?]`（literalNil 與 unknown 皆為 nil，語義不變）
    static func bindIndices(_ snapshot: CoverFlowTraceFormat.Snapshot) -> [Int?] {
        bindRecords(snapshot).map(\.value.fixtureIndex)
    }
}
