import Testing

@testable import AzathothsWhisper

// 自 NowPlayingMonitor 抽出的忙碌記帳（A1 計劃 §3.3）。回傳的是「轉移」，不是現況
@Suite("BusyLedger")
struct BusyLedgerTests {
    @Test func startsIdle() {
        #expect(BusyLedger().isIdle)
    }

    @Test func firstBusySourceIsBecameBusy() {
        var ledger = BusyLedger()
        #expect(ledger.set(true, source: .editor) == .becameBusy)
        #expect(!ledger.isIdle)
    }

    @Test func onlyTheLastSourceReleasingBecomesIdle() {
        var ledger = BusyLedger()
        _ = ledger.set(true, source: .editor)
        #expect(ledger.set(true, source: .batch) == .unchanged)
        #expect(ledger.set(false, source: .editor) == .unchanged)
        #expect(!ledger.isIdle)
        #expect(ledger.set(false, source: .batch) == .becameIdle)
        #expect(ledger.isIdle)
    }

    /// 已空閒時再送 false 不得當成「變成空閒」——否則會錯觸補讀
    @Test func releasingWhileAlreadyIdleIsUnchanged() {
        var ledger = BusyLedger()
        #expect(ledger.set(false, source: .editor) == .unchanged)
        _ = ledger.set(true, source: .editor)
        _ = ledger.set(false, source: .editor)
        #expect(ledger.set(false, source: .editor) == .unchanged)
    }

    @Test func repeatedBusyFromTheSameSourceIsUnchanged() {
        var ledger = BusyLedger()
        _ = ledger.set(true, source: .batch)
        #expect(ledger.set(true, source: .batch) == .unchanged)
        #expect(ledger.set(false, source: .batch) == .becameIdle)
    }
}
