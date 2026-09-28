import Foundation
import Testing

@testable import AzathothsWhisper

// 換歌平移：VM 的顯示層與過渡狀態（計劃 docs/plans/2026-09-26-coverflow-follow-playback-slide.md §3.1、§3.3、§3.7）。
// 換歌當下 `centerID` 立即是新的當前卡（與不平移時相同）；差別只在條帶多吃一張暫留的舊當前卡、多收到一個平移指令。
@MainActor
@Suite("CoverFlowViewModel.Slide")
struct CoverFlowViewModelSlideTests {
    private typealias F = DeckFixtures

    /// 逾時保險用可控時鐘：不放行就永遠不到期
    private func makeModel(clock: any PollClock = GatedPollClock(),
                           artwork: StubArtworkProvider = StubArtworkProvider()) -> CoverFlowViewModel {
        let model = CoverFlowViewModel(artwork: artwork, clock: clock)
        model.setPrefersReducedMotion(false)
        return model
    }

    /// 起點：[0…4]、正在播 C2、條帶回報它在正中
    private func settleOnC2(_ model: CoverFlowViewModel) {
        model.apply(F.deck([0, 1, 2, 3, 4], current: 2), isRealChange: true)
        model.playingCardCentering(cardID: "C2", isCentered: true)
    }

    /// 下一首：履歴還沒追上，正式牌組裡沒有剛播完的 C2
    private let nextDeck = DeckFixtures.deck([0, 1, 3, 4, 5], current: 3)

    /// 已經在往 C3 滑
    private func slidingToC3(clock: any PollClock = GatedPollClock(),
                             artwork: StubArtworkProvider = StubArtworkProvider()) -> CoverFlowViewModel {
        let model = makeModel(clock: clock, artwork: artwork)
        settleOnC2(model)
        model.apply(nextDeck, isRealChange: true)
        return model
    }

    private func ids(_ cards: [DeckCard]) -> [String] { cards.map(\.id) }

    private func details(_ persistentID: String, title: String) -> TrackDetails {
        TrackDetails(persistentID: persistentID, artist: "A", title: title, album: "L", discNumber: 1, trackNumber: 1, lyrics: nil)
    }

    // MARK: 平移

    @Test func aProvableNextTrackSlides() {
        let model = slidingToC3()

        #expect(model.centerID == "C3", "中心立即是新的當前卡")
        #expect(model.slide == CoverFlowSlideRequest(generation: 1, slots: 1))
        #expect(ids(model.cards) == ["C1", "C2", "C3", "C4", "C5"], "舊當前卡暫留在左鄰，最左一張讓位")
        #expect(ids(model.deck.cards) == ["C0", "C1", "C3", "C4", "C5"], "正式牌組不動")
        #expect(model.cards.first { $0.id == "C2" }?.side == .played)
    }

    @Test func aProvablePreviousTrackSlidesTheOtherWay() {
        let model = makeModel()
        settleOnC2(model)
        let back = DeckSnapshot(
            cards: [F.card(0), F.card(1), DeckCard(id: "O9", persistentID: "T9", side: .current)],
            currentCardID: "O9", upcoming: .pending
        )
        let hint = SlideHint(oldCardID: "C2", oldPersistentID: "T2", targetPersistentID: "T9", direction: .previous)

        model.apply(back, isRealChange: true, slideHint: hint)

        #expect(model.centerID == "O9")
        #expect(model.slide == CoverFlowSlideRequest(generation: 1, slots: -1))
        #expect(ids(model.cards) == ["C0", "C1", "O9", "C2"])
        #expect(model.cards.last?.side == .upcoming)
    }

    @Test func aRealChangeStillClearsTheOverride() {
        let model = makeModel()
        settleOnC2(model)
        model.userDidScroll(to: "C4")
        model.userDidScroll(to: "C2")
        model.apply(nextDeck, isRealChange: true)
        model.apply(nextDeck, isRealChange: false)
        #expect(model.centerID == "C3")
    }

    // MARK: 落定

    @Test func settlingRetiresTheKeptCardWithoutMovingTheCentre() {
        let model = slidingToC3()
        let indexWhileSliding = model.cards.firstIndex { $0.id == "C3" }

        model.slideDidSettle(generation: 1)

        #expect(model.slide == nil)
        #expect(model.transition == nil)
        #expect(ids(model.cards) == ids(model.deck.cards))
        #expect(model.cards.firstIndex { $0.id == "C3" } == indexWhileSliding, "正中卡位次不變，捲動位置才不必改")
        #expect(model.centerID == "C3")
    }

    @Test func theTimeoutSettlesWhenNoCompletionArrives() async {
        let clock = GatedPollClock()
        let model = slidingToC3(clock: clock)
        await clock.waitUntilPending(1)
        #expect(await clock.requested == [CoverFlowViewModel.slideTimeout])
        #expect(CoverFlowViewModel.slideTimeout == .seconds(Theme.Motion.layerShiftDuration * 2))
        #expect(model.slide != nil, "到期前仍在過渡")

        await clock.releaseAll()
        await model.slideTimeoutTaskForTesting?.value

        #expect(model.slide == nil)
        #expect(ids(model.cards) == ids(model.deck.cards))
    }

    @Test func aReportForAnotherGenerationIsIgnored() {
        let model = slidingToC3()
        model.slideDidSettle(generation: 0)
        model.slideDidSettle(generation: 2)
        #expect(model.slide == CoverFlowSlideRequest(generation: 1, slots: 1))
    }

    /// 完成回呼先到、逾時後到：第二次是 no-op，不得推翻使用者其後的操作
    @Test func settlingTwiceDoesNotUndoWhatTheUserDidSince() async {
        let clock = GatedPollClock()
        let model = slidingToC3(clock: clock)
        await clock.waitUntilPending(1)
        let timeout = model.slideTimeoutTaskForTesting

        model.slideDidSettle(generation: 1)
        model.userDidScroll(to: "C5")
        model.slideDidSettle(generation: 1)
        await clock.releaseAll()
        await timeout?.value

        #expect(model.centerID == "C5")
        model.apply(nextDeck, isRealChange: false)
        #expect(model.centerID == "C5", "抑制仍在")
    }

    /// 過渡已被下一次換歌結束，舊世代的回報才到
    @Test func aLateReportAfterTheTransitionWasReplacedIsIgnored() {
        let model = slidingToC3()
        model.apply(F.deck([1, 3, 4, 5, 6], current: 4), isRealChange: true)
        model.userDidScroll(to: "C6")

        model.slideDidSettle(generation: 1)

        #expect(model.centerID == "C6")
    }

    /// 使用者在過渡中停到暫留卡上；它落定後退場 → 回當前卡，抑制解除
    @Test func settlingWhileTheUserIsParkedOnTheKeptCardFallsBackToTheCurrentCard() {
        let model = slidingToC3()
        model.scrollPositionDidChange(to: "C2")
        #expect(model.centerID == "C2")

        model.slideDidSettle(generation: 1)

        #expect(model.centerID == "C3")
        model.apply(F.deck([0, 1, 3, 4, 5], current: 3), isRealChange: false)
        #expect(model.centerID == "C3")
    }

    @Test func draggingDuringTheSlideTakesOverAndTheSlideStillSettles() {
        let model = slidingToC3()
        model.scrollPositionDidChange(to: "C5")

        model.slideDidSettle(generation: 1)

        #expect(model.centerID == "C5")
        #expect(ids(model.cards) == ids(model.deck.cards))
        model.apply(nextDeck, isRealChange: false)
        #expect(model.centerID == "C5", "手動滑走後同曲更新不得搶回控制")
    }

    // MARK: 過渡中的其他更新

    /// 履歴追上：左鄰換成同一首歌的履歴卡 → 暫留卡原位留著，世代不變
    @Test func aNonRealUpdateKeepsTheSlideGoing() {
        let model = slidingToC3()
        model.apply(F.deck([1, 20, 3, 4, 5], current: 3, persistentIDs: [20: "T2"]), isRealChange: false)

        #expect(model.slide == CoverFlowSlideRequest(generation: 1, slots: 1))
        #expect(ids(model.cards) == ["C1", "C2", "C3", "C4", "C5"])
        #expect(ids(model.deck.cards) == ["C1", "C20", "C3", "C4", "C5"])

        model.slideDidSettle(generation: 1)
        #expect(ids(model.cards) == ["C1", "C20", "C3", "C4", "C5"])
    }

    @Test func aNonRealUpdateThatMovesTheTargetEndsTheSlide() {
        let model = slidingToC3()
        model.apply(F.deck([3, 4, 5], current: 3), isRealChange: false)
        #expect(model.slide == nil)
        #expect(ids(model.cards) == ["C3", "C4", "C5"])
        #expect(model.centerID == "C3")
    }

    /// 往回跳之後解析成佇列卡：同一首歌換了卡 ID
    @Test func theCurrentCardChangingIdentityEndsTheSlide() {
        let model = slidingToC3()
        model.apply(F.deck([0, 1, 30, 4, 5], current: 30, persistentIDs: [30: "T3"]), isRealChange: false)
        #expect(model.slide == nil)
        #expect(ids(model.cards) == ["C0", "C1", "C30", "C4", "C5"])
        #expect(model.centerID == "C30")
    }

    /// 過渡中又換歌：不承接尚未歸零的位移，直接定位
    @Test func anotherRealChangeDuringTheSlideIsDirect() {
        let model = slidingToC3()
        model.apply(F.deck([1, 3, 4, 5, 6], current: 4), isRealChange: true)

        #expect(model.slide == nil)
        #expect(model.centerID == "C4")
        #expect(ids(model.cards) == ["C1", "C3", "C4", "C5", "C6"])
    }

    @Test func aRealChangeAfterSettlingSlidesAgainWithANewGeneration() {
        let model = slidingToC3()
        model.slideDidSettle(generation: 1)
        model.playingCardCentering(cardID: "C3", isCentered: true)

        model.apply(F.deck([0, 1, 4, 5, 6], current: 4), isRealChange: true)

        #expect(model.slide == CoverFlowSlideRequest(generation: 2, slots: 1))
        #expect(model.centerID == "C4")
        #expect(ids(model.cards) == ["C1", "C3", "C4", "C5", "C6"])
    }

    // MARK: 不平移

    @Test func withoutTheStripsReportItIsDirect() {
        let model = makeModel()
        model.apply(F.deck([0, 1, 2, 3, 4], current: 2), isRealChange: true)
        model.apply(nextDeck, isRealChange: true)
        #expect(model.slide == nil)
        #expect(model.centerID == "C3")
        #expect(ids(model.cards) == ids(nextDeck.cards))
    }

    @Test func aPlayingCardThatLeftTheCentreIsDirect() {
        let model = makeModel()
        settleOnC2(model)
        model.playingCardCentering(cardID: "C2", isCentered: false)
        model.apply(nextDeck, isRealChange: true)
        #expect(model.slide == nil)
    }

    /// 幾何回報還在容差內，但 `centerID` 已經不是舊當前卡
    @Test func aCentreThatMovedAwayIsDirectEvenIfTheReportLags() {
        let model = makeModel()
        settleOnC2(model)
        model.userDidScroll(to: "C4")

        model.apply(nextDeck, isRealChange: true)

        #expect(model.slide == nil)
        #expect(model.centerID == "C3", "真實換歌照現行行為直接拉回")
    }

    @Test func scrollingAwayAndBackSlides() {
        let model = makeModel()
        settleOnC2(model)
        model.userDidScroll(to: "C4")
        model.playingCardCentering(cardID: "C2", isCentered: false)
        model.userDidScroll(to: "C2")
        model.playingCardCentering(cardID: "C2", isCentered: true)

        model.apply(nextDeck, isRealChange: true)

        #expect(model.slide == CoverFlowSlideRequest(generation: 1, slots: 1))
    }

    @Test func aNonRealUpdateNeverSlides() {
        let model = makeModel()
        settleOnC2(model)
        model.apply(nextDeck, isRealChange: false)
        #expect(model.slide == nil)
        #expect(model.centerID == "C3")
    }

    /// 同步到實值之前先當作「減少動態效果」已開
    @Test func reducedMotionIsAssumedUntilToldOtherwise() {
        let model = CoverFlowViewModel(artwork: StubArtworkProvider(), clock: GatedPollClock())
        settleOnC2(model)
        model.apply(nextDeck, isRealChange: true)
        #expect(model.slide == nil)
        #expect(model.centerID == "C3")
    }

    @Test func turningReducedMotionOnEndsTheSlide() {
        let model = slidingToC3()
        model.setPrefersReducedMotion(true)
        #expect(model.slide == nil)
        #expect(ids(model.cards) == ids(model.deck.cards))
        #expect(model.centerID == "C3")
    }

    // MARK: 播放卡在正中的回報

    @Test func thePlayingCardIsNotCentredUntilTheStripSaysSo() {
        let model = slidingToC3()
        #expect(!model.isPlayingCardCentered, "目標卡還在滑")
        model.playingCardCentering(cardID: "C3", isCentered: true)
        #expect(model.isPlayingCardCentered)
    }

    /// 卡片離開「正在播」之後不會再回報 false：舊回報不得在它又成為當前卡時被當成現況
    @Test func aStaleReportDoesNotSurviveTheCardComingBack() {
        let model = makeModel()
        settleOnC2(model)
        model.apply(F.deck([0, 1, 2, 3, 4], current: 3), isRealChange: true)
        model.userDidScroll(to: "C0")

        model.apply(F.deck([0, 1, 2, 3, 4], current: 2), isRealChange: false)

        #expect(!model.isPlayingCardCentered)
    }

    // MARK: 顯示牌組的消費端（§3.7）

    @Test func keptCardDetailsAndArtworkLastUntilTheSlideSettles() {
        let model = makeModel()
        settleOnC2(model)
        model.updateDetails(["T2": details("T2", title: "Two"), "T0": details("T0", title: "Zero")])

        model.apply(nextDeck, isRealChange: true)
        model.artworkDidStore("T2")

        #expect(model.details["T2"] != nil)
        #expect(model.artworkRevision(for: "T2") == 1)
        #expect(model.details["T0"] != nil, "最左那張只是顯示上讓位，仍在正式牌組裡")

        model.slideDidSettle(generation: 1)

        #expect(model.details["T2"] == nil)
        #expect(model.artworkRevision(for: "T2") == 0)
    }

    @Test func theCentreLabelIsTheNewTrackFromTheStart() {
        let model = makeModel()
        settleOnC2(model)
        model.updateDetails(["T2": details("T2", title: "Two"), "T3": details("T3", title: "Three")])
        model.apply(nextDeck, isRealChange: true)
        #expect(model.centerLabel == "A // Three")
        #expect(model.playingCardTitle == "Three")
    }

    @Test func keyboardSteppingWalksTheDisplayedCards() {
        let model = slidingToC3()
        model.stepCenter(by: -1)
        #expect(model.centerID == "C2", "左鄰是暫留的舊當前卡")
    }

    /// 顯示上讓位的那張仍在正式牌組裡：它的封面恢復通知不得被丟掉
    @Test func artworkRecoveryForTheYieldedCardIsKept() {
        let model = slidingToC3()
        model.artworkDidStore("T0")
        #expect(model.artworkRevision(for: "T0") == 1)
        model.slideDidSettle(generation: 1)
        #expect(model.artworkRevision(for: "T0") == 1)
    }

    /// 落定後牌組換回正式牌組：預取集合跟著重排，不再含暫留卡
    @Test func settlingReschedulesThePrefetch() async {
        let artwork = StubArtworkProvider()
        let model = makeModel(artwork: artwork)
        model.setVisible(true)
        settleOnC2(model)
        model.apply(nextDeck, isRealChange: true)
        await model.prefetchTaskForTesting?.value

        model.slideDidSettle(generation: 1)
        await model.prefetchTaskForTesting?.value

        #expect(await artwork.prefetchCommands.last == ["T4", "T1", "T5", "T0"])
    }

    @Test func prefetchCoversTheKeptCard() async {
        let artwork = StubArtworkProvider()
        let model = makeModel(artwork: artwork)
        model.setVisible(true)
        settleOnC2(model)

        model.apply(nextDeck, isRealChange: true)
        await model.prefetchTaskForTesting?.value

        #expect(await artwork.prefetchCommands.last == ["T4", "T2", "T5", "T1"])
    }
}
