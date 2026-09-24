import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 AC8、R3-1（當前出現位置解析）、R4-4（itID epoch）、AC8b（右側可用性）
@Suite("QueueSession")
struct QueueSessionTests {
    private typealias Item = QueueFixtures.Item

    private func snapshot(_ items: [Item]) -> QueueSnapshot {
        QueueSnapshot.parse(QueueFixtures.queue(list: items))!
    }

    private func pid(_ n: Int64) -> String { QueueFixtures.pid(n) }

    @Test func resolvesTheUniqueOccurrence() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)]))
            .resolvingCurrent(persistentID: pid(2), isRealChange: true)
        #expect(session.currentIndex == 1)
        #expect(session.upcoming == .available)
    }

    /// 實測（S8）：按下一首時檔案不重寫，位置由「上次位置的下一項」推進
    @Test func realChangeAdvancesToTheNextPosition() {
        // 同一首在清單出現兩次（插歌）：P2 在 1 與 4
        var session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 50), Item(3, itemID: 11), Item(4, itemID: 12), Item(2, itemID: 13)]))
            .resolvingCurrent(persistentID: pid(1), isRealChange: true)
        session = session.resolvingCurrent(persistentID: pid(2), isRealChange: true)
        #expect(session.currentIndex == 1, "插入的那個（較前）")
        session = session.resolvingCurrent(persistentID: pid(3), isRealChange: true)
        session = session.resolvingCurrent(persistentID: pid(4), isRealChange: true)
        session = session.resolvingCurrent(persistentID: pid(2), isRealChange: true)
        #expect(session.currentIndex == 4, "原本的那個（較後）")
    }

    @Test func sameTrackRefreshKeepsThePosition() {
        let session = QueueSession()
            .applying(snapshot([Item(2, itemID: 50), Item(3, itemID: 11), Item(2, itemID: 13)]))
            .resolvingCurrent(persistentID: pid(3), isRealChange: true)
            .resolvingCurrent(persistentID: pid(2), isRealChange: true)
            .resolvingCurrent(persistentID: pid(2), isRealChange: false)
        #expect(session.currentIndex == 2)
    }

    /// 對抗覆核 P2：往回跳到清單中重複的歌——不猜成後面那一個（舊邏輯選 index 3）
    @Test func backSkipOntoADuplicateIsUnresolved() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12), Item(1, itemID: 13)]))
            .resolvingCurrent(persistentID: pid(2), isRealChange: true)
            .resolvingCurrent(persistentID: pid(1), isRealChange: true)
        #expect(session.currentIndex == nil)
        #expect(session.upcoming == .pending, "先不顯示右側，也不宣稱讀不到")
    }

    /// 跳播到不相鄰的歌（或從專輯頁點播，檔案尚未重寫）：事件當下不猜，下一次輪詢再依唯一性定位
    @Test func nonAdjacentJumpWaitsForTheNextPoll() {
        var session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12), Item(4, itemID: 13)]))
            .resolvingCurrent(persistentID: pid(1), isRealChange: true)
            .resolvingCurrent(persistentID: pid(4), isRealChange: true)
        #expect(session.currentIndex == nil)
        session = session.resolvingCurrent(persistentID: pid(4), isRealChange: false)
        #expect(session.currentIndex == 3)
    }

    /// 無上次位置、同曲出現多次 → 無法唯一 → 不猜（退回）
    @Test func ambiguousWithoutAHintIsUnresolved() {
        let session = QueueSession()
            .applying(snapshot([Item(2, itemID: 1), Item(3, itemID: 2), Item(2, itemID: 3)]))
            .resolvingCurrent(persistentID: pid(2), isRealChange: true)
        #expect(session.currentIndex == nil)
    }

    /// 重寫（插歌）後以 itID 找回同一項（事實 23：既有項 itID 不變）
    @Test func rewriteKeepsThePositionThroughTheItemID() {
        let before = snapshot([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)])
        let afterInsert = snapshot([Item(1, itemID: 10), Item(2, itemID: 11), Item(9, itemID: 99), Item(3, itemID: 12)])
        let session = QueueSession()
            .applying(before)
            .resolvingCurrent(persistentID: pid(2), isRealChange: true)
            .applying(afterInsert)
        #expect(session.currentIndex == 1)
        #expect(session.cardID(at: 3) == "q:0:12", "既有項 ID 不因插入改變")
        #expect(session.cardID(at: 2) == "q:0:99")
    }

    /// Genius 重建：舊位置的 itID 已不在新清單 → 依唯一性重新定位
    @Test func rebuildResolvesByUniquenessWhenTheOldItemIsGone() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 11)]))
            .resolvingCurrent(persistentID: pid(2), isRealChange: true)
            .applying(snapshot([Item(7, itemID: 70), Item(8, itemID: 71)]))
            .resolvingCurrent(persistentID: pid(7), isRealChange: true)
        #expect(session.currentIndex == 0)
    }

    /// R4-4：同一 itID 在新快照指向不同的歌 → epoch 加一，卡 ID 隨之不同
    @Test func reusedItemIDForADifferentTrackBumpsTheEpoch() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10)]))
            .applying(snapshot([Item(2, itemID: 10)]))
        #expect(session.cardID(at: 0) == "q:1:10")
    }

    @Test func sameItemIDSameTrackKeepsTheEpochAcrossRewrites() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 11)]))
            .applying(snapshot([Item(5, itemID: 20), Item(1, itemID: 10), Item(2, itemID: 11)]))
        #expect(session.cardID(at: 1) == "q:0:10")
    }

    /// 對抗覆核 P2：同一快照內重複的 itID 不得產生相同的卡 ID（否則牌組去重會靜默丟卡）
    @Test func duplicateItemIDsGetDistinctCardIDs() {
        let session = QueueSession().applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 10), Item(3, itemID: 11)]))
        #expect(session.cardID(at: 0) == "q:0:10")
        #expect(session.cardID(at: 1) == "q:0:10#1")
        let rewritten = session.applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 10), Item(9, itemID: 12)]))
        #expect(rewritten.cardID(at: 0) == "q:0:10", "重複項不得讓 epoch 每次重寫都跳")
        #expect(rewritten.cardID(at: 1) == "q:0:10#1")
    }

    @Test func entriesWithoutItemIDUseOccurrenceWithinTheSnapshot() {
        let session = QueueSession().applying(snapshot([Item(4), Item(5), Item(4)]))
        #expect(session.cardID(at: 0) == "q:p:\(pid(4))#0")
        #expect(session.cardID(at: 2) == "q:p:\(pid(4))#1")
    }

    // MARK: 右側可用性（AC8b）

    @Test func beforeAnyReadTheUpcomingSideIsPending() {
        #expect(QueueSession().upcoming == .pending)
    }

    @Test func failedReadWithoutAValidSnapshotIsUnavailable() {
        #expect(QueueSession().markingReadFailed().upcoming == .unavailable)
    }

    @Test func failedReadKeepsTheLastValidSnapshot() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10), Item(2, itemID: 11)]))
            .resolvingCurrent(persistentID: pid(1), isRealChange: true)
            .markingReadFailed()
        #expect(session.currentIndex == 0)
        #expect(session.upcoming == .available)
    }

    /// 專輯點播的 3 秒空窗（事實 22）：第一次找不到先 pending（不顯示「讀不到」），連續第二次才 unavailable
    @Test func currentNotInTheListIsPendingOnceThenUnavailable() {
        var session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10)]))
            .resolvingCurrent(persistentID: pid(9), isRealChange: true)
        #expect(session.upcoming == .pending)
        session = session.resolvingCurrent(persistentID: pid(9), isRealChange: false)
        #expect(session.upcoming == .unavailable)
    }

    @Test func aSuccessfulResolveClearsTheMissStreak() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10)]))
            .resolvingCurrent(persistentID: pid(9), isRealChange: true)
            .applying(snapshot([Item(9, itemID: 90)]))
            .resolvingCurrent(persistentID: pid(9), isRealChange: false)
        #expect(session.currentIndex == 0)
        #expect(session.upcoming == .available)
    }

    /// D15：Music 未執行 → session 失效
    @Test func invalidationDropsTheSnapshotAndPosition() {
        let session = QueueSession()
            .applying(snapshot([Item(1, itemID: 10)]))
            .resolvingCurrent(persistentID: pid(1), isRealChange: true)
            .invalidated()
        #expect(session.snapshot == nil)
        #expect(session.currentIndex == nil)
        #expect(session.upcoming == .pending)
    }
}
