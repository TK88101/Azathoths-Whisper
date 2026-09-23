import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// Cover Flow VM 的預取與封面版本（計劃 Q3a、§9.6；原 H-06 預取語義改為「牌組」）。
// 預取送的是 persistentID（同曲出現多張卡時只取一次）。
@MainActor
@Suite("CoverFlowViewModel.Prefetch")
struct CoverFlowViewModelPrefetchTests {
    private typealias F = DeckFixtures

    private func makeModel() -> (CoverFlowViewModel, StubArtworkProvider) {
        let artwork = StubArtworkProvider()
        return (CoverFlowViewModel(artwork: artwork), artwork)
    }

    /// 九張、可見、中心在 C4、首批預取已送達
    private func centredOnC4() async -> (CoverFlowViewModel, StubArtworkProvider) {
        let (model, artwork) = makeModel()
        model.setVisible(true)
        model.apply(F.deck(Array(0...8), current: 4), isRealChange: true)
        await model.prefetchTaskForTesting?.value
        return (model, artwork)
    }

    @Test func applyingPrefetchesAroundTheCentre() async {
        let (_, artwork) = await centredOnC4()
        let last = await artwork.prefetchCommands.last ?? []
        #expect(last == ["T5", "T3", "T6", "T2", "T7", "T1", "T8", "T0"])
        #expect(!last.contains("T4"), "中心由 View 的 explicit 請求取，不進預取集合")
    }

    @Test func userScrollPrefetchesInTheScrollDirection() async {
        let (model, artwork) = await centredOnC4()
        model.userDidScroll(to: "C3")
        await model.prefetchTaskForTesting?.value
        #expect((await artwork.prefetchCommands.last ?? []).first == "T2")
    }

    @Test func keyboardStepPrefetchesInTheStepDirection() async {
        let (model, artwork) = await centredOnC4()
        model.stepCenter(by: 1)
        await model.prefetchTaskForTesting?.value
        #expect((await artwork.prefetchCommands.last ?? []).first == "T6")
    }

    /// 清單重寫：新牌組的預取集合取代舊的（舊封面不得繼續佔用 AE 佇列）
    @Test func aRebuiltDeckReplacesThePrefetchSet() async {
        let (model, artwork) = await centredOnC4()
        model.apply(F.deck([20, 21, 22], current: 21), isRealChange: true)
        await model.prefetchTaskForTesting?.value
        #expect(await artwork.prefetchCommands.last == ["T22", "T20"])
    }

    /// 畫面降下或切到 Batch：不可見就取消預取
    @Test func hidingCancelsThePrefetch() async {
        let (model, artwork) = await centredOnC4()
        model.setVisible(false)
        await model.prefetchTaskForTesting?.value
        #expect((await artwork.prefetchCommands.last ?? ["not-empty"]).isEmpty)
    }

    @Test func hiddenModelDoesNotPrefetch() async {
        let (model, artwork) = makeModel()
        model.apply(F.deck(Array(0...8), current: 4), isRealChange: true)
        await model.prefetchTaskForTesting?.value
        #expect(await artwork.prefetchCommands.isEmpty)
    }

    @Test func becomingVisiblePrefetchesTheCurrentWindow() async {
        let (model, artwork) = makeModel()
        model.apply(F.deck(Array(0...8), current: 4), isRealChange: true)
        model.setVisible(true)
        await model.prefetchTaskForTesting?.value
        #expect(await artwork.prefetchCommands.last?.first == "T5")
    }

    @Test func stalePrefetchCommandsAreSkipped() async {
        let (model, artwork) = await centredOnC4()
        model.userDidScroll(to: "C5")
        model.userDidScroll(to: "C6")
        model.userDidScroll(to: "C7")
        await model.prefetchTaskForTesting?.value
        #expect((await artwork.prefetchCommands.last ?? []).first == "T8")
    }

    /// 同曲在牌組出現多張（重播、插歌）：只取一次
    @Test func duplicatePersistentIDsArePrefetchedOnce() async {
        let (model, artwork) = makeModel()
        model.setVisible(true)
        model.apply(F.deck([0, 1, 2, 3], current: 0, persistentIDs: [2: "T1", 3: "T0"]), isRealChange: true)
        await model.prefetchTaskForTesting?.value
        #expect(await artwork.prefetchCommands.last == ["T1"], "中心的 T0 與重複的 T1 各不重取")
    }

    // MARK: 封面版本

    @Test func artworkRevisionBumpsOnlyForTheStoredID() {
        let (model, _) = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.artworkDidStore("T2")
        #expect(model.artworkRevision(for: "T2") == 1)
        #expect(model.artworkRevision(for: "T1") == 0)
    }

    @Test func storeNotificationFromTheProviderBumpsTheRevision() async {
        let (model, artwork) = makeModel()
        model.observeArtworkStores(from: artwork)
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        // 訂閱是非同步登記的：先等登記完成，否則通知發得太早、無人接收
        await waitFor { await artwork.hasStoreHandler }
        await artwork.emitStored("T2")
        await waitUntil { model.artworkRevision(for: "T2") == 1 }
        #expect(model.artworkRevision(for: "T2") == 1)
    }

    @Test func storedNotificationForAnUnknownIDIsIgnored() {
        let (model, _) = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.artworkDidStore("NOT-IN-DECK")
        #expect(model.artworkRevision(for: "NOT-IN-DECK") == 0)
    }

    /// 離開牌組的歌，版本號一併丟掉（否則長時間聽歌會讓字典無界增長）
    @Test func revisionsOfTracksThatLeftTheDeckAreDropped() {
        let (model, _) = makeModel()
        model.apply(F.deck([0, 1, 2], current: 0), isRealChange: true)
        model.artworkDidStore("T2")
        model.apply(F.deck([5, 6], current: 5), isRealChange: true)
        model.apply(F.deck([2, 5, 6], current: 5), isRealChange: false)
        #expect(model.artworkRevision(for: "T2") == 0)
    }
}

/// 封面替身：VM 測試不關心圖片內容，只關心**預取命令的內容與順序**
actor StubArtworkProvider: ArtworkProviding {
    private(set) var prefetchCommands: [[String]] = []
    private var onStored: (@Sendable (String) -> Void)?

    func artwork(for persistentID: String) async -> NSImage? { nil }

    func prefetch(_ persistentIDs: [String]) async {
        prefetchCommands.append(persistentIDs)
    }

    func setOnStored(_ handler: (@Sendable (String) -> Void)?) async {
        onStored = handler
    }

    func emitStored(_ persistentID: String) {
        onStored?(persistentID)
    }

    var hasStoreHandler: Bool { onStored != nil }
}
