import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// H-02 UI 測試閘門的捲動軌跡旁路（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.5）。
//
// C4（回寫不反向、不拉回）整條判定都建立在這份軌跡上：序號斷、時間倒退、讀到半行或 NUL，
// 都會讓閘門對 M3 的結論失真。所以寫入端與讀取端的協議先在單元層釘住。
@Suite("CoverFlowUITestTrace", .serialized)
@MainActor
struct CoverFlowUITestTraceTests {
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("azw-trace-\(UUID().uuidString).log").path
    }

    @Test func headerIdentifiesTheWritingBinary() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try #require(CoverFlowUITestTrace(path: path))

        let snapshot = try CoverFlowTraceFormat.read(path: path, fromOffset: 0)
        let header = try #require(snapshot.header)
        #expect(header.pid == ProcessInfo.processInfo.processIdentifier)
        #expect(header.bundlePath == Bundle.main.bundleURL.path)
        #expect(header.executableSize > 0)
        #expect(snapshot.records.isEmpty)
        #expect(snapshot.problems.isEmpty)
    }

    /// §5.7 (1)：header 帶 wall-clock 錨點，runner marks（wall-clock µs）與 trace 的
    /// `ContinuousClock` 相對微秒才能對齊（§5.4「分段來源」要求兩種 marks 同錨點）
    @Test func headerCarriesWallClockEpochAnchor() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let before = Int64(Date().timeIntervalSince1970 * 1_000_000)
        _ = try #require(CoverFlowUITestTrace(path: path))
        let after = Int64(Date().timeIntervalSince1970 * 1_000_000)

        let header = try #require(try CoverFlowTraceFormat.read(path: path, fromOffset: 0).header)
        let epoch = try #require(header.epochMicroseconds)
        #expect(epoch >= before && epoch <= after, "epoch-us 必須是開檔當下的 wall-clock：\(epoch)")
    }

    /// 舊檔（無 `epoch-us` 欄）仍要解析得出 header，否則既有證據包一律變成 `no-header`
    @Test func headerWithoutEpochFieldStillParses() {
        let legacy = "#header\tpid=7\tbundle=/tmp/A.app\texe-size=42\texe-mtime=99\n"
        let snapshot = CoverFlowTraceFormat.parse(Data(legacy.utf8), offset: 0)
        #expect(snapshot.header?.epochMicroseconds == nil)
        #expect(snapshot.header?.pid == 7)
        #expect(snapshot.problems.isEmpty)
    }

    @Test func recordsAreSequencedMonotonicAndSanitised() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(CoverFlowUITestTrace(path: path))

        trace.record(kind: .bind, payload: "T11")
        trace.record(kind: .bind, payload: "nil")
        trace.record(kind: .event, payload: "phase=1|momentum=0\tinjected\nline")
        trace.record(kind: .live, payload: "start")

        let snapshot = try CoverFlowTraceFormat.read(path: path, fromOffset: 0)
        #expect(snapshot.problems.isEmpty, "\(snapshot.problems)")
        #expect(snapshot.records.map(\.sequence) == [0, 1, 2, 3])
        #expect(snapshot.records.map(\.kind) == [.bind, .bind, .event, .live])
        #expect(snapshot.records[2].payload == "phase=1|momentum=0 injected line")
        let times = snapshot.records.map(\.microseconds)
        #expect(times == times.sorted())
        #expect(trace.writeErrors == 0)
    }

    /// §5.7 (2)：bind 回寫分三型。舊的 `bindIndices` 把字面 `nil` 與非 fixture ID 都壓成 nil，
    /// 於是「SwiftUI 回寫 nil」與「軌跡記到看不懂的值」在判定上無法區分（計劃 §2 D2 盲區）
    @Test func bindSamplesSeparateFixtureLiteralNilAndUnknown() {
        let lines = "0\t10\tbind\tT11\n1\t20\tbind\tnil\n2\t30\tbind\t1234567890\n3\t40\tevent\tphase=1\n"
            + "4\t50\tbind\tT20\n"
        let snapshot = CoverFlowTraceFormat.parse(Data(lines.utf8), offset: 0)

        let samples = CoverFlowTraceFormat.bindSamples(snapshot)
        #expect(samples.map(\.value) == [.fixture(11), .literalNil, .unknown("1234567890"), .unknown("T20")])
        #expect(samples.map(\.microseconds) == [10, 20, 30, 50], "讀取端必須帶時間戳")
        #expect(samples.map(\.value.fixtureIndex) == [11, nil, nil, nil], "writebackFindings 的輸入仍是 [Int?]")
        #expect(samples.compactMap(\.value.unknownPayload) == ["1234567890", "T20"])
    }

    /// runner 不截斷檔案，只讀水位之後的行（計劃 §3.5）
    @Test func readerHonoursWatermark() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(CoverFlowUITestTrace(path: path))
        trace.record(kind: .bind, payload: "T10")
        let first = try CoverFlowTraceFormat.read(path: path, fromOffset: 0)

        trace.record(kind: .bind, payload: "T11")
        trace.record(kind: .bind, payload: "T12")
        let second = try CoverFlowTraceFormat.read(path: path, fromOffset: first.endOffset)
        #expect(second.records.map(\.payload) == ["T11", "T12"])
        #expect(second.records.map(\.sequence) == [1, 2])
        #expect(second.header == nil, "水位之後不應再出現 header")
        #expect(second.endOffset > first.endOffset)
    }

    /// 短寫停在 payload 中途時，錯誤標記必須自成一行——否則它會被當成該行 payload 的一部分，
    /// 前三欄仍合法 → 解析成正常記錄，`write-error` 永遠不出現（2026-09-11 Codex review）
    @Test func writeErrorMarkerCannotGlueOntoATruncatedRecord() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let truncated = "0\t10\tbind\tT1"  // payload 寫到一半就短寫
        try Data((truncated + CoverFlowTraceFormat.errorLine(errno: 28)).utf8)
            .write(to: URL(fileURLWithPath: path))

        let snapshot = try CoverFlowTraceFormat.read(path: path, fromOffset: 0)
        #expect(snapshot.problems.contains { $0.hasPrefix("write-error") }, "\(snapshot.problems)")
        #expect(snapshot.records.allSatisfy { !$0.payload.contains("#error") })
    }

    @Test func readerFlagsGapsNulBytesAndWriteErrors() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let lines = "0\t10\tbind\tT10\n2\t20\tbind\tT11\n\u{0}\u{0}\n1\t5\tbind\tT09\n#error\terrno=28\n"
        try Data(lines.utf8).write(to: URL(fileURLWithPath: path))

        let problems = try CoverFlowTraceFormat.read(path: path, fromOffset: 0).problems
        #expect(problems.contains { $0.hasPrefix("gap") })
        #expect(problems.contains { $0.hasPrefix("nul") })
        #expect(problems.contains { $0.hasPrefix("time") })
        #expect(problems.contains { $0.hasPrefix("write-error") })
    }

    /// 半行（寫入進行中）不得被解析成記錄，也不得推進水位
    @Test func trailingPartialLineIsLeftForTheNextRead() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data("0\t10\tbind\tT10\n1\t20\tbi".utf8).write(to: URL(fileURLWithPath: path))

        let snapshot = try CoverFlowTraceFormat.read(path: path, fromOffset: 0)
        #expect(snapshot.records.map(\.payload) == ["T10"])
        #expect(snapshot.endOffset == UInt64("0\t10\tbind\tT10\n".utf8.count))
    }

    /// 全檔 audit（R5-4 Round 2 P1 ②）：`watermark()` 只留 endOffset，前綴裡的 write-error／malformed
    /// 若不從 0 重讀就永遠被跳過——每條測試結束前必須做一次全檔 audit
    @Test func fullFileAuditSeesProblemsBeforeTheWatermark() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(CoverFlowUITestTrace(path: path))
        trace.record(kind: .bind, payload: "T10")
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(CoverFlowTraceFormat.errorLine(errno: 28).utf8))
        try handle.close()
        let mark = try CoverFlowTraceFormat.read(path: path, fromOffset: 0).endOffset
        trace.record(kind: .bind, payload: "T11")

        let sinceMark = try CoverFlowTraceFormat.read(path: path, fromOffset: mark)
        #expect(sinceMark.problems.isEmpty, "水位之後看不見前綴問題——這正是全檔 audit 要補的洞")
        let audit = CoverFlowTraceFormat.audit(path: path)
        #expect(audit.contains { $0.hasPrefix("write-error") }, "\(audit)")
    }

    @Test func auditReportsMissingHeaderPartialTailAndUnreadableFile() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data("0\t10\tbind\tT10\n1\t20\tbi".utf8).write(to: URL(fileURLWithPath: path))
        let audit = CoverFlowTraceFormat.audit(path: path)
        #expect(audit.contains("no-header"), "\(audit)")
        #expect(audit.contains("partial-tail"), "\(audit)")
        let missing = CoverFlowTraceFormat.audit(path: "/nonexistent-dir-\(UUID().uuidString)/trace.log")
        #expect(missing.contains { $0.hasPrefix("unreadable") }, "\(missing)")
    }

    @Test func cleanTraceAuditsClean() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(CoverFlowUITestTrace(path: path))
        trace.record(kind: .bind, payload: "T10")
        trace.record(kind: .live, payload: "end")
        #expect(CoverFlowTraceFormat.audit(path: path).isEmpty)
    }

    @Test func unwritablePathYieldsNoTrace() {
        #expect(CoverFlowUITestTrace(path: "/nonexistent-dir-\(UUID().uuidString)/trace.log") == nil)
    }

    @Test func factoryRequiresThePathVariable() throws {
        #expect(CoverFlowUITestTrace.makeIfRequested(environment: [:]) == nil)
        #expect(CoverFlowUITestTrace.makeIfRequested(environment: [CoverFlowUITestFixture.tracePathVariable: ""]) == nil)
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(CoverFlowUITestTrace.makeIfRequested(environment: [CoverFlowUITestFixture.tracePathVariable: path]) != nil)
    }

    /// §5.7 (3)：安裝條件＝`tracePath 非空 && !isUnitTestHost`，與 fixture 旗標無關——
    /// 實體手滑輪以 `open --env` 正常啟動（fixture OFF）也要記軌跡。
    /// 這裡只驗**純判定**：真的安裝會污染行程級單例 `shared`，不在單元測試裡執行
    @Test func installDecisionIgnoresFixtureFlagButHonoursUnitTestHost() {
        let path = CoverFlowUITestFixture.tracePathVariable
        let fixture = CoverFlowUITestFixture.launchFlag
        let host = AppModel.unitTestHostFlag

        #expect(CoverFlowUITestTrace.shouldInstall(environment: [fixture: "1", path: "/tmp/t"], isInstalled: false))
        #expect(CoverFlowUITestTrace.shouldInstall(environment: [path: "/tmp/t"], isInstalled: false))
        #expect(CoverFlowUITestTrace.shouldInstall(environment: [path: "/tmp/t", host: "0"], isInstalled: false))
        #expect(!CoverFlowUITestTrace.shouldInstall(environment: [path: "/tmp/t", host: "1"], isInstalled: false))
        #expect(!CoverFlowUITestTrace.shouldInstall(environment: [fixture: "1"], isInstalled: false))
        #expect(!CoverFlowUITestTrace.shouldInstall(environment: [path: ""], isInstalled: false))
        #expect(!CoverFlowUITestTrace.shouldInstall(environment: [fixture: "1", path: "/tmp/t"], isInstalled: true),
                "已安裝就不再安裝：切 tab 重建、兩條分支都呼叫時只裝一次")
    }

    /// 切 tab 重建 CoverFlowView 不得重複安裝監聽（否則同一事件記兩次，C4 判定被灌水）
    @Test func monitoringIsInstalledOnlyOnce() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(CoverFlowUITestTrace(path: path))
        trace.startMonitoring()
        trace.startMonitoring()
        #expect(trace.installedObserverCount == 3, "一個事件監聽＋兩個 live-scroll 觀察者")
        trace.stopMonitoring()
        #expect(trace.installedObserverCount == 0)
    }

    /// 非測試模式（單例未安裝）下，CoverFlowView 的 binding 鉤子必須是 no-op，且不會順手把旁路裝起來
    @Test func bindingHookIsANoOpWithoutInstalledTrace() {
        #expect(CoverFlowUITestTrace.shared == nil)
        CoverFlowUITestTrace.recordBinding("T10")
        CoverFlowUITestTrace.recordBinding(nil)
        #expect(CoverFlowUITestTrace.shared == nil)
    }

    /// AppKit 的 willStart／didEnd live scroll 通知逐條記成 `live` 行（S4：合成捲動仍會發這兩個通知）
    @Test func liveScrollNotificationsAreRecorded() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(CoverFlowUITestTrace(path: path))
        trace.startMonitoring()
        defer { trace.stopMonitoring() }

        let scrollView = NSScrollView()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)

        let records = try CoverFlowTraceFormat.read(path: path, fromOffset: 0).records
        #expect(records.map(\.kind) == [.live, .live])
        #expect(records.map(\.payload) == ["start", "end"])
    }

    /// 經 sendEvent 派發的 scrollWheel 事件被本行程局部監聽記下 phase／momentum／precise／dx——
    /// 這正是 §3.11 判斷「XCUITest 合成捲動是否帶慣性」所讀的欄位。零位移：不會真的捲動宿主裡任何視圖
    @Test func scrollWheelEventsRecordPhaseMomentumAndPrecision() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(CoverFlowUITestTrace(path: path))
        trace.startMonitoring()
        defer { trace.stopMonitoring() }

        let cgEvent = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0
        ))
        NSApp.sendEvent(try #require(NSEvent(cgEvent: cgEvent)))

        let events = try CoverFlowTraceFormat.read(path: path, fromOffset: 0).records.filter { $0.kind == .event }
        let payload = try #require(events.first?.payload)
        #expect(events.count == 1)
        #expect(payload.hasPrefix("phase=0|momentum=0|precise="), "無 phase／慣性的合成事件：\(payload)")
        #expect(payload.hasSuffix("|dx=0.00"))
    }
}
