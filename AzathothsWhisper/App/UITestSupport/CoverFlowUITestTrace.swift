// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import AppKit
import Foundation

/// 捲動軌跡的寫入端（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.5）。
///
/// **為何需要**：`XCUIElement.scroll(byDeltaX:deltaY:)` 是阻塞呼叫，UITest 只能在它返回之後取樣；
/// 返回前發生的拉回／反轉看不到。這條旁路把 binding 的原始回寫、scrollWheel 事件性質、
/// live-scroll 通知逐行記進 runner 指定的檔案，C4 以整段軌跡判定。
///
/// **寫入協議**：主執行緒上以 `O_APPEND` 的 `write(2)` 同步追加、不 fsync——寫進 page cache 是微秒級；
/// 換來的是沒有待寫佇列，runner 讀到的就是至今記下的全部（R2 評審：背景佇列會製造無法驗證的 drain 邊界）。
/// 不掛成 `@State`／`@Observable`：否則每次回寫都觸發 body 重算，觀測本身就可能改變捲動行為。
@MainActor
final class CoverFlowUITestTrace {
    /// 行程級單例：只由測試組裝安裝一次，`CoverFlowView` 切 tab 重建不會重複安裝
    private(set) static var shared: CoverFlowUITestTrace?

    private let descriptor: Int32
    private let origin = ContinuousClock.now
    private var nextSequence = 0
    private(set) var writeErrors = 0
    private var eventMonitor: Any?
    private var liveObservers: [NSObjectProtocol] = []

    var installedObserverCount: Int { (eventMonitor == nil ? 0 : 1) + liveObservers.count }

    /// 開檔失敗＝nil；runner 讀不到檔即判 `[PROBE-TRACE]`
    init?(path: String) {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard descriptor >= 0 else { return nil }
        self.descriptor = descriptor
        append(CoverFlowTraceFormat.headerLine(Self.currentHeader()))
    }

    deinit {
        close(descriptor)
    }

    static func makeIfRequested(environment: [String: String]) -> CoverFlowUITestTrace? {
        guard let path = environment[CoverFlowUITestFixture.tracePathVariable], !path.isEmpty else { return nil }
        return CoverFlowUITestTrace(path: path)
    }

    static func installIfRequested(environment: [String: String]) {
        guard shared == nil, let trace = makeIfRequested(environment: environment) else { return }
        trace.startMonitoring()
        shared = trace
    }

    /// `CoverFlowView` 的 scrollPosition binding setter 呼叫：記 SwiftUI 的原始回寫值（未經 VM 過濾）
    static func recordBinding(_ persistentID: String?) {
        shared?.record(kind: .bind, payload: persistentID ?? "nil")
    }

    func record(kind: CoverFlowTraceFormat.Kind, payload: String) {
        let elapsed = (ContinuousClock.now - origin).components
        let micros = elapsed.seconds * 1_000_000 + elapsed.attoseconds / 1_000_000_000_000
        let record = CoverFlowTraceFormat.Record(
            sequence: nextSequence, microseconds: micros, kind: kind, payload: payload
        )
        nextSequence += 1
        append(CoverFlowTraceFormat.recordLine(record))
    }

    /// 本行程局部監聽（不是全域 hook）＋ live-scroll 通知；重複呼叫不重複安裝
    func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let payload = Self.describe(event)
            MainActor.assumeIsolated { self?.record(kind: .event, payload: payload) }
            return event
        }
        let notifications = [
            (NSScrollView.willStartLiveScrollNotification, "start"),
            (NSScrollView.didEndLiveScrollNotification, "end"),
        ]
        for (name, payload) in notifications {
            liveObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.record(kind: .live, payload: payload) }
            })
        }
    }

    func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        liveObservers.forEach(NotificationCenter.default.removeObserver)
        liveObservers = []
    }

    /// 合成事件是否帶 phase／慣性，直接決定 XCUITest 能否觸發 M2／M3 的真機故障機制（計劃 §3.11）
    private nonisolated static func describe(_ event: NSEvent) -> String {
        "phase=\(event.phase.rawValue)|momentum=\(event.momentumPhase.rawValue)"
            + "|precise=\(event.hasPreciseScrollingDeltas ? 1 : 0)"
            + "|dx=\(String(format: "%.2f", event.scrollingDeltaX))"
    }

    /// 寫滿為止（短寫續寫、`EINTR` 重試）；真的失敗才計數並補記一行錯誤，runner 見到即判 `[PROBE-TRACE]`
    private func append(_ line: String) {
        guard !writeAll(Array(line.utf8)) else { return }
        let failure = errno
        writeErrors += 1
        _ = writeAll(Array(CoverFlowTraceFormat.errorLine(errno: failure).utf8))
    }

    /// `write(2)` 允許短寫，也可能被信號打斷；寫不完就是失敗（回 false），不當成已寫入
    private func writeAll(_ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress! + offset, bytes.count - offset)
            }
            if written > 0 {
                offset += written
            } else if !(written < 0 && errno == EINTR) {
                return false
            }
        }
        return true
    }

    private static func currentHeader() -> CoverFlowTraceFormat.Header {
        let attributes = Bundle.main.executableURL.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)
        }
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970) } ?? 0
        return CoverFlowTraceFormat.Header(
            pid: ProcessInfo.processInfo.processIdentifier, bundlePath: Bundle.main.bundleURL.path,
            executableSize: size, executableModified: modified
        )
    }
}
#endif
