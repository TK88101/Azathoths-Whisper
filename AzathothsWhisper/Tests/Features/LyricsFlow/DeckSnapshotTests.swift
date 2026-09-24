import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 AC8／AC8e：左＝Music 履歴（或觀察到的歷史）、中＝當前、右＝清單中當前之後；卡 ID 規則
@Suite("DeckSnapshot")
struct DeckSnapshotTests {
    private typealias Item = QueueFixtures.Item

    private func pid(_ n: Int64) -> String { QueueFixtures.pid(n) }

    private func session(_ items: [Item], current: Int64) -> QueueSession {
        QueueSession()
            .applying(QueueSnapshot.parse(QueueFixtures.queue(list: items))!)
            .resolvingCurrent(persistentID: pid(current), isRealChange: true)
    }

    private func history(_ ids: [Int64], keep: Int = 10) -> DeckSnapshot.PlayedSource {
        .musicHistory(HistorySnapshot.parse(QueueFixtures.history(ids), keepLast: keep)!)
    }

    @Test func leftHistoryCentreCurrentRightUpcoming() {
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(2), occurrence: 1),
            played: history([7, 8]),
            queue: session([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12), Item(4, itemID: 13)], current: 2),
            window: 10
        )
        #expect(deck.cards.map(\.side) == [.played, .played, .current, .upcoming, .upcoming])
        #expect(deck.cards.map(\.persistentID) == [pid(7), pid(8), pid(2), pid(3), pid(4)])
        #expect(deck.currentCardID == "q:0:11")
        #expect(deck.upcoming == .available)
    }

    /// 對抗覆核 P2：左側若出現與中心同 ID 的卡，保中心、剔左側（中心＝播放中，永遠在）
    @Test func theCentreCardSurvivesACollidingPlayedCard() {
        let early = ListeningHistory()
            .recording(.init(persistentID: pid(1), occurrence: 1))
            .recording(.init(persistentID: pid(2), occurrence: 2))
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(2), occurrence: 2),
            played: .observed(early),
            queue: QueueSession(),
            window: 10
        )
        #expect(deck.cards.map(\.id).contains(deck.currentCardID ?? "-"))
        #expect(deck.cards.last?.side == .current)
        #expect(deck.cards.count == 2)
    }

    @Test func aHugeWindowDoesNotOverflow() {
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(1), occurrence: 1),
            played: history([7]),
            queue: session([Item(1, itemID: 10), Item(2, itemID: 11)], current: 1),
            window: .max
        )
        #expect(deck.cards.map(\.persistentID) == [pid(7), pid(1), pid(2)])
    }

    @Test func windowLimitsBothSides() {
        let items = (1...30).map { Item(Int64($0), itemID: Int64(100 + $0)) }
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(15), occurrence: 1),
            played: history(Array(40...60)),
            queue: session(items, current: 15),
            window: 3
        )
        #expect(deck.cards.filter { $0.side == .played }.map(\.persistentID) == [pid(58), pid(59), pid(60)])
        #expect(deck.cards.filter { $0.side == .upcoming }.map(\.persistentID) == [pid(16), pid(17), pid(18)])
    }

    /// 換歌（同一份清單）：下一首的卡 ID 在它成為中心前後不變——條帶才能平滑平移（S5）
    @Test func theNextCardKeepsItsIDWhenItBecomesCurrent() {
        let items = [Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)]
        let before = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(1), occurrence: 1),
            played: history([]), queue: session(items, current: 1), window: 10
        )
        let after = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(2), occurrence: 2),
            played: history([1]),
            queue: session(items, current: 1).resolvingCurrent(persistentID: pid(2), isRealChange: true),
            window: 10
        )
        let nextBefore = before.cards.first { $0.side == .upcoming }?.id
        #expect(nextBefore == after.currentCardID)
    }

    /// R4-7：同曲重播可同時在左（播完的那次）與中（這一次），不互相去重
    @Test func theSameTrackMayAppearOnTheLeftAndInTheCentre() {
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(2), occurrence: 3),
            played: history([2]),
            queue: session([Item(2, itemID: 11)], current: 2),
            window: 10
        )
        #expect(deck.cards.map(\.persistentID) == [pid(2), pid(2)])
        #expect(Set(deck.cards.map(\.id)).count == 2)
    }

    @Test func historyCardIDsCountOccurrencesFromTheNewest() {
        let deck = DeckSnapshot.build(
            nowPlaying: nil, played: history([5, 6, 5]), queue: QueueSession(), window: 10
        )
        #expect(deck.cards.map(\.id) == ["h:\(pid(5))#1", "h:\(pid(6))#0", "h:\(pid(5))#0"])
    }

    /// 右側不可用：中心退回 `o:` 身分，右側空，可用性照實帶出（AC8b）
    @Test func withoutAResolvedQueuePositionTheCentreFallsBack() {
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(9), occurrence: 4),
            played: history([1]),
            queue: QueueSession().markingReadFailed(),
            window: 10
        )
        #expect(deck.currentCardID == "o:\(pid(9))#4")
        #expect(deck.cards.map(\.side) == [.played, .current])
        #expect(deck.upcoming == .unavailable)
    }

    /// 左側退回（History 不可讀）：觀察到的歷史，ID 與它曾為中心時相同
    @Test func observedHistoryReusesTheIDTheTrackHadAsCentre() {
        let observed = ListeningHistory().recording(ListeningHistory.Play(persistentID: pid(3), occurrence: 7))
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(4), occurrence: 8),
            played: .observed(observed),
            queue: QueueSession().markingReadFailed(),
            window: 10
        )
        #expect(deck.cards.map(\.id) == ["o:\(pid(3))#7", "o:\(pid(4))#8"])
    }

    @Test func notPlayingShowsOnlyTheLeftSide() {
        let deck = DeckSnapshot.build(nowPlaying: nil, played: history([1, 2]), queue: QueueSession(), window: 10)
        #expect(deck.currentCardID == nil)
        #expect(deck.cards.allSatisfy { $0.side == .played })
    }

    @Test func cardIDsAreUniqueWithinADeck() {
        let items = [Item(1, itemID: 10), Item(1, itemID: 11), Item(1, itemID: 12)]
        let deck = DeckSnapshot.build(
            nowPlaying: DeckSnapshot.NowPlaying(persistentID: pid(1), occurrence: 1),
            played: history([1, 1]),
            queue: QueueSession()
                .applying(QueueSnapshot.parse(QueueFixtures.queue(list: items))!)
                .resolvingCurrent(persistentID: pid(1), isRealChange: false),
            window: 10
        )
        #expect(Set(deck.cards.map(\.id)).count == deck.cards.count)
    }
}
