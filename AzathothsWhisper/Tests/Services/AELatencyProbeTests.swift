#if DEBUG
import Foundation
import Testing

@testable import AzathothsWhisper

// I-68 量測（docs/plans/2026-11-01-i68-nowplaying-latency.md L1）：帳本、格式（只有數字與編譯期字串）、`beginRun` 的快照時點
@Suite("AE latency probe")
struct AELatencyProbeTests {
    // MARK: 掃描 token

    @Test func scanTokensAreUniqueAndEachEndsOnlyItself() {
        var ledger = AELatencyLedger()
        let old = ledger.beginScan()
        let new = ledger.beginScan()
        #expect(old != new)
        #expect(ledger.activeScans == [old, new])
        // 重掃：舊的取消、新的已開始、舊的晚結束——只結束自己
        let r1 = ledger.endScan(old)
        #expect(r1)
        #expect(ledger.activeScans == [new])
        let r2 = ledger.endScan(old)
        #expect(!r2)
        let r3 = ledger.endScan(new)
        #expect(r3)
        #expect(ledger.activeScans.isEmpty)
    }

    // MARK: 序號

    @Test func requestRunAndSignalIDsIncrease() {
        var ledger = AELatencyLedger()
        let requests = [ledger.newRequest(), ledger.newRequest()]
        let runs = [ledger.newRun(), ledger.newRun()]
        let signals = [ledger.receiveSignal(atMs: 10), ledger.receiveSignal(atMs: 20)]
        #expect(requests == [1, 2])
        #expect(runs == [1, 2])
        #expect(signals == [1, 2])
    }

    // MARK: 通知批次

    @Test func aReadTakesTheSignalsPendingAtItsStart() {
        var ledger = AELatencyLedger()
        _ = ledger.receiveSignal(atMs: 100)
        _ = ledger.receiveSignal(atMs: 140)
        let r4 = ledger.takeSignals()
        #expect(r4 == AELatencyLedger.SignalBatch(first: 1, last: 2, count: 2, earliestMs: 100))
        // 讀取進行中才到的通知歸下一批
        _ = ledger.receiveSignal(atMs: 300)
        let r5 = ledger.takeSignals()
        #expect(r5 == AELatencyLedger.SignalBatch(first: 3, last: 3, count: 1, earliestMs: 300))
    }

    @Test func noPendingSignalsMeansNoBatch() {
        var ledger = AELatencyLedger()
        let r6 = ledger.takeSignals()
        #expect(r6 == nil)
    }

    // MARK: 讀取結果

    @Test func aReadThatEmitsTrackChangedIsChangedWithItsTime() {
        var ledger = AELatencyLedger()
        let request = ledger.newRequest()
        ledger.recordNowPlaying(request: request, outcome: .track)
        ledger.recordTrackChanged(request: request, atMs: 480)
        let r7 = ledger.finishRead(request: request)
        #expect(r7 == AELatencyLedger.ReadSummary(result: .changed, changedAtMs: 480))
    }

    @Test(arguments: [
        (AELatencyLedger.NowPlayingOutcome.track, AELatencyLedger.ReadResult.nochange),
        (.none, .notplaying),
        (.failed, .error),
    ])
    func readsWithoutTrackChangedHaveNoTime(outcome: AELatencyLedger.NowPlayingOutcome, expected: AELatencyLedger.ReadResult) {
        var ledger = AELatencyLedger()
        let request = ledger.newRequest()
        ledger.recordNowPlaying(request: request, outcome: outcome)
        let r8 = ledger.finishRead(request: request)
        #expect(r8 == AELatencyLedger.ReadSummary(result: expected, changedAtMs: nil))
    }

    @Test func aReadWithoutAnyNowPlayingRecordIsAnError() {
        var ledger = AELatencyLedger()
        let request = ledger.newRequest()
        let r9 = ledger.finishRead(request: request)
        #expect(r9 == AELatencyLedger.ReadSummary(result: .error, changedAtMs: nil))
        // 結束後清掉，同一 ID 再結束不會讀到舊紀錄
        ledger.recordNowPlaying(request: request, outcome: .track)
        ledger.recordTrackChanged(request: request, atMs: 5)
        _ = ledger.finishRead(request: request)
        let r10 = ledger.finishRead(request: request)
        #expect(r10 == AELatencyLedger.ReadSummary(result: .error, changedAtMs: nil))
    }

    // MARK: 毫秒

    @Test func millisecondsTruncateAttoseconds() {
        #expect(AELatencyFormat.milliseconds(.seconds(2)) == 2_000)
        #expect(AELatencyFormat.milliseconds(.milliseconds(1_499)) == 1_499)
        #expect(AELatencyFormat.milliseconds(.microseconds(1_999)) == 1)
        #expect(AELatencyFormat.milliseconds(.zero) == 0)
    }

    // MARK: 格式：只有固定字樣、數字、編譯期函式名

    static func allowedLine() -> Regex<(Substring, Substring?)> { /^[a-z]+( [A-Za-z][A-Za-z0-9]*=[-0-9A-Za-z(),:]+| begin| end)*$/ }

    static let sampleLines: [String] = [
        AELatencyFormat.boot(app: 42, pid: 900),
        AELatencyFormat.scan(app: 42, pid: 900, token: 3, phase: .begin, t: 10),
        AELatencyFormat.scan(app: 42, pid: 900, token: 3, phase: .end(.complete), t: 70_010),
        AELatencyFormat.nowPlaying(app: 42, pid: 900, request: 5, scans: [3, 4], startMs: 100, endMs: 260),
        AELatencyFormat.nowPlaying(app: 42, pid: 900, request: 6, scans: [], startMs: 300, endMs: 310),
        AELatencyFormat.run(
            app: 42, pid: 900, run: 9, request: 5, operation: "nowPlaying()",
            enqueuedMs: 100, startMs: 180, endMs: 250, scansAtEnqueue: [3], scansAtStart: []
        ),
        AELatencyFormat.run(
            app: 42, pid: 900, run: 10, request: nil, operation: "artistLyrics(artist:)",
            enqueuedMs: 1, startMs: 2, endMs: 3, scansAtEnqueue: [], scansAtStart: [3]
        ),
        AELatencyFormat.signal(app: 42, pid: 900, id: 2, t: 400),
        AELatencyFormat.batch(app: 42, pid: 900, request: 7, batch: .init(first: 2, last: 4, count: 3, earliestMs: 400), result: .changed, e2eMs: 120),
        AELatencyFormat.batch(app: 42, pid: 900, request: 8, batch: .init(first: 5, last: 5, count: 1, earliestMs: 500), result: .nochange, e2eMs: nil),
    ]

    @Test func everyLineUsesOnlyFixedWordsNumbersAndFunctionNames() {
        for line in Self.sampleLines {
            #expect(line.wholeMatch(of: Self.allowedLine()) != nil, "\(line)")
        }
    }

    @Test func linesCarryTheFieldsTheReportReads() {
        #expect(Self.sampleLines[0] == "boot app=42 pid=900")
        #expect(Self.sampleLines[1] == "scan app=42 pid=900 scan=3 begin t=10")
        #expect(Self.sampleLines[2] == "scan app=42 pid=900 scan=3 end outcome=complete t=70010")
        #expect(Self.sampleLines[3] == "np app=42 pid=900 req=5 scan=3,4 start=100 end=260 total=160")
        #expect(Self.sampleLines[4] == "np app=42 pid=900 req=6 scan=- start=300 end=310 total=10")
        #expect(Self.sampleLines[5] == "run app=42 pid=900 run=9 req=5 op=nowPlaying() enq=100 start=180 end=250 wait=80 exec=70 scanAtEnq=3 scanAtStart=-")
        #expect(Self.sampleLines[6].contains("req=- op=artistLyrics(artist:)"))
        #expect(Self.sampleLines[7] == "sig app=42 pid=900 sig=2 t=400")
        #expect(Self.sampleLines[8] == "batch app=42 pid=900 req=7 sigs=2-4 n=3 result=changed e2e=120")
        #expect(Self.sampleLines[9] == "batch app=42 pid=900 req=8 sigs=5-5 n=1 result=nochange e2e=-")
    }

    // MARK: beginRun 的快照時點（必須在 `queue.async` 之前，Codex 整體確認 #2）

    @Test func beginRunSnapshotsTheRequestOnTheCallingTask() {
        let token = AELatencyProbe.$requestID.withValue(7) { AELatencyProbe.beginRun(operation: "nowPlaying()") }
        #expect(token.request == 7)
    }

    @Test func beginRunInsideADispatchBlockSeesNoRequest() async {
        let request: Int? = await AELatencyProbe.$requestID.withValue(7) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(returning: AELatencyProbe.beginRun(operation: "nowPlaying()").request)
                }
            }
        }
        #expect(request == nil)
    }

    @Test func measureRunsTheBodyAndRethrows() {
        let token = AELatencyProbe.beginRun(operation: "playerState()")
        #expect(token.measure { 5 } == 5)
        struct Boom: Error {}
        #expect(throws: Boom.self) { try token.measure { throw Boom() } }
    }
}
#endif
