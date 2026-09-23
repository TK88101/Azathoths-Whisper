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

    // MARK: AC8d 卡片詳情

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
}
