import Foundation
import Testing

@testable import AzathothsWhisper

// Cover Flow VM 的牌組與居中（計劃 Q3a、§9.6 處置表）。VM 不再自己讀 Music：牌組由 LyricsFlowModel 給。
// 對應 H-04（換歌居中）、H-05（手動滑走不搶控制）、H-09（鍵盤步進）、D6（換牌與居中同一次更新）。
@MainActor
@Suite("CoverFlowViewModel.Deck")
struct CoverFlowViewModelDeckTests {
    private typealias F = DeckFixtures

    private func makeModel() -> CoverFlowViewModel {
        CoverFlowViewModel(artwork: StubArtworkProvider())
    }

    // MARK: H-04／D6

    // MARK: D6 播放卡是否在幾何正中（條帶回報；可點與否只看這個，不看 centerID）

    @Test func playingCardCountsAsCentredOnlyWhenTheStripSaysSo() {
        let model = makeModel()
        model.apply(F.deck([1, 2, 3], current: 2), isRealChange: true)
        #expect(!model.isPlayingCardCentered, "centerID 已是它，但條帶還沒回報：不算")
        model.playingCardCentering(cardID: "C2", isCentered: true)
        #expect(model.isPlayingCardCentered)
        model.playingCardCentering(cardID: "C2", isCentered: false)
        #expect(!model.isPlayingCardCentered)
    }

    /// AC3 無障礙標籤「Edit lyrics of %@」的曲名：只取播放卡的詳情，任何一環缺了就是空字串
    @Test func playingCardTitleComesOnlyFromThePlayingCardsDetails() {
        let model = makeModel()
        model.apply(F.deck([1, 2, 3], current: 2), isRealChange: true)
        #expect(model.playingCardTitle == "", "詳情未到")
        model.updateDetails(["T2": TrackDetails(persistentID: "T2", artist: "A", title: "Two", album: "L",
                                                discNumber: 1, trackNumber: 2, lyrics: nil)])
        #expect(model.playingCardTitle == "Two")
        model.apply(DeckSnapshot(cards: [F.card(1)], currentCardID: "C9", upcoming: .pending), isRealChange: true)
        #expect(model.playingCardTitle == "", "播放卡不在牌組")
        model.apply(F.deck([1, 3], current: nil), isRealChange: true)
        #expect(model.playingCardTitle == "", "沒有播放卡")
    }

    @Test func aReportForAnotherCardDoesNotCount() {
        let model = makeModel()
        model.apply(F.deck([1, 2, 3], current: 2), isRealChange: true)
        model.playingCardCentering(cardID: "C3", isCentered: true)
        #expect(!model.isPlayingCardCentered)
    }

    /// 換了播放卡：舊的回報失效，等新卡自己回報
    @Test func aNewPlayingCardStartsUncentred() {
        let model = makeModel()
        model.apply(F.deck([1, 2, 3], current: 2), isRealChange: true)
        model.playingCardCentering(cardID: "C2", isCentered: true)
        model.apply(F.deck([2, 3, 4], current: 3), isRealChange: true)
        #expect(!model.isPlayingCardCentered)
    }

    @Test func applyingADeckCentresOnItsCurrentCard() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 1), isRealChange: true)
        #expect(model.cards.map(\.id) == ["C0", "C1", "C2"])
        #expect(model.centerID == "C1")
    }

    /// 換歌（同一份清單）：下一張的 ID 不變，中心移過去（S5：換牌與設中心同一次更新）
    @Test func advancingMovesTheCentreToTheNextCard() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2, 3], current: 1), isRealChange: true)
        model.apply(F.deck([1, 2, 3, 4], current: 2), isRealChange: true)
        #expect(model.centerID == "C2")
        #expect(model.cards.first?.id == "C1")
    }

    @Test func rapidDecksLandOnTheLast() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.apply(F.deck([0, 1, 2], current: 1), isRealChange: true)
        model.apply(F.deck([0, 1, 2], current: 2), isRealChange: true)
        #expect(model.centerID == "C2")
    }

    /// 沒在播：中心停在最新播過的那張（最右）
    @Test func deckWithoutACurrentCardCentresOnTheNewestCard() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: nil), isRealChange: false)
        #expect(model.centerID == "C2")
    }

    @Test func emptyDeckClearsTheCentre() {
        let model = makeModel()
        model.apply(F.deck([0, 1], current: 1), isRealChange: true)
        model.apply(.empty, isRealChange: false)
        #expect(model.centerID == nil)
    }

    // MARK: H-05

    @Test func manualScrollSuppressesAutoCentreForTheSameTrack() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.userDidScroll(to: "C2")
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: false)
        #expect(model.centerID == "C2", "手動滑走後同曲更新不得搶回控制")
    }

    /// 同曲重發（forceRefresh）不是真實換歌，不得解除抑制
    @Test func sameTrackRefreshDoesNotClearTheOverride() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.userDidScroll(to: "C2")
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: false)
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: false)
        #expect(model.centerID == "C2")
    }

    @Test func realChangeClearsTheOverrideAndCentres() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.userDidScroll(to: "C2")
        model.apply(F.deck([0, 1, 2], current: 1), isRealChange: true)
        #expect(model.centerID == "C1", "真實換歌須解除抑制並居中")
    }

    /// 使用者停著的那張已不在新牌組（清單重寫）→ 回到當前那張並解除抑制
    @Test func userCentreThatLeftTheDeckFallsBackToTheCurrentCard() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.userDidScroll(to: "C2")
        model.apply(F.deck([7, 8, 9], current: 8), isRealChange: false)
        #expect(model.centerID == "C8")

        model.apply(F.deck([7, 8, 9], current: 9), isRealChange: false)
        #expect(model.centerID == "C9", "抑制已解除，之後的更新照常居中")
    }

    /// 程式化居中落定後的回呼（id 已等於 centerID）不得設回抑制
    @Test func settledProgrammaticCallbackDoesNotSetTheOverride() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 1), isRealChange: true)
        model.scrollPositionDidChange(to: "C1")
        model.apply(F.deck([0, 1, 2], current: 2), isRealChange: false)
        #expect(model.centerID == "C2")
    }

    /// 已知限制（原 H-05 註記照舊）：不同 id 的回呼一律視為使用者接管——
    /// D6 不帶動畫，程式化居中不產生途經回呼，故目前只有真正的拖曳會送來不同的 id
    @Test func differentIDCallbackIsTreatedAsUserTakeover() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.scrollPositionDidChange(to: "C1")
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: false)
        #expect(model.centerID == "C1")
    }

    // MARK: H-09

    @Test func stepMovesTheCentreByOffset() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.stepCenter(by: 1)
        #expect(model.centerID == "C1")
        model.stepCenter(by: 1)
        #expect(model.centerID == "C2")
        model.stepCenter(by: -1)
        #expect(model.centerID == "C1")
    }

    @Test func stepIsClampedAtBothEnds() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.stepCenter(by: -1)
        #expect(model.centerID == "C0")
        model.stepCenter(by: 99)
        #expect(model.centerID == "C2")
    }

    @Test func keyboardStepSuppressesAutoCentre() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.stepCenter(by: 2)
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: false)
        #expect(model.centerID == "C2")
    }

    @Test func stepOnAnEmptyDeckIsANoOp() {
        let model = makeModel()
        model.stepCenter(by: 1)
        #expect(model.centerID == nil)
    }

    // MARK: 徽章狀態（AC7）

    @Test func statusFollowsDetailsAndMarks() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2, 3], current: 0), isRealChange: true)
        model.updateDetails([
            "T0": TrackDetails(persistentID: "T0", artist: "a", title: "t", album: "l", discNumber: 1, trackNumber: 1, lyrics: "words"),
            "T1": TrackDetails(persistentID: "T1", artist: "a", title: "t", album: "l", discNumber: 1, trackNumber: 2, lyrics: ""),
            "T2": TrackDetails(persistentID: "T2", artist: "a", title: "t", album: "l", discNumber: 1, trackNumber: 3, lyrics: ""),
        ])
        model.updateMarks(["T2"])

        #expect(model.status(for: F.card(0)) == .present)
        #expect(model.status(for: F.card(1)) == .missing)
        #expect(model.status(for: F.card(2)) == .markedNone)
        #expect(model.status(for: F.card(3)) == .unknown, "還沒讀到詳情＝unknown，不是缺詞")
    }

    @Test func centreLabelUsesTheCentredCardsDetails() {
        let model = makeModel()
        model.apply(F.deck([0, 1], current: 1), isRealChange: true)
        #expect(model.centerLabel == CoverFlowCenterLabel.placeholder)
        model.updateDetails([
            "T1": TrackDetails(persistentID: "T1", artist: "Bjork", title: "Hyperballad", album: "Post", discNumber: 1, trackNumber: 1, lyrics: nil),
        ])
        #expect(model.centerLabel == "Bjork // Hyperballad")
    }
}
