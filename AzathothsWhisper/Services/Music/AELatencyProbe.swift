#if DEBUG
import Foundation
import OSLog
import os

// I-68 量測（docs/plans/2026-11-01-i68-nowplaying-latency.md）：整檔只在 DEBUG。
// 日誌行只能由 `AELatencyFormat` 造出（`AELatencyLine` 的初始化器是 fileprivate），參數只有整數、列舉與 `StaticString`——
// 曲名、歌手、ID、歌詞在型別上就傳不進來。

/// 量測帳本：純值型別，鎖與日誌在 `AELatencyProbe`
struct AELatencyLedger: Sendable {
    struct SignalBatch: Equatable, Sendable {
        let first: Int
        let last: Int
        let count: Int
        let earliestMs: Int
    }

    enum ScanOutcome: String, Sendable { case complete, incomplete, cancelled, error }
    enum ReadResult: String, Sendable { case changed, nochange, notplaying, error }

    struct ReadSummary: Equatable, Sendable {
        let result: ReadResult
        let changedAtMs: Int?
    }

    private struct Counter: Sendable {
        private var last = 0
        mutating func next() -> Int {
            last += 1
            return last
        }
    }

    private var scans = Counter()
    private var requests = Counter()
    private var runs = Counter()
    private var signals = Counter()
    /// 進行中的掃描（重掃時舊掃描的 AE 停不下來，可以同時兩個）
    private(set) var activeScans: [Int] = []
    private var pending: SignalBatch?
    private var reads: [Int: ReadSummary] = [:]

    mutating func beginScan() -> Int {
        let token = scans.next()
        activeScans.append(token)
        return token
    }

    /// 只結束自己
    mutating func endScan(_ token: Int) {
        activeScans.removeAll { $0 == token }
    }

    mutating func newRequest() -> Int { requests.next() }
    mutating func newRun() -> Int { runs.next() }

    mutating func receiveSignal(atMs ms: Int) -> Int {
        let id = signals.next()
        pending = SignalBatch(
            first: pending?.first ?? id, last: id, count: (pending?.count ?? 0) + 1, earliestMs: min(pending?.earliestMs ?? ms, ms)
        )
        return id
    }

    /// 讀取開始時收走當時待配對的通知；之後才到的歸下一批
    mutating func takeSignals() -> SignalBatch? {
        defer { pending = nil }
        return pending
    }

    mutating func recordNowPlaying(request: Int, result: ReadResult) {
        reads[request] = ReadSummary(result: result, changedAtMs: nil)
    }

    mutating func recordTrackChanged(request: Int, atMs ms: Int) {
        reads[request] = ReadSummary(result: .changed, changedAtMs: ms)
    }

    /// 沒有任何 nowPlaying 紀錄的讀取算 error；讀完即清
    mutating func finishRead(request: Int) -> ReadSummary {
        reads.removeValue(forKey: request) ?? ReadSummary(result: .error, changedAtMs: nil)
    }
}

/// 一行事件：只能由 `AELatencyFormat` 造出；`app=`／`pid=` 前綴在輸出時統一加
struct AELatencyLine: Equatable, Sendable {
    private let kind: String
    private let body: String

    fileprivate init(_ kind: String, _ body: String = "") {
        self.kind = kind
        self.body = body
    }

    func rendered(app: Int, pid: Int32) -> String {
        body.isEmpty ? "\(kind) app=\(app) pid=\(pid)" : "\(kind) app=\(app) pid=\(pid) \(body)"
    }
}

/// 事件格式的唯一入口：參數只有整數、列舉與 `StaticString`
enum AELatencyFormat {
    enum ScanPhase: Sendable {
        case begin
        case end(AELatencyLedger.ScanOutcome)
    }

    /// 整數換算（不經 Double：0.29 s 走浮點會截成 289 ms）
    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds) * 1_000 + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    static func boot() -> AELatencyLine { AELatencyLine("boot") }

    static func scan(token: Int, phase: ScanPhase, t: Int) -> AELatencyLine {
        switch phase {
        case .begin: AELatencyLine("scan", "scan=\(token) begin t=\(t)")
        case .end(let outcome): AELatencyLine("scan", "scan=\(token) end outcome=\(outcome.rawValue) t=\(t)")
        }
    }

    static func nowPlaying(request: Int, scans: [Int], startMs: Int, endMs: Int) -> AELatencyLine {
        AELatencyLine("np", "req=\(request) scan=\(list(scans)) start=\(startMs) end=\(endMs) total=\(endMs - startMs)")
    }

    // swiftlint:disable:next function_parameter_count
    static func run(
        run: Int, request: Int?, operation: StaticString, enqueuedMs: Int, startMs: Int, endMs: Int, scansAtEnqueue: [Int], scansAtStart: [Int]
    ) -> AELatencyLine {
        AELatencyLine("run", "run=\(run) req=\(request.map(String.init) ?? "-") op=\(operation) "
            + "enq=\(enqueuedMs) start=\(startMs) end=\(endMs) wait=\(startMs - enqueuedMs) exec=\(endMs - startMs) "
            + "scanAtEnq=\(list(scansAtEnqueue)) scanAtStart=\(list(scansAtStart))")
    }

    static func signal(id: Int, t: Int) -> AELatencyLine {
        AELatencyLine("sig", "sig=\(id) t=\(t)")
    }

    static func batch(request: Int, batch: AELatencyLedger.SignalBatch, result: AELatencyLedger.ReadResult, e2eMs: Int?) -> AELatencyLine {
        AELatencyLine("batch", "req=\(request) sigs=\(batch.first)-\(batch.last) n=\(batch.count) "
            + "result=\(result.rawValue) e2e=\(e2eMs.map(String.init) ?? "-")")
    }

    private static func list(_ tokens: [Int]) -> String {
        tokens.isEmpty ? "-" : tokens.map(String.init).joined(separator: ",")
    }
}

/// 全域薄殼：鎖住帳本、單調時鐘、OSLog（category `latency`，`.notice`；`log stream` 才是驗收證據）
enum AELatencyProbe {
    /// monitor 每次讀取的請求 ID；`run` 在呼叫端 task 上（`queue.async` 之前）快照
    @TaskLocal static var requestID: Int?

    /// 每次 app 啟動一個數字 nonce，報表據此拒絕跨啟動混算
    static let app = Int.random(in: 1...Int(UInt32.max))
    static let pid = ProcessInfo.processInfo.processIdentifier

    private static let log = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "latency")
    private static let origin = ContinuousClock.now
    private static let ledger = OSAllocatedUnfairLock(initialState: AELatencyLedger())
    /// 靜態初始化只跑一次且執行緒安全：保證 `boot` 是本次啟動的第一行
    private static let booted: Void = log.notice("\(AELatencyFormat.boot().rendered(app: app, pid: pid), privacy: .public)")

    static func nowMs() -> Int {
        AELatencyFormat.milliseconds(ContinuousClock.now - origin)
    }

    private static func activeScans() -> [Int] {
        ledger.withLock { $0.activeScans }
    }

    private static func emit(_ line: AELatencyLine) {
        _ = booted
        log.notice("\(line.rendered(app: app, pid: pid), privacy: .public)")
    }

    // MARK: AE 工作 block

    struct RunToken: Sendable {
        let run: Int
        let request: Int?
        let operation: StaticString
        let enqueuedMs: Int
        let scansAtEnqueue: [Int]

        /// 在佇列 block 內包住 body：開始／結束各記一次；錯誤照拋
        func measure<T>(_ body: () throws -> T) rethrows -> T {
            let startMs = nowMs()
            let scansAtStart = activeScans()
            defer {
                emit(AELatencyFormat.run(
                    run: run, request: request, operation: operation, enqueuedMs: enqueuedMs, startMs: startMs, endMs: nowMs(),
                    scansAtEnqueue: scansAtEnqueue, scansAtStart: scansAtStart
                ))
            }
            return try body()
        }
    }

    /// 必須在呼叫端 task 上呼叫（`queue.async` 之前）：TaskLocal 進了 GCD block 就讀不到
    static func beginRun(operation: StaticString) -> RunToken {
        let (run, scans) = ledger.withLock { ($0.newRun(), $0.activeScans) }
        return RunToken(run: run, request: requestID, operation: operation, enqueuedMs: nowMs(), scansAtEnqueue: scans)
    }

    // MARK: 掃描

    static func measuringScan(_ body: @Sendable () async throws -> LibraryScanOutcome) async throws -> LibraryScanOutcome {
        let token = ledger.withLock { $0.beginScan() }
        emit(AELatencyFormat.scan(token: token, phase: .begin, t: nowMs()))
        do {
            let outcome = try await body()
            endScan(token, outcome.isComplete ? .complete : .incomplete)
            return outcome
        } catch is CancellationError {
            endScan(token, .cancelled)
            throw CancellationError()
        } catch {
            endScan(token, .error)
            throw error
        }
    }

    private static func endScan(_ token: Int, _ outcome: AELatencyLedger.ScanOutcome) {
        ledger.withLock { $0.endScan(token) }
        emit(AELatencyFormat.scan(token: token, phase: .end(outcome), t: nowMs()))
    }

    // MARK: nowPlaying 與換歌

    struct ReadToken: Sendable {
        let request: Int
        let batch: AELatencyLedger.SignalBatch?
    }

    static func signalReceived() {
        let t = nowMs()
        let id = ledger.withLock { $0.receiveSignal(atMs: t) }
        emit(AELatencyFormat.signal(id: id, t: t))
    }

    /// monitor 一次讀取開始：新請求 ID；理由含換歌通知時收走待配對的通知
    static func readBegan(takesSignals: Bool) -> ReadToken {
        ledger.withLock { ReadToken(request: $0.newRequest(), batch: takesSignals ? $0.takeSignals() : nil) }
    }

    /// `result`：讀到曲目＝nochange（之後送出 trackChanged 會改成 changed）、沒在播＝notplaying、丟錯＝error
    static func nowPlayingFinished(startedMs: Int, result: AELatencyLedger.ReadResult) {
        guard let request = requestID else { return }
        let endMs = nowMs()
        let scans = ledger.withLock { ledger in
            ledger.recordNowPlaying(request: request, result: result)
            return ledger.activeScans
        }
        emit(AELatencyFormat.nowPlaying(request: request, scans: scans, startMs: startedMs, endMs: endMs))
    }

    static func trackChangedEmitted() {
        guard let request = requestID else { return }
        let t = nowMs()
        ledger.withLock { $0.recordTrackChanged(request: request, atMs: t) }
    }

    static func readFinished(_ token: ReadToken) {
        let summary = ledger.withLock { $0.finishRead(request: token.request) }
        guard let batch = token.batch else { return }
        emit(AELatencyFormat.batch(request: token.request, batch: batch, result: summary.result, e2eMs: summary.changedAtMs.map { $0 - batch.earliestMs }))
    }
}

private extension LibraryScanOutcome {
    var isComplete: Bool {
        if case .complete = self { true } else { false }
    }
}
#endif
