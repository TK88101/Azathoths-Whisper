import Foundation
import Testing

@testable import AzathothsWhisper

// AC8d／D14（simcodex R1 採納 Codex）：卡片詳情一批 AE 的「總」時限——每送一個 AE 前取剩餘時間當它的 timeout，用完就停
@Suite("AEBudget")
struct AEBudgetTests {
    private let start = ContinuousClock.Instant.now

    @Test func eachEventGetsWhatIsLeftOfTheBudget() {
        let budget = AEBudget(total: .milliseconds(1500), start: start)
        #expect(budget.remainingTicks(at: start) == 90)
        #expect(budget.remainingTicks(at: start + .milliseconds(500)) == 60)
        #expect(budget.remainingTicks(at: start + .milliseconds(1480)) == 1, "不足 2 tick 仍給 1 tick")
    }

    @Test func lessThanOneTickLeftStopsTheBatch() {
        let budget = AEBudget(total: .milliseconds(1500), start: start)
        #expect(budget.remainingTicks(at: start + .milliseconds(1490)) == nil)
        #expect(budget.remainingTicks(at: start + .milliseconds(1500)) == nil)
        #expect(budget.remainingTicks(at: start + .seconds(5)) == nil)
    }

    /// 送任何一個 AE 前的單一扣預算步驟（篩選與逐欄共用）：有剩就設 timeout，用完就不送
    @Test func spendingSetsTheRemainingTimeoutOrRefuses() {
        let budget = AEBudget(total: .milliseconds(1500), start: start)
        var timeouts: [Int] = []
        #expect(budget.spend(setTimeout: { timeouts.append($0) }, now: start + .milliseconds(500)))
        #expect(!budget.spend(setTimeout: { timeouts.append($0) }, now: start + .milliseconds(1495)))
        #expect(timeouts == [60], "用完時不得再設 timeout（不送 AE）")
    }

    /// 總時限與既有單一 AE 上限同為 1.5 秒：monitor 最多多等一批（H-04 的 3 秒口徑不變）
    @Test func detailsBudgetMatchesTheArtworkBound() {
        #expect(MusicAppleEventsClient.detailsBudget == .milliseconds(1500))
    }
}

// 逐欄讀取（每欄一個 AE）與欄位→TrackDetails 的純邏輯：從 AE client（覆蓋率豁免檔）搬出來才測得到
@Suite("AEBudget.readColumns")
struct AEBudgetReadColumnsTests {
    private let start = ContinuousClock.Instant.now

    @Test func everyColumnIsSentWithWhatIsLeftOfTheBudget() {
        let budget = AEBudget(total: .milliseconds(1500), start: start)
        var clock = start
        var timeouts: [Int] = []
        let columns = budget.readColumns(
            ["a", "b", "c"],
            setTimeout: { timeouts.append($0) },
            read: { key in clock += .milliseconds(500); return [key] },
            now: { clock }
        )
        #expect(columns?.map { $0 as? [String] } == [["a"], ["b"], ["c"]])
        #expect(timeouts == [90, 60, 30])
    }

    @Test func runningOutMidwayDropsTheWholeBatch() {
        let budget = AEBudget(total: .milliseconds(1500), start: start)
        var clock = start
        var sent: [String] = []
        let columns = budget.readColumns(
            ["a", "b", "c"],
            setTimeout: { _ in },
            read: { key in sent.append(key); clock += .milliseconds(800); return [key] },
            now: { clock }
        )
        #expect(columns == nil)
        #expect(sent == ["a", "b"], "用完就不再送下一個 AE")
    }
}

@Suite("TrackDetails.fromColumns")
struct TrackDetailsColumnsTests {
    @Test func columnsBecomeDetailsInTrackOrder() {
        let details = TrackDetails.fromColumns([
            ["00000000000000AA", "00000000000000BB"],
            ["Artist A", "Artist B"],
            ["Title A", "Title B"],
            ["Album A", NSNull()],
            [NSNumber(value: 1), NSNumber(value: 2)],
            [NSNumber(value: 7), NSNull()],
            ["words", NSNull()],
        ])
        #expect(details == [
            TrackDetails(persistentID: "00000000000000AA", artist: "Artist A", title: "Title A", album: "Album A",
                         discNumber: 1, trackNumber: 7, lyrics: "words"),
            TrackDetails(persistentID: "00000000000000BB", artist: "Artist B", title: "Title B", album: "",
                         discNumber: 2, trackNumber: 0, lyrics: nil),
        ])
    }

    @Test func rowsWithoutAPersistentIDAreDropped() {
        let details = TrackDetails.fromColumns([[NSNull(), ""], ["a", "b"], ["t", "u"], ["l", "m"], [1, 2], [3, 4], ["x", "y"]])
        #expect(details.isEmpty)
    }

    /// 各欄長度不一致或欄數不對＝批次讀取不完整：整批不採用（卡片退為 unknown）
    @Test func incompleteBatchesAreRejected() {
        #expect(TrackDetails.fromColumns([["A"], ["a"], ["t"], ["l"], [1], [2], []]).isEmpty)
        #expect(TrackDetails.fromColumns([["A"], ["a"]]).isEmpty)
    }
}
