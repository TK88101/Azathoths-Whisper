import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 Q3b：LyricsFlowModel 把狀態機、Queue.dat／History.dat、卡片詳情、無詞標記、升回計時串起來。
// 依賴全部是真的（ConfigStore＋臨時 defaults、QueueFileSource＋臨時目錄、CoverFlowViewModel），
// 只有 Music（MockMusicClient，供卡片詳情）與時鐘（GatedPollClock）是替身。
@MainActor
@Suite("LyricsFlowModel", .serialized)
struct LyricsFlowModelTests {
    private typealias Item = QueueFixtures.Item

    @MainActor
    final class Recorder {
        var forceRefreshes = 0
        var cancelledAutoFetches: [String] = []
        var surfaces: [LyricsSurface] = []
        var notConfirmed: [String] = []
        var musicRunning = true
    }

    private struct Harness {
        let model: LyricsFlowModel
        let coverFlow: CoverFlowViewModel
        let store: ConfigStore
        let music: MockMusicClient
        let clock: GatedPollClock
        let recorder: Recorder
        let directory: URL
        let suiteName: String

        func writeQueue(_ items: [Item]) throws {
            try QueueFixtures.queue(list: items).write(
                to: directory.appendingPathComponent(QueueFileSource.queueFileName), options: .atomic
            )
        }

        func writeHistory(_ ids: [Int64]) throws {
            try QueueFixtures.history(ids).write(
                to: directory.appendingPathComponent(QueueFileSource.historyFileName), options: .atomic
            )
        }

        func tearDown() {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeHarness() throws -> Harness {
        let suiteName = "LyricsFlowModelTests-\(UUID().uuidString)"
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LyricsFlowModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let music = MockMusicClient()
        let clock = GatedPollClock()
        let recorder = Recorder()
        let coverFlow = CoverFlowViewModel(artwork: StubArtworkProvider())
        let model = LyricsFlowModel(
            configStore: store,
            detailsReader: CardDetailsReader(music: music),
            queueSource: QueueFileSource(directory: directory),
            clock: clock,
            coverFlow: coverFlow,
            isMusicRunning: { recorder.musicRunning },
            forceRefresh: { recorder.forceRefreshes += 1 },
            cancelAutoFetch: { recorder.cancelledAutoFetches.append($0) }
        )
        model.onSurfaceChanged = { recorder.surfaces.append($0) }
        model.onWriteNotConfirmed = { recorder.notConfirmed.append($0) }
        return Harness(model: model, coverFlow: coverFlow, store: store, music: music, clock: clock,
                       recorder: recorder, directory: directory, suiteName: suiteName)
    }

    private func track(_ n: Int64) -> TrackInfo {
        TrackInfo.fixture(id: QueueFixtures.pid(n), title: "Song \(n)")
    }

    private func play(_ harness: Harness, _ n: Int64, lyrics: String?) async {
        harness.model.handle(.trackChanged(track(n), existingLyrics: lyrics))
        await harness.model.settleForTesting()
    }

    // MARK: AC1／AC2／AC7

    @Test func trackWithLyricsShowsCoverFlowCentredOnIt() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "words")

        #expect(h.model.surface == .coverFlow)
        #expect(h.coverFlow.cards.last?.side == .current)
        #expect(h.coverFlow.centerID == h.coverFlow.cards.last?.id)
    }

    @Test func missingTrackShowsTheEditor() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "")
        #expect(h.model.surface == .editor)
        #expect(h.recorder.surfaces == [.editor])
    }

    @Test func unreadableLyricsKeepCoverFlow() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: nil)
        #expect(h.model.surface == .coverFlow)
        #expect(h.model.status == .unknown)
    }

    /// AC6：同曲重發不動畫面
    @Test func sameTrackRefreshKeepsTheUsersEditor() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "words")
        h.model.tapPlayingCard(isCentered: true)
        await play(h, 1, lyrics: "words")
        #expect(h.model.surface == .editor)
    }

    // MARK: AC4 寫入與升回

    @Test func successfulWriteRisesAfterTheConfettiDelay() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "")

        h.model.saved(persistentID: QueueFixtures.pid(1), text: "new words")
        await h.clock.waitUntilPending(1)
        #expect(h.model.surface == .editor, "彩帶撒完才升回")
        #expect(await h.clock.requested.last == LyricsFlowModel.riseDelay)
        #expect(h.recorder.forceRefreshes == 1, "寫入後補讀一次當前曲")

        await h.clock.releaseAll()
        await waitUntil { h.model.surface == .coverFlow }
        #expect(h.model.surface == .coverFlow)
    }

    @Test func realChangeDuringTheDelayCancelsTheRise() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "")
        h.model.saved(persistentID: QueueFixtures.pid(1), text: "new words")
        await h.clock.waitUntilPending(1)

        await play(h, 2, lyrics: "")
        await waitFor { await h.clock.pendingCount == 0 }
        #expect(await h.clock.pendingCount == 0, "計時已取消")
        #expect(h.model.surface == .editor, "新曲缺詞，照新曲的規則")
    }

    /// 使用者拍板①＋Codex P0：讀回仍缺詞 → 計時真的被取消（不只是狀態），到期也不升回，並回報寫入沒生效
    @Test func readBackMissingAfterAWriteStaysInTheEditor() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "")
        h.model.saved(persistentID: QueueFixtures.pid(1), text: "new words")
        await h.clock.waitUntilPending(1)

        await play(h, 1, lyrics: "")
        await waitFor { await h.clock.pendingCount == 0 }
        #expect(await h.clock.pendingCount == 0, "計時已取消")
        await h.clock.releaseAll()
        await settle()
        #expect(h.model.surface == .editor)
        #expect(h.model.status == .missing)
        #expect(h.recorder.notConfirmed == [QueueFixtures.pid(1)])
    }

    @Test func emptyWriteDoesNotRise() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "")
        h.model.saved(persistentID: QueueFixtures.pid(1), text: "   ")
        await settle()
        #expect(await h.clock.pendingCount == 0)
        #expect(h.model.surface == .editor)
    }

    // MARK: AC5 無詞標記

    @Test func markingNoLyricsPersistsRaisesAndCancelsAutoFetch() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "")
        h.model.markNoLyrics(persistentID: QueueFixtures.pid(1))

        #expect(h.store.noLyricsMarks == [QueueFixtures.pid(1)])
        #expect(h.model.surface == .coverFlow)
        #expect(h.recorder.cancelledAutoFetches == [QueueFixtures.pid(1)])
        #expect(h.coverFlow.marks.contains(QueueFixtures.pid(1)))
    }

    @Test func aMarkedTrackShowsCoverFlowNextTime() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        h.store.markNoLyrics(QueueFixtures.pid(1))
        await play(h, 1, lyrics: "")
        #expect(h.model.surface == .coverFlow)
        #expect(h.model.status == .markedNone)
    }

    @Test func successfulWriteClearsTheMark() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        h.store.markNoLyrics(QueueFixtures.pid(1))
        await play(h, 1, lyrics: "")
        h.model.saved(persistentID: QueueFixtures.pid(1), text: "found them after all")
        #expect(h.store.noLyricsMarks.isEmpty)
    }

    /// Codex 修正版 B3：有詞或讀不到的歌不記標記（否則日後詞被清空時會潛伏生效）
    @Test func onlyAMissingCurrentTrackCanBeMarked() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "words")
        h.model.tapPlayingCard(isCentered: true)
        h.model.markNoLyrics(persistentID: QueueFixtures.pid(1))
        #expect(h.store.noLyricsMarks.isEmpty)
        #expect(h.model.surface == .editor)

        await play(h, 2, lyrics: nil)
        h.model.markNoLyrics(persistentID: QueueFixtures.pid(2))
        #expect(h.store.noLyricsMarks.isEmpty, "讀不到不等於沒有")
    }

    @Test func emptyPersistentIDCannotBeMarked() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        h.model.markNoLyrics(persistentID: "")
        #expect(h.store.noLyricsMarks.isEmpty)
        #expect(h.recorder.cancelledAutoFetches.isEmpty)
    }

    // MARK: AC8／AC8e 牌組來源

    @Test func queueFileGivesTheUpcomingCards() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)])
        await play(h, 1, lyrics: "words")

        #expect(h.coverFlow.cards.map(\.side) == [.current, .upcoming, .upcoming])
        #expect(h.coverFlow.centerID == "q:0:10")
        #expect(h.model.upcoming == .available)
    }

    @Test func historyFileGivesThePlayedCards() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        try h.writeHistory([7, 8])
        try h.writeQueue([Item(1, itemID: 10)])
        await play(h, 1, lyrics: "words")

        #expect(h.coverFlow.cards.map(\.persistentID) == [QueueFixtures.pid(7), QueueFixtures.pid(8), QueueFixtures.pid(1)])
    }

    /// 兩個檔都沒有：左＝本 app 觀察到的歷史，右＝空並標明讀不到
    @Test func withoutFilesTheLeftSideIsTheObservedHistory() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "words")
        await play(h, 2, lyrics: "words")

        #expect(h.coverFlow.cards.map(\.persistentID) == [QueueFixtures.pid(1), QueueFixtures.pid(2)])
        #expect(h.coverFlow.cards.map(\.side) == [.played, .current])
        #expect(h.model.upcoming == .unavailable)
    }

    /// 換歌（檔案不重寫）：中心移到清單下一首
    @Test func advancingWithinTheSameQueueMovesTheCentre() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)])
        await play(h, 1, lyrics: "words")
        await play(h, 2, lyrics: "words")
        #expect(h.coverFlow.centerID == "q:0:11")
    }

    /// D15：Music 未執行 → 佇列 session 失效
    @Test func musicNotRunningInvalidatesTheQueue() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11)])
        await play(h, 1, lyrics: "words")

        h.recorder.musicRunning = false
        await h.model.refreshSources()
        #expect(!h.coverFlow.cards.contains { $0.side == .upcoming })
    }

    /// §1／AC8b（simcodex R1 採納 Codex）：Queue.dat 消失 → 右側退回（空＋讀不到），不沿用舊清單；
    /// 檔案回來（即使內容與屬性和先前相同）→ 恢復
    @Test func queueFileDisappearingFallsBackInsteadOfShowingAStaleQueue() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        let items = [Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)]
        try h.writeQueue(items)
        await play(h, 1, lyrics: "words")
        #expect(h.model.upcoming == .available)

        let queueFile = h.directory.appendingPathComponent(QueueFileSource.queueFileName)
        let attributes = try FileManager.default.attributesOfItem(atPath: queueFile.path)
        try FileManager.default.removeItem(at: queueFile)
        await h.model.refreshSources()
        #expect(!h.coverFlow.cards.contains { $0.side == .upcoming })
        #expect(h.model.upcoming == .unavailable)

        try h.writeQueue(items)
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: queueFile.path)
        await h.model.refreshSources()
        #expect(h.model.upcoming == .available)
        #expect(h.coverFlow.cards.map(\.side) == [.current, .upcoming, .upcoming])
    }

    // MARK: AC8d 卡片詳情

    /// AC8d：詳情批次最新者勝——較早發出的一批晚回來不得套用（世代號）。
    /// 還有卡缺詳情時，每次發布牌組都會發新的一批；不用 `play`（它的 settle 會等被閘門擋住的批次）
    @Test func anOlderDetailsBatchArrivingLateIsDropped() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        let first = LyricsGate(), second = LyricsGate()
        await h.music.setTrackDetailsGateQueue([first, second])
        func details(_ title: String) -> TrackDetails {
            TrackDetails(persistentID: QueueFixtures.pid(2), artist: "B", title: title, album: "L",
                         discNumber: 1, trackNumber: 2, lyrics: "")
        }
        await h.music.setTrackDetails([details("Old")])
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11)])
        h.model.handle(.trackChanged(track(1), existingLyrics: "words"))
        await waitFor { await h.music.trackDetailsRequests.count == 1 }

        await h.music.setTrackDetails([details("New")])
        await h.model.refreshSources()
        await waitFor { await h.music.trackDetailsRequests.count == 2 }

        await second.open()
        await waitUntil { h.coverFlow.details[QueueFixtures.pid(2)]?.title == "New" }
        await first.open()
        // 舊批次的任務不在 settleForTesting 的追蹤內：等它真的回來、再讓它有機會套用
        await waitFor { await h.music.trackDetailsCompleted == 2 }
        await settle(300)
        #expect(h.coverFlow.details[QueueFixtures.pid(2)]?.title == "New", "較早的一批晚回來不得覆蓋")
    }

    @Test func detailsAreFetchedForTheDeck() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await h.music.setTrackDetails([
            TrackDetails(persistentID: QueueFixtures.pid(2), artist: "B", title: "Two", album: "L", discNumber: 1, trackNumber: 2, lyrics: ""),
        ])
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11)])
        await play(h, 1, lyrics: "words")

        #expect(h.coverFlow.details[QueueFixtures.pid(2)]?.title == "Two")
        #expect(h.coverFlow.status(for: h.coverFlow.cards[1]) == .missing)
        #expect(h.coverFlow.details[QueueFixtures.pid(1)]?.lyrics == "words", "當前曲的詳情直接取自事件")
    }

    // MARK: Batch 寫入（2026-09-25 回報：匯入成功後徽章不刷新）

    private func details(_ n: Int64, lyrics: String) -> TrackDetails {
        TrackDetails(persistentID: QueueFixtures.pid(n), artist: "B", title: "Song \(n)", album: "L",
                     discNumber: 1, trackNumber: Int(n), lyrics: lyrics)
    }

    /// 正在播 1（有詞），右側是缺詞的 2
    private func playingOneWithMissingTwo(_ h: Harness) async throws -> DeckCard {
        await h.music.setTrackDetails([details(2, lyrics: "")])
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11)])
        await play(h, 1, lyrics: "words")
        let card = try #require(h.coverFlow.cards.first { $0.persistentID == QueueFixtures.pid(2) })
        return card
    }

    /// AC1／AC6：非當前曲——卡片立即 ✓；不補讀、不動畫面、不排升回、不重讀詳情
    @Test func batchWriteOfAnotherTrackRefreshesItsCardOnly() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        let card = try await playingOneWithMissingTwo(h)
        #expect(h.coverFlow.status(for: card) == .missing)
        let surfaceReports = h.recorder.surfaces.count
        let detailRequests = await h.music.trackDetailsRequests.count

        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "batch words")
        await h.model.settleForTesting()

        #expect(h.coverFlow.status(for: card) == .present)
        #expect(h.recorder.forceRefreshes == 0, "Batch 期間 monitor 不 busy，非當前曲不補讀")
        #expect(h.recorder.surfaces.count == surfaceReports, "非當前曲不經狀態機")
        #expect(h.model.surface == .coverFlow)
        #expect(h.model.status == .present, "當前曲狀態不受影響")
        #expect(await h.clock.pendingCount == 0)
        #expect(await h.music.trackDetailsRequests.count == detailRequests, "就地更新，不重讀 Music")
    }

    /// AC4：寫到當前缺詞曲——與 Editor 寫入同一條路：彩帶撒完升回、補讀一次
    @Test func batchWriteOfTheMissingCurrentTrackRisesLikeAnEditorWrite() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "")
        #expect(h.model.surface == .editor)

        h.model.batchSaved(persistentID: QueueFixtures.pid(1), text: "batch words")
        await h.clock.waitUntilPending(1)
        #expect(h.model.surface == .editor, "彩帶撒完才升回")
        #expect(h.model.status == .present)
        #expect(h.recorder.forceRefreshes == 1, "當前曲補讀確認寫入生效")

        await h.clock.releaseAll()
        await waitUntil { h.model.surface == .coverFlow }
        #expect(h.model.surface == .coverFlow)
    }

    /// AC5：已標記「沒有歌詞」的非當前曲被寫入非空歌詞 → 標記清除、徽章 ✓
    @Test func batchWriteClearsTheNoLyricsMarkOfAnotherTrack() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        h.store.markNoLyrics(QueueFixtures.pid(2))
        let card = try await playingOneWithMissingTwo(h)
        #expect(h.coverFlow.status(for: card) == .markedNone)

        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "found them after all")

        #expect(h.store.noLyricsMarks.isEmpty)
        #expect(!h.coverFlow.marks.contains(QueueFixtures.pid(2)))
        #expect(h.coverFlow.status(for: card) == .present)
    }

    /// Import Selected 可能寫入空的預覽框：卡片照實顯示缺詞
    @Test func batchWriteOfEmptyTextShowsTheCardAsMissing() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await h.music.setTrackDetails([details(2, lyrics: "old words")])
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11)])
        await play(h, 1, lyrics: "words")
        let card = try #require(h.coverFlow.cards.first { $0.persistentID == QueueFixtures.pid(2) })

        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "   ")

        #expect(h.coverFlow.status(for: card) == .missing)
        #expect(h.recorder.forceRefreshes == 0)
    }

    /// 計劃 §9.3 AC11（F4）：空文字寫入不清「沒有歌詞」標記——AC5 只在非空寫入時清
    @Test func batchWriteOfEmptyTextKeepsTheNoLyricsMark() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        h.store.markNoLyrics(QueueFixtures.pid(2))
        let card = try await playingOneWithMissingTwo(h)

        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "   ")

        #expect(h.store.noLyricsMarks == [QueueFixtures.pid(2)])
        #expect(h.coverFlow.marks.contains(QueueFixtures.pid(2)))
        #expect(h.coverFlow.status(for: card) == .markedNone)
    }

    /// 計劃 T3b（回歸防線）：詳情讀取在飛時 Batch 寫入 → 放行後該卡不得顯示寫入前的舊歌詞。
    /// 不用 `play`（它的 settle 會等被閘門擋住的批次）
    @Test func detailsInFlightDuringABatchWriteNeverShowTheOldLyrics() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        let gate = LyricsGate()
        await h.music.setTrackDetailsGateQueue([gate])
        await h.music.setTrackDetails([details(2, lyrics: "")])
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11)])
        h.model.handle(.trackChanged(track(1), existingLyrics: "words"))
        await waitFor { await h.music.trackDetailsRequests.count == 1 }

        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "batch words")
        await settle(300)       // 讓排進工作鏈的快取更新先落地
        await h.music.setTrackDetails([details(2, lyrics: "batch words")])     // 之後的 Music 讀取讀得到寫入
        await gate.open()
        await waitFor { await h.music.trackDetailsCompleted == 1 }
        await settle(300)

        let card = try #require(h.coverFlow.cards.first { $0.persistentID == QueueFixtures.pid(2) })
        #expect(h.coverFlow.status(for: card) != .missing, "在飛的舊讀取不得蓋掉寫入")

        await h.model.refreshSources()
        await h.model.settleForTesting()
        #expect(h.coverFlow.status(for: card) == .present, "下一輪輪詢補上")
    }

    // MARK: 計劃 §9.1（F1）：寫入確認（ack）收口

    /// 種下 reader 快取（2＝缺詞）後把 2 移出牌組：`coverFlow.details` 濾掉 2，reader 快取仍留著舊值
    private func cachedMissingTwoOutOfTheDeck(_ h: Harness) async throws {
        await h.music.setTrackDetails([details(2, lyrics: ""), details(3, lyrics: "three")])
        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11)])
        await play(h, 1, lyrics: "words")
        try h.writeQueue([Item(1, itemID: 10), Item(3, itemID: 12)])
        await h.model.refreshSources()
        await h.model.settleForTesting()
        #expect(h.coverFlow.details[QueueFixtures.pid(2)] == nil)
    }

    /// AC10 原時序（評審 F1 重現）：工作鏈上 readSources 未跑完時寫入 2，readSources 把 2 帶回牌組 →
    /// 詳情讀取命中 reader 的舊快取。回牌組後不得是舊值，下一輪輪詢後必 ✓
    @Test func aCardReturningToTheDeckRightAfterABatchWriteIsNotStale() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        try await cachedMissingTwoOutOfTheDeck(h)

        try h.writeQueue([Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)])
        h.model.handle(.trackChanged(track(1), existingLyrics: "words"))    // 讀檔排上工作鏈、尚未執行
        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "batch words")
        await h.model.settleForTesting()

        let card = try #require(h.coverFlow.cards.first { $0.persistentID == QueueFixtures.pid(2) })
        #expect(h.coverFlow.status(for: card) != .missing, "回牌組後不得是寫入前的舊值")
        await h.model.refreshSources()
        await h.model.settleForTesting()
        #expect(h.coverFlow.status(for: card) == .present)
    }

    /// §9.1 三分法之一：ack 前已套上的舊詳情，ack 時被重套為寫入的歌詞
    @Test func staleDetailsAppliedBeforeTheAckAreCorrectedByIt() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        let card = try await playingOneWithMissingTwo(h)

        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "batch words")
        h.coverFlow.updateDetails([QueueFixtures.pid(2): details(2, lyrics: "")])    // 模擬 ack 前落地的舊讀取
        await h.model.settleForTesting()

        #expect(h.coverFlow.status(for: card) == .present)
        #expect(h.coverFlow.details[QueueFixtures.pid(2)]?.lyrics == "batch words")
    }

    /// 同首連寫兩次：只認最後一筆
    @Test func theLastOfTwoWritesToTheSameTrackWins() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        _ = try await playingOneWithMissingTwo(h)

        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "first")
        h.model.batchSaved(persistentID: QueueFixtures.pid(2), text: "second")
        await h.model.settleForTesting()

        #expect(h.coverFlow.details[QueueFixtures.pid(2)]?.lyrics == "second")
    }

    // MARK: 計劃 §9.2（F2）：當前曲有詞→有詞不經狀態機

    /// AC9：當前曲已有詞、使用者手動降下 Editor → Batch 寫入（同文或不同文字）後畫面不動、無升回；恰讀回一次
    @Test("有詞→有詞不升回", arguments: ["words", "different words"])
    func batchRewriteOfThePresentCurrentTrackKeepsTheUsersSurface(text: String) async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "words")
        h.model.toggleHandle()
        #expect(h.model.surface == .editor)
        let surfaceReports = h.recorder.surfaces.count

        h.model.batchSaved(persistentID: QueueFixtures.pid(1), text: text)
        await h.model.settleForTesting()

        #expect(h.model.surface == .editor, "畫面是使用者的選擇")
        #expect(await h.clock.pendingCount == 0, "不排升回")
        #expect(h.recorder.surfaces.count == surfaceReports, "不經狀態機")
        #expect(h.recorder.forceRefreshes == 1, "讀回一次，讓當前曲收斂到 Music 的真值")
        #expect(h.coverFlow.details[QueueFixtures.pid(1)]?.lyrics == text)
    }

    /// 有詞→空文字仍走 `saved()`：狀態跟著變成缺詞，與卡片一致
    @Test func batchWriteOfEmptyTextToThePresentCurrentTrackGoesThroughTheStateMachine() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1, lyrics: "words")

        h.model.batchSaved(persistentID: QueueFixtures.pid(1), text: "  ")

        #expect(h.model.status == .missing)
        #expect(h.recorder.forceRefreshes == 1)
    }
}
