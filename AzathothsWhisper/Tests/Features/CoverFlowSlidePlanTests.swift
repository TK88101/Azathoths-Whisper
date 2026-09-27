import Foundation
import Testing

@testable import AzathothsWhisper

// 換歌平移的判定與過渡顯示牌組（計劃 docs/plans/2026-09-26-coverflow-follow-playback-slide.md §3.1、§3.2）。
// 卡 ID 沿用 AC8 的前綴：`h:` 履歴、`q:` 佇列、`o:` 觀察到的播放。
@Suite("CoverFlowSlidePlan")
struct CoverFlowSlidePlanTests {
    private static let limit = 21

    private func history(_ n: Int) -> DeckCard { DeckCard(id: "h:H\(n)#0", persistentID: "H\(n)", side: .played) }
    private func queue(_ name: String, _ side: DeckCard.Side) -> DeckCard { DeckCard(id: "q:0:\(name)", persistentID: name, side: side) }
    private func observed(_ name: String, _ side: DeckCard.Side) -> DeckCard { DeckCard(id: "o:\(name)#0", persistentID: name, side: side) }
    private func played(_ name: String) -> DeckCard { DeckCard(id: "h:\(name)#0", persistentID: name, side: .played) }

    private func histories(_ range: ClosedRange<Int>) -> [DeckCard] { range.map(history) }
    private func upcoming(_ names: [String]) -> [DeckCard] { names.map { queue($0, .upcoming) } }

    private func deck(_ cards: [DeckCard], current: String) -> DeckSnapshot {
        DeckSnapshot(cards: cards, currentCardID: current, upcoming: .available)
    }

    private func ids(_ cards: [DeckCard]?) -> [String]? { cards?.map(\.id) }

    /// `.slide` 的過渡顯示牌組（由同一組參數經 `display` 算出）
    private func display(of plan: CoverFlowSlidePlan, canonical: DeckSnapshot) -> [DeckCard]? {
        guard case .slide(let old, let target, let slots, let targetIndex) = plan else { return nil }
        return CoverFlowSlidePlan.display(canonical: canonical, old: old, target: target, slots: slots,
                                          targetIndex: targetIndex, limit: Self.limit)
    }

    // MARK: §3.2 對照表

    /// 佇列，下一首：履歴還沒追上，canonical 沒有剛播完的 A → 暫留在左鄰、剔掉最左一張
    @Test func queueNextKeepsTheOldCardOnTheLeftAndDropsTheFarthestLeft() {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old] + upcoming(["B", "C", "D"])
        let canonical = deck(histories(1...10) + [queue("B", .current)] + upcoming(["C", "D", "E"]), current: "q:0:B")

        let plan = CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit)

        #expect(plan == .slide(old: queue("A", .played), target: "q:0:B", slots: 1, targetIndex: 10))
        #expect(ids(display(of: plan, canonical: canonical))
            == (2...10).map { "h:H\($0)#0" } + ["q:0:A", "q:0:B", "q:0:C", "q:0:D", "q:0:E"])
    }

    /// 佇列，下一首：履歴已追上（左鄰是同一首歌的履歴卡）→ 暫留卡原位取代它，張數不變
    @Test func queueNextReplacesTheCaughtUpHistoryCardInPlace() {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old] + upcoming(["B", "C"])
        let canonical = deck(histories(2...10) + [played("A"), queue("B", .current)] + upcoming(["C", "D"]), current: "q:0:B")

        let plan = CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit)

        #expect(plan == .slide(old: queue("A", .played), target: "q:0:B", slots: 1, targetIndex: 10))
        #expect(ids(display(of: plan, canonical: canonical))
            == (2...10).map { "h:H\($0)#0" } + ["q:0:A", "q:0:B", "q:0:C", "q:0:D"])
    }

    /// 佇列，上一首：往回跳當下中心是新身分的 `o:` 卡、右側清空；方向靠 hint → 暫留在右鄰
    @Test func queuePreviousNeedsTheHintAndKeepsTheOldCardOnTheRight() {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old] + upcoming(["X", "Y"])
        let canonical = deck(histories(1...10) + [observed("B", .current)], current: "o:B#0")
        let hint = SlideHint(oldCardID: "q:0:A", oldPersistentID: "A", targetPersistentID: "B", direction: .previous)

        let plan = CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: hint, limit: Self.limit)

        #expect(plan == .slide(old: queue("A", .upcoming), target: "o:B#0", slots: -1, targetIndex: 10))
        #expect(ids(display(of: plan, canonical: canonical)) == (1...10).map { "h:H\($0)#0" } + ["o:B#0", "q:0:A"])
    }

    /// 退回模式，下一首：舊當前卡本來就留在 canonical 的左鄰 → 顯示牌組＝canonical
    @Test func observedNextUsesTheCanonicalDeckAsIs() {
        let old = observed("A", .current)
        let left = (1...10).map { observed("P\($0)", .played) }
        let previous = left + [old]
        let canonical = deck(Array(left.dropFirst()) + [observed("A", .played), observed("B", .current)], current: "o:B#0")

        let plan = CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit)

        #expect(plan == .slide(old: observed("A", .played), target: "o:B#0", slots: 1, targetIndex: 10))
        #expect(display(of: plan, canonical: canonical) == canonical.cards)
    }

    // MARK: 不平移

    /// 左側還在長（履歴不足）：目標卡的新位次 ≠ 舊當前卡的原位次，捲動位置非改不可
    @Test func aGrowingLeftSideIsDirect() {
        let old = observed("A", .current)
        let previous = [observed("P1", .played), old]
        let canonical = deck([observed("P1", .played), observed("A", .played), observed("B", .current)], current: "o:B#0")
        #expect(CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit) == .direct)
    }

    /// 暫留卡要插在左側，但左側沒有可剔的卡
    @Test func nothingToDropOnTheLeftIsDirect() {
        let old = queue("A", .current)
        let previous = [old] + upcoming(["B", "C"])
        let canonical = deck([queue("B", .current)] + upcoming(["C"]), current: "q:0:B")
        #expect(CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit) == .direct)
    }

    /// 跳播到不相鄰的歌
    @Test func aNonAdjacentTargetIsDirect() {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old] + upcoming(["B", "C", "D"])
        let canonical = deck(histories(1...10) + [queue("C", .current)] + upcoming(["D"]), current: "q:0:C")
        #expect(CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit) == .direct)
    }

    /// 方向無從證明：目標是新身分的卡、舊當前卡不在 canonical、又沒有 hint
    @Test func anUnprovableDirectionIsDirect() {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old] + upcoming(["X"])
        let canonical = deck(histories(1...10) + [observed("B", .current)], current: "o:B#0")
        #expect(CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit) == .direct)
    }

    @Test(arguments: [
        SlideHint(oldCardID: "q:0:Z", oldPersistentID: "A", targetPersistentID: "B", direction: .previous),
        SlideHint(oldCardID: "q:0:A", oldPersistentID: "Z", targetPersistentID: "B", direction: .previous),
        SlideHint(oldCardID: "q:0:A", oldPersistentID: "A", targetPersistentID: "Z", direction: .previous),
    ])
    func aHintAboutAnotherCardOrTrackIsIgnored(hint: SlideHint) {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old] + upcoming(["X"])
        let canonical = deck(histories(1...10) + [observed("B", .current)], current: "o:B#0")
        #expect(CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: hint, limit: Self.limit) == .direct)
    }

    /// 牌組說下一首、hint 說上一首：兩份證據互相矛盾就不滑
    @Test func aHintContradictingTheDeckIsDirect() {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old] + upcoming(["B", "C"])
        let canonical = deck(histories(1...10) + [queue("B", .current)] + upcoming(["C"]), current: "q:0:B")
        let hint = SlideHint(oldCardID: "q:0:A", oldPersistentID: "A", targetPersistentID: "B", direction: .previous)
        #expect(CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: hint, limit: Self.limit) == .direct)
    }

    @Test func theSameCardStayingCurrentIsDirect() {
        let old = queue("A", .current)
        let previous = histories(1...10) + [old]
        let canonical = deck(histories(2...10) + [played("Z"), old], current: "q:0:A")
        #expect(CoverFlowSlidePlan.make(previousDisplay: previous, old: old, canonical: canonical, hint: nil, limit: Self.limit) == .direct)
    }

    @Test func aDeckWithoutACurrentCardIsDirect() {
        let old = queue("A", .current)
        let canonical = DeckSnapshot(cards: histories(1...10), currentCardID: nil, upcoming: .pending)
        #expect(CoverFlowSlidePlan.make(previousDisplay: histories(1...10) + [old], old: old, canonical: canonical,
                                        hint: nil, limit: Self.limit) == .direct)
    }

    /// 舊當前卡不在目前的顯示牌組裡：沒有「原位次」可比
    @Test func anOldCardMissingFromTheDisplayIsDirect() {
        let old = queue("A", .current)
        let canonical = deck(histories(1...10) + [queue("B", .current)], current: "q:0:B")
        #expect(CoverFlowSlidePlan.make(previousDisplay: histories(1...10) + upcoming(["B"]), old: old, canonical: canonical,
                                        hint: nil, limit: Self.limit) == .direct)
    }

    // MARK: 過渡顯示牌組（過渡中 canonical 變動時重算）

    /// 履歴在過渡中追上：由「插入＋剔最左」變成「原位取代」，目標卡位次不變
    @Test func theDisplaySurvivesHistoryCatchingUp() {
        let caughtUp = deck(histories(2...10) + [played("A"), queue("B", .current)] + upcoming(["C"]), current: "q:0:B")
        let cards = CoverFlowSlidePlan.display(canonical: caughtUp, old: queue("A", .played), target: "q:0:B", slots: 1,
                                               targetIndex: 10, limit: Self.limit)
        #expect(ids(cards) == (2...10).map { "h:H\($0)#0" } + ["q:0:A", "q:0:B", "q:0:C"])
    }

    /// 左側張數變了 → 目標卡位次對不上
    @Test func aChangedLeftCountEndsTheTransition() {
        let shrunk = deck(histories(1...5) + [queue("B", .current)], current: "q:0:B")
        #expect(CoverFlowSlidePlan.display(canonical: shrunk, old: queue("A", .played), target: "q:0:B", slots: 1,
                                           targetIndex: 10, limit: Self.limit) == nil)
    }

    /// 當前卡換了身分（往回跳後解析成佇列卡）
    @Test func aCurrentCardChangingIdentityEndsTheTransition() {
        let resolved = deck(histories(1...10) + [queue("B", .current), queue("A", .upcoming)], current: "q:0:B")
        #expect(CoverFlowSlidePlan.display(canonical: resolved, old: queue("A", .upcoming), target: "o:B#0", slots: -1,
                                           targetIndex: 10, limit: Self.limit) == nil)
    }

    /// 右側已滿時暫留在右鄰：剔掉最右一張，不超過上限
    @Test func insertingOnTheRightRespectsTheLimit() {
        let right = (1...10).map { "R\($0)" }
        let canonical = deck(histories(1...10) + [observed("B", .current)] + upcoming(right), current: "o:B#0")
        let cards = CoverFlowSlidePlan.display(canonical: canonical, old: queue("A", .upcoming), target: "o:B#0", slots: -1,
                                               targetIndex: 10, limit: Self.limit)
        #expect(cards?.count == Self.limit)
        #expect(ids(cards)?.suffix(3) == ["q:0:R7", "q:0:R8", "q:0:R9"])
        #expect(cards?[11].id == "q:0:A")
    }

    /// canonical 裡已有同 ID 的卡但不在緊鄰位置：不重複放、也不滑
    @Test func anOldCardElsewhereInTheDeckEndsTheTransition() {
        let canonical = deck([queue("A", .played)] + histories(1...9) + [queue("B", .current)], current: "q:0:B")
        #expect(CoverFlowSlidePlan.display(canonical: canonical, old: queue("A", .played), target: "q:0:B", slots: 1,
                                           targetIndex: 10, limit: Self.limit) == nil)
    }
}
