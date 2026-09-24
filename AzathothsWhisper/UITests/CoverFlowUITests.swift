import AppKit
import XCTest

// H-02 Cover Flow 缺陷 2／3 的 UI 閘門（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.8）。
//
// 為何要有這一層：CoverFlowStripRenderGeometryTests 只能程式化設 centerID，三次修復都「單測綠 → 真機錯」。
// 這裡在**真實組裝**（只換 Music）上走使用者會走的四條路徑——捲動、鍵盤、首次載入、切 tab 重建——
// 每個落定步驟跑同一個契約（CoverFlowGateLogic）。紅燈以 `SIG{…}`／`[PROBE-…]` 開頭，
// 由 Scripts/h02_gate_eval.py 逐步驟判定；在回退版上預期會紅，**不得為了轉綠而改判據**（計劃 §6 護欄）。
//
// 紀律：只用 XCUIApplication 定界操作；每次送鍵／捲動前確認 app 在前台，否則中止（memory no-global-keystrokes）。
final class CoverFlowUITests: AppUITestCase {
    private typealias Fixture = CoverFlowUITestFixture

    /// runner 端環境變數（經 `TEST_RUNNER_` 前綴轉發）：本輪預期的 Products 目錄，用於二進位身分斷言（§3.13）
    private static let expectedAppDirVariable = "AZW_EXPECTED_APP_DIR"
    private static let bundleID = "com.ibridgezhao.azathothswhisper"
    /// 約 2 個 stride；方向與單位由 S4 實測（XCUIElement.h：「specified pixels」）
    private static let scrollDelta: CGFloat = 300
    private static let endpointPresses = 25

    private var probe: CoverFlowProbe!
    private var trace: CoverFlowTraceSession!
    /// 步驟邊界（wall-clock µs）；未設 `AZW_EVIDENCE_DIR` 時是 no-op（計劃 §5.7 (10)）
    private var marks: CoverFlowMarks!
    private var evidence: CoverFlowEvidence.Destination!
    private var testLabel = ""

    /// 每條測試結束前對整份軌跡做一次全檔 audit（R5-4 Round 2 P1 ②）：水位讀取只看新行，
    /// 前綴裡的 write-error／malformed／gap 否則永遠不會被檢查。問題以**未歸屬**的 `[PROBE-TRACE]` 上報
    /// （不印 GATE 行——它不是契約步驟），判定腳本據此把該次迭代記 invalid
    override func tearDown() {
        auditTrace()
        marks?.close()
        // 先讓 super 終止被測 app，trace 檔到那一刻才真正定版；manifest 的 md5 必須是最終內容，
        // 否則「app 在 audit 之後又追加了一行」會被判定器讀成證據與清單不符
        super.tearDown()
        writeEvidenceManifest()
    }

    /// `<dir>/<test>-<n>.manifest.json`（計劃 §5.7 (7)）。沒有證據目錄＝閘門輪，維持 R5-5 的行為不寫。
    /// 寫失敗不另發 XCTFail：本檔不得新增產品碼，而「manifest 缺檔」本身就是判定器判運行無效的依據
    private func writeEvidenceManifest() {
        guard let evidence, let directory = evidence.directory, let ordinal = evidence.ordinal else { return }
        let environment = ProcessInfo.processInfo.environment
        do {
            let path = try CoverFlowEvidence.writeManifest(
                directory: directory, test: testLabel, ordinal: ordinal,
                treeHash: environment[CoverFlowEvidence.treeHashVariable] ?? "",
                cdhash: environment[CoverFlowEvidence.cdhashVariable] ?? ""
            )
            print("EVIDENCE \(testLabel)-\(ordinal) manifest=\(path)")
        } catch {
            print("EVIDENCE \(testLabel)-\(ordinal) manifest-error=\(error.localizedDescription)")
        }
    }

    private func auditTrace() {
        guard let trace else { return }
        let problems = trace.audit()
        print("AUDIT \(testLabel).trace problems=\(problems)")
        guard !problems.isEmpty else { return }
        let previous = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previous }
        XCTFail("[PROBE-TRACE] \(testLabel).audit \(problems.joined(separator: ","))")
    }

    // MARK: 四條路徑

    /// 觀測路徑：外部捲動後回寫、不被延遲的 onChange 拉回或反向跳動（C4），落定後契約成立
    @MainActor func testExternalScrollWritesBackAndDoesNotSnapBack() {
        guard launchCoverFlow(test: "T1"), settle(step: "T1.s0") != nil,
              let before = focusAndStepRight(step: "T1.s1")
        else { return }
        probe.assertContract(step: "T1.s1", want: before + 1, in: self)
        scrollStep("T1.s2", deltaX: -Self.scrollDelta)
        scrollStep("T1.s3", deltaX: Self.scrollDelta)
    }

    /// 命令路徑（鍵盤）：兩端都能真的居中，不只是 label 對
    @MainActor func testKeyboardCommandsCanCenterBothEndpoints() {
        guard launchCoverFlow(test: "T2"), settle(step: "T2.s0") != nil,
              let before = focusAndStepRight(step: "T2.s1")
        else { return }
        probe.assertContract(step: "T2.s1", want: before + 1, in: self)
        guard press(.leftArrow, times: Self.endpointPresses, step: "T2.s2"), settle(step: "T2.s2") != nil else { return }
        probe.assertContract(step: "T2.s2", want: 0, in: self)
        guard press(.rightArrow, times: Self.endpointPresses, step: "T2.s3"), settle(step: "T2.s3") != nil else { return }
        probe.assertContract(step: "T2.s3", want: Fixture.trackCount - 1, in: self)
    }

    /// 首次載入自動居中：正對觀者那張不得被傾斜的鄰張壓住（缺陷 2 的使用者可見症狀）
    @MainActor func testCenteredCardPaintsAboveBothNeighbours() {
        guard launchCoverFlow(test: "T3"), settle(step: "T3.s1") != nil else { return }
        probe.assertContract(step: "T3.s1", want: Fixture.playingIndex, in: self)
    }

    /// 初始值路徑：切 tab 往返使 CoverFlowView 以預設 centerID 重建；重建前後同一邏輯狀態都必須成立
    @MainActor func testReenteringTabKeepsCenteredCardCentered() {
        guard launchCoverFlow(test: "T4"), settle(step: "T4.s0") != nil,
              focusAndStepRight(step: "T4.s1") != nil,
              press(.rightArrow, times: Self.endpointPresses - 1, step: "T4.s1"),
              let settledBefore = settle(step: "T4.s1")
        else { return }
        let last = Fixture.trackCount - 1
        probe.assertContract(step: "T4.s1", want: last, in: self)
        // 切 tab 前的 label 取自 T4.s1 的落定狀態（連續 4 次相同讀數），不另做單次無重試的讀取；
        // 落定狀態仍無 label＝量測失敗：報探針並停止本路徑，不得以 "nil" 頂替後被判成 C5-DRIFT
        guard let before = settledBefore.label else {
            probe.reportSingle(step: "T4.s2", code: "PROBE-AX", detail: "no-label-before-tab-switch", in: self)
            return
        }

        app.buttons["EDITOR"].click()
        guard waitForStripToDisappear(step: "T4.s2") else { return }
        app.buttons["COVER FLOW"].click()
        guard waitForLabel(step: "T4.s2"), let rebuilt = settle(step: "T4.s2") else { return }
        let drift = CoverFlowGateLogic.driftFindings(before: before, after: rebuilt.label)
        probe.assertContract(step: "T4.s2", want: last, extra: drift, in: self)
    }

    // MARK: 共同前置

    @MainActor private func launchCoverFlow(test: String) -> Bool {
        let destination = Self.evidenceDestination(test: test)
        var environment = [Fixture.launchFlag: "1", Fixture.tracePathVariable: destination.tracePath]
        if let delay = ProcessInfo.processInfo.environment[Fixture.albumDelayVariable] {
            environment[Fixture.albumDelayVariable] = delay      // 0ms 資訊對照輪（§3.2）
        }
        evidence = destination
        marks = CoverFlowMarks(path: destination.marksPath)
        launch(language: "en", environment: environment)
        probe = CoverFlowProbe(app: app, marks: marks)
        trace = CoverFlowTraceSession(path: destination.tracePath)
        testLabel = test
        waitForMainUI()
        let step = "\(test).setup"
        guard verifyIdentity(step: step), verifyWindow(step: step) else { return false }
        app.buttons["COVER FLOW"].click()
        return waitForLabel(step: step)
    }

    /// 證據落點（計劃 §5.7 (7)）：`AZW_EVIDENCE_DIR`（經 `TEST_RUNNER_` 前綴轉發）有值時，
    /// trace／marks 以 `<test>-<n>.*` 持久化；缺省退回現行的 temporaryDirectory＋UUID，閘門輪行為不變
    private static func evidenceDestination(test: String) -> CoverFlowEvidence.Destination {
        let manager = FileManager.default
        let directory = ProcessInfo.processInfo.environment[CoverFlowEvidence.directoryVariable]
            .flatMap { $0.isEmpty ? nil : $0 }
        if let directory {
            try? manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        let existing = directory.flatMap { try? manager.contentsOfDirectory(atPath: $0) } ?? []
        let fallback = manager.temporaryDirectory
            .appendingPathComponent("azw-cf-trace-\(UUID().uuidString).log").path
        return CoverFlowEvidence.destination(
            directory: directory, test: test, existingFileNames: existing, fallbackTracePath: fallback
        )
    }

    /// 二進位身分：trace header 由 app 自報 bundle 路徑（主證據），runner 側同 bundle ID 恰好一個實例（輔證）
    @MainActor private func verifyIdentity(step: String) -> Bool {
        guard let snapshot = trace.read(from: 0), let header = snapshot.header else {
            probe.reportSingle(step: step, code: "PROBE-TRACE", detail: "no-header", in: self)
            return false
        }
        // 同一份 snapshot 的協議問題也要看：header 正確但已有 write-error 的軌跡不是健康的證據
        guard snapshot.problems.isEmpty else {
            let detail = "problems=\(snapshot.problems.joined(separator: ","))"
            probe.reportSingle(step: step, code: "PROBE-TRACE", detail: detail, in: self)
            return false
        }
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).count
        let expected = ProcessInfo.processInfo.environment[Self.expectedAppDirVariable] ?? ""
        print("IDENTITY bundle=\(header.bundlePath) pid=\(header.pid) exe-size=\(header.executableSize) "
              + "exe-mtime=\(header.executableModified) instances=\(instances) expected=\(expected)")
        // 期望目錄缺失＝證據無效（不是「放行」）；比對走路徑元件邊界，`/tmp/Products-evil` 不得通過 `/tmp/Products`
        guard instances == 1, !expected.isEmpty, Self.isInside(header.bundlePath, directory: expected) else {
            probe.reportSingle(
                step: step, code: "PROBE-WRONG-BINARY",
                detail: "bundle=\(header.bundlePath)|instances=\(instances)", in: self
            )
            return false
        }
        return true
    }

    private static func isInside(_ path: String, directory: String) -> Bool {
        let bundle = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let root = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return bundle.count > root.count && Array(bundle.prefix(root.count)) == root
    }

    /// 閘門的「≈3 stride」等預登記量級以 1200×800 為前提；尺寸取自使用者共享的 app 設定，偏了就不判
    @MainActor private func verifyWindow(step: String) -> Bool {
        let frame = app.windows.firstMatch.frame
        print("WINDOW \(frame)")
        guard abs(frame.width - 1200) <= 1, abs(frame.height - 800) <= 30 else {
            probe.reportSingle(step: step, code: "PROBE-WINDOW", detail: "size=\(frame.size)", in: self)
            return false
        }
        return true
    }

    @MainActor private func waitForLabel(step: String) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if probe.readState()?.labelIndex != nil { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        probe.reportSingle(step: step, code: "PROBE-AX", detail: "label-never-populated", in: self)
        return false
    }

    @MainActor private func waitForStripToDisappear(step: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !probe.strip.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        probe.reportSingle(step: step, code: "PROBE-AX", detail: "strip-still-present", in: self)
        return false
    }

    // MARK: 操作

    @MainActor private func settle(step: String) -> CoverFlowProbe.State? {
        switch probe.waitForStableCenter() {
        case .settled(let state):
            marks?.record(.settled, step)
            return state
        case .neverSettles:
            probe.reportSingle(step: step, code: "C6-NEVER-SETTLES", detail: "", in: self)
        case .axUnreadable:
            probe.reportSingle(step: step, code: "PROBE-AX", detail: "unreadable", in: self)
        }
        return nil
    }

    @MainActor private func ensureForeground(step: String) -> Bool {
        guard app.state == .runningForeground else {
            probe.reportSingle(step: step, code: "PROBE-FOREGROUND", detail: "state=\(app.state.rawValue)", in: self)
            return false
        }
        return true
    }

    /// 點 label 取焦點（在 ScrollView 之外：點卡片可能把焦點交給 ScrollView，方向鍵就改走原生捲動）後按一次 →。
    /// 回傳按前的 label 索引；label 完全沒變＝`[PROBE-FOCUS]`，變了但不是 ＋1 交給契約的 C3 判
    @MainActor private func focusAndStepRight(step: String) -> Int? {
        marks?.record(.stepBegin, step)
        defer { marks?.record(.stepEnd, step) }
        guard let before = probe.readState()?.labelIndex else {
            probe.reportSingle(step: step, code: "PROBE-AX", detail: "no-label-before-focus", in: self)
            return nil
        }
        probe.label.click()
        guard press(.rightArrow, times: 1, step: step) else { return nil }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let now = probe.readState()?.labelIndex, now != before {
                return settle(step: step) == nil ? nil : before
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let detail = "label-unchanged=\(Fixture.persistentID(at: before))"
        probe.reportSingle(step: step, code: "PROBE-FOCUS", detail: detail, in: self)
        return nil
    }

    @MainActor private func press(_ key: XCUIKeyboardKey, times: Int, step: String) -> Bool {
        let name = Self.name(of: key)
        for _ in 0..<times {
            guard ensureForeground(step: step) else { return false }
            // 鍵盤事件不進 trace（只有 `.scrollWheel` 局部監聽），marks 是命令路徑唯一的時間錨點
            marks?.record(.key, name)
            app.typeKey(key, modifierFlags: [])
        }
        return true
    }

    /// `XCUIKeyboardKey` 的 rawValue 是私有區 Unicode，直接寫進 marks 不可讀
    private static func name(of key: XCUIKeyboardKey) -> String {
        switch key.rawValue {
        case XCUIKeyboardKey.leftArrow.rawValue: return "leftArrow"
        case XCUIKeyboardKey.rightArrow.rawValue: return "rightArrow"
        default: return "other"
        }
    }

    /// 捲動段：記水位 → 捲動 → 等軌跡靜止 → 落定 → 保持 1.5s → C4（整段軌跡）＋ 契約
    @MainActor private func scrollStep(_ step: String, deltaX: CGFloat) {
        marks?.record(.stepBegin, step)
        defer { marks?.record(.stepEnd, step) }
        guard ensureForeground(step: step), let start = probe.readState()?.labelIndex else { return }
        let mark = trace.watermark()
        // `XCUIElement.scroll` 是阻塞呼叫：手勢期間 runner 不能取樣，起訖只能靠這兩個 mark 定界
        marks?.record(.scrollBegin, String(format: "%.1f", deltaX))
        probe.scroll(byDeltaX: deltaX)
        marks?.record(.scrollEnd, String(format: "%.1f", deltaX))
        guard trace.readUntilQuiet(from: mark, quiet: CoverFlowProbe.traceQuiet) != nil else {
            probe.reportSingle(step: step, code: "PROBE-TRACE", detail: "unreadable", in: self)
            return
        }
        guard let settled = settle(step: step) else { return }
        // 整段重讀到落定之後：軌跡靜止與落定之間仍可能有回寫，若只取靜止時的快照，
        // 那段既不在 gesture 也不在 hold——恰好是最該抓反轉／拉回的時段（觀測空窗）
        guard let gesture = trace.read(from: mark) else {
            probe.reportSingle(step: step, code: "PROBE-TRACE", detail: "unreadable-after-settle", in: self)
            return
        }
        let holdMark = gesture.endOffset
        Thread.sleep(forTimeInterval: CoverFlowProbe.holdDuration)
        // hold 段讀不到＝探針失敗，不得以空序列冒充「保持期間沒有回寫」
        guard let hold = trace.read(from: holdMark) else {
            probe.reportSingle(step: step, code: "PROBE-TRACE", detail: "unreadable-after-hold", in: self)
            return
        }
        // 保持期後的 AX 讀數是 runner 對「中心是否被改掉」的獨立觀測（也是非 binding 驅動的拉回唯一偵測點）：
        // 讀不到＝探針失敗，不得壓成 nil 後被 compactMap 靜默丟掉（2026-09-12 完整性批評指出的假綠路徑）
        guard let afterHoldState = probe.readState() else {
            probe.reportSingle(step: step, code: "PROBE-AX", detail: "unreadable-after-hold", in: self)
            return
        }
        let afterHold = afterHoldState.labelIndex
        let gestureBinds = CoverFlowTraceSession.bindRecords(gesture)
        let holdBinds = CoverFlowTraceSession.bindRecords(hold)
        var findings = CoverFlowGateLogic.writebackFindings(
            start: start, gesture: gestureBinds.map(\.value.fixtureIndex),
            hold: holdBinds.map(\.value.fixtureIndex) + [afterHold],
            settled: settled.labelIndex
        )
        var problems = gesture.problems + hold.problems
        // fixture 模式下 binding 只會回寫 T00…T19 或字面 nil；其他 payload＝量測沒讀懂，
        // 不得沿用舊行為靜默壓成 nil 後被 compactMap 丟掉（計劃 §5.7 (2)）
        let unknown = (gestureBinds + holdBinds).compactMap(\.value.unknownPayload)
        if !unknown.isEmpty {
            problems.append("unknown-bind=" + unknown.joined(separator: "/"))
        }
        if !problems.isEmpty {
            findings.append(GateFinding(code: "PROBE-TRACE", detail: problems.joined(separator: ",")))
        }
        let events = gesture.records.filter { $0.kind != .bind }.map { "\($0.kind.rawValue):\($0.payload)" }
        probe.assertContract(step: step, want: nil, extra: findings, notes: events, in: self)
    }
}
