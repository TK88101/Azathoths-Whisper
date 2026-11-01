#if DEBUG
import Foundation
import OSLog
import os

// I-68 量測（docs/plans/2026-11-01-i68-nowplaying-latency.md）：整檔只在 DEBUG。
// 只記數字、固定字樣與編譯期函式名（`StaticString`）——曲名、歌手、ID、歌詞在型別上就傳不進來。

/// 量測帳本：純值型別，鎖與日誌在 `AELatencyProbe`
struct AELatencyLedger: Sendable {
    struct SignalBatch: Equatable, Sendable {
        let first: Int
        let last: Int
        let count: Int
        let earliestMs: Int
    }

    enum ScanOutcome: String, Sendable { case complete, incomplete, cancelled, error }
    enum NowPlayingOutcome: Sendable { case track, none, failed }
    enum ReadResult: String, Sendable { case changed, nochange, notplaying, error }

    struct ReadSummary: Equatable, Sendable {
        let result: ReadResult
        let changedAtMs: Int?
    }

    private struct ReadRecord: Sendable {
        var outcome: NowPlayingOutcome?
        var changedAtMs: Int?
    }

    private var nextScan = 1
    private var nextRequest = 1
    private var nextRun = 1
    private var nextSignal = 1
    /// 進行中的掃描（重掃時舊掃描的 AE 停不下來，可以同時兩個）
    private(set) var activeScans: [Int] = []
    private var pendingSignals: [(id: Int, ms: Int)] = []
    private var reads: [Int: ReadRecord] = [:]

    mutating func beginScan() -> Int {
        defer { nextScan += 1 }
        activeScans.append(nextScan)
        return nextScan
    }

    /// 只結束自己；不在進行中回 false
    mutating func endScan(_ token: Int) -> Bool {
        guard let index = activeScans.firstIndex(of: token) else { return false }
        activeScans.remove(at: index)
        return true
    }

    mutating func newRequest() -> Int {
        defer { nextRequest += 1 }
        return nextRequest
    }

    mutating func newRun() -> Int {
        defer { nextRun += 1 }
        return nextRun
    }

    mutating func receiveSignal(atMs ms: Int) -> Int {
        defer { nextSignal += 1 }
        pendingSignals.append((nextSignal, ms))
        return nextSignal
    }

    /// 讀取開始時收走當時待配對的通知；之後才到的歸下一批
    mutating func takeSignals() -> SignalBatch? {
        guard let first = pendingSignals.first, let last = pendingSignals.last else { return nil }
        defer { pendingSignals = [] }
        return SignalBatch(first: first.id, last: last.id, count: pendingSignals.count, earliestMs: pendingSignals.map(\.ms).min() ?? first.ms)
    }

    mutating func recordNowPlaying(request: Int, outcome: NowPlayingOutcome) {
        reads[request, default: ReadRecord()].outcome = outcome
    }

    mutating func recordTrackChanged(request: Int, atMs ms: Int) {
        reads[request, default: ReadRecord()].changedAtMs = ms
    }

    mutating func finishRead(request: Int) -> ReadSummary {
        let record = reads.removeValue(forKey: request)
        if let changed = record?.changedAtMs { return ReadSummary(result: .changed, changedAtMs: changed) }
        switch record?.outcome {
        case .track: return ReadSummary(result: .nochange, changedAtMs: nil)
        case .none?: return ReadSummary(result: .notplaying, changedAtMs: nil)
        case .failed, nil: return ReadSummary(result: .error, changedAtMs: nil)
        }
    }
}

/// 事件格式的唯一入口：參數只有整數、列舉與 `StaticString`
enum AELatencyFormat {
    enum ScanPhase: Sendable {
        case begin
        case end(AELatencyLedger.ScanOutcome)
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds) * 1_000 + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    static func boot(app: Int, pid: Int32) -> String {
        "boot app=\(app) pid=\(pid)"
    }

    static func scan(app: Int, pid: Int32, token: Int, phase: ScanPhase, t: Int) -> String {
        switch phase {
        case .begin: "scan app=\(app) pid=\(pid) scan=\(token) begin t=\(t)"
        case .end(let outcome): "scan app=\(app) pid=\(pid) scan=\(token) end outcome=\(outcome.rawValue) t=\(t)"
        }
    }

    static func nowPlaying(app: Int, pid: Int32, request: Int, scans: [Int], startMs: Int, endMs: Int) -> String {
        "np app=\(app) pid=\(pid) req=\(request) scan=\(list(scans)) start=\(startMs) end=\(endMs) total=\(endMs - startMs)"
    }

    // swiftlint:disable:next function_parameter_count
    static func run(
        app: Int, pid: Int32, run: Int, request: Int?, operation: StaticString,
        enqueuedMs: Int, startMs: Int, endMs: Int, scansAtEnqueue: [Int], scansAtStart: [Int]
    ) -> String {
        "run app=\(app) pid=\(pid) run=\(run) req=\(request.map(String.init) ?? "-") op=\(operation) "
            + "enq=\(enqueuedMs) start=\(startMs) end=\(endMs) wait=\(startMs - enqueuedMs) exec=\(endMs - startMs) "
            + "scanAtEnq=\(list(scansAtEnqueue)) scanAtStart=\(list(scansAtStart))"
    }

    static func signal(app: Int, pid: Int32, id: Int, t: Int) -> String {
        "sig app=\(app) pid=\(pid) sig=\(id) t=\(t)"
    }

    static func batch(
        app: Int, pid: Int32, request: Int, batch: AELatencyLedger.SignalBatch, result: AELatencyLedger.ReadResult, e2eMs: Int?
    ) -> String {
        "batch app=\(app) pid=\(pid) req=\(request) sigs=\(batch.first)-\(batch.last) n=\(batch.count) "
            + "result=\(result.rawValue) e2e=\(e2eMs.map(String.init) ?? "-")"
    }

    private static func list(_ tokens: [Int]) -> String {
        tokens.isEmpty ? "-" : tokens.map(String.init).joined(separator: ",")
    }
}

/// 全域薄殼：鎖住帳本、單調時鐘、OSLog（category `latency`，`.notice` 會落盤；`log stream` 才是驗收證據）
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
    private static let booted: Void = log.notice("\(AELatencyFormat.boot(app: app, pid: pid), privacy: .public)")

    static func nowMs() -> Int {
        AELatencyFormat.milliseconds(ContinuousClock.now - origin)
    }

    static func activeScans() -> [Int] {
        ledger.withLock { $0.activeScans }
    }

    static func emit(_ line: String) {
        _ = booted
        log.notice("\(line, privacy: .public)")
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
            let startMs = AELatencyProbe.nowMs()
            let scansAtStart = AELatencyProbe.activeScans()
            defer {
                AELatencyProbe.emit(AELatencyFormat.run(
                    app: AELatencyProbe.app, pid: AELatencyProbe.pid, run: run, request: request, operation: operation,
                    enqueuedMs: enqueuedMs, startMs: startMs, endMs: AELatencyProbe.nowMs(),
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

    static func measuringScan<T: Sendable>(
        isComplete: @Sendable (T) -> Bool, _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let token = ledger.withLock { $0.beginScan() }
        emit(AELatencyFormat.scan(app: app, pid: pid, token: token, phase: .begin, t: nowMs()))
        do {
            let value = try await body()
            endScan(token, isComplete(value) ? .complete : .incomplete)
            return value
        } catch is CancellationError {
            endScan(token, .cancelled)
            throw CancellationError()
        } catch {
            endScan(token, .error)
            throw error
        }
    }

    private static func endScan(_ token: Int, _ outcome: AELatencyLedger.ScanOutcome) {
        _ = ledger.withLock { $0.endScan(token) }
        emit(AELatencyFormat.scan(app: app, pid: pid, token: token, phase: .end(outcome), t: nowMs()))
    }

    // MARK: nowPlaying 與換歌

    struct ReadToken: Sendable {
        let request: Int
        let batch: AELatencyLedger.SignalBatch?
    }

    static func signalReceived() {
        let t = nowMs()
        let id = ledger.withLock { $0.receiveSignal(atMs: t) }
        emit(AELatencyFormat.signal(app: app, pid: pid, id: id, t: t))
    }

    /// monitor 一次讀取開始：新請求 ID；理由含換歌通知時收走待配對的通知
    static func readBegan(takesSignals: Bool) -> ReadToken {
        ledger.withLock { ReadToken(request: $0.newRequest(), batch: takesSignals ? $0.takeSignals() : nil) }
    }

    static func nowPlayingStarted() -> Int {
        nowMs()
    }

    static func nowPlayingFinished(startedMs: Int, outcome: AELatencyLedger.NowPlayingOutcome) {
        guard let request = requestID else { return }
        let endMs = nowMs()
        let scans = ledger.withLock { ledger in
            ledger.recordNowPlaying(request: request, outcome: outcome)
            return ledger.activeScans
        }
        emit(AELatencyFormat.nowPlaying(app: app, pid: pid, request: request, scans: scans, startMs: startedMs, endMs: endMs))
    }

    static func trackChangedEmitted() {
        guard let request = requestID else { return }
        let t = nowMs()
        ledger.withLock { $0.recordTrackChanged(request: request, atMs: t) }
    }

    static func readFinished(_ token: ReadToken) {
        let summary = ledger.withLock { $0.finishRead(request: token.request) }
        guard let batch = token.batch else { return }
        let e2e = summary.changedAtMs.map { $0 - batch.earliestMs }
        emit(AELatencyFormat.batch(app: app, pid: pid, request: token.request, batch: batch, result: summary.result, e2eMs: e2e))
    }
}
#endif
