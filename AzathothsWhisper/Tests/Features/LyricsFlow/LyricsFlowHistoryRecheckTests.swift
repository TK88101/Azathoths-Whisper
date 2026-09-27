import Foundation
import Testing

@testable import AzathothsWhisper

// F2（計劃 2026-09-27-coverflow-f1-f2 §3.3、§4 15–21）：換歌後對 History.dat 的有界短重讀。
// 依賴全部是真的（QueueFileSource＋臨時目錄、CoverFlowViewModel），Music 與時鐘是替身
@MainActor
@Suite("LyricsFlowModel history recheck", .serialized)
struct LyricsFlowHistoryRecheckTests {
    private typealias Item = QueueFixtures.Item
    private static let fullHistory: [Int64] = Array(101...110)

    @MainActor
    private struct Harness {
        let model: LyricsFlowModel
        let coverFlow: CoverFlowViewModel
        let music: MockMusicClient
        let recheckClock: any PollClock
        let directory: URL
        let suiteName: String

        func writeHistory(_ ids: [Int64]) throws {
            try QueueFixtures.history(ids).write(to: historyURL, options: .atomic)
        }

        var historyURL: URL { directory.appendingPathComponent(QueueFileSource.historyFileName) }

        /// 左側（播過）的 persistentID，由舊到新
        var played: [String] { coverFlow.deck.cards.filter { $0.side == .played }.map(\.persistentID) }

        func tearDown() {
            model.stopPolling()
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeHarness(recheckClock: any PollClock = GatedPollClock(), slides: Bool = false) throws -> Harness {
        let suiteName = "LyricsFlowHistoryRecheckTests-\(UUID().uuidString)"
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsFlowHistoryRecheckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let music = MockMusicClient()
        let coverFlow = CoverFlowViewModel(artwork: StubArtworkProvider(), clock: GatedPollClock())
        coverFlow.setPrefersReducedMotion(!slides)
        let model = LyricsFlowModel(
            configStore: store,
            detailsReader: CardDetailsReader(music: music),
            queueSource: QueueFileSource(directory: directory),
            clock: GatedPollClock(),
            historyRecheckClock: recheckClock,
            coverFlow: coverFlow,
            isMusicRunning: { true },
            forceRefresh: {},
            cancelAutoFetch: { _ in }
        )
        let harness = Harness(model: model, coverFlow: coverFlow, music: music, recheckClock: recheckClock,
                              directory: directory, suiteName: suiteName)
        try QueueFixtures.queue(list: [Item(1, itemID: 10), Item(2, itemID: 11), Item(3, itemID: 12)])
            .write(to: directory.appendingPathComponent(QueueFileSource.queueFileName), options: .atomic)
        try harness.writeHistory(Self.fullHistory)
        return harness
    }

    private func play(_ h: Harness, _ n: Int64) async {
        h.model.handle(.trackChanged(TrackInfo.fixture(id: QueueFixtures.pid(n), title: "Song \(n)"), existingLyrics: "words"))
        await h.model.settleForTesting()
    }

    private func gated(_ h: Harness) -> GatedPollClock { h.recheckClock as! GatedPollClock }

    /// 放行下一個重讀時點，等它讀完（讀檔走工作鏈）
    private func releaseNextRecheck(_ h: Harness) async {
        await gated(h).waitUntilPending(1)
        await gated(h).releaseNext()
        await settle(200)
        await h.model.settleForTesting()
    }

    private func pid(_ n: Int64) -> String { QueueFixtures.pid(n) }

    @Test func historyWrittenAfterTheChangeIsPickedUpByTheRecheck() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        await play(h, 2)
        #expect(h.played.last == pid(110), "換歌當下 Music 還沒寫履歴")

        try h.writeHistory(Array(Self.fullHistory.dropFirst()) + [1])
        await releaseNextRecheck(h)

        #expect(h.played.last == pid(1), "剛播完的那首在短重讀時出現在左鄰")
    }

    @Test func recheckStopsOnceTheFinishedTrackAppears() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        await play(h, 2)

        try h.writeHistory(Array(Self.fullHistory.dropFirst()) + [1])
        await releaseNextRecheck(h)

        #expect(await gated(h).requested.count == 1, "追上就停，不再排下一個時點")
        #expect(await gated(h).pendingCount == 0)
    }

    @Test func recheckSleepsTheGapsBetweenOffsetsAndGivesUp() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        await play(h, 2)

        for _ in LyricsFlowModel.historyRecheckOffsets { await releaseNextRecheck(h) }

        let requested = await gated(h).requested
        #expect(requested == [.milliseconds(5200), .milliseconds(800), .seconds(1)], "sleep 的是相鄰時點的差")
        #expect(await gated(h).pendingCount == 0, "跑滿時點表就放棄")
        #expect(h.played.last == pid(110), "沒播完的歌 Music 不記，左鄰維持履歴的真相")
    }

    /// 使用者 2026-09-27 拍板（計劃 §9 乙）：實測 Music 在換歌後 4.86–5.05 秒才寫履歴，
    /// 第一點要晚於實測最大值，末點是放棄的上限
    @Test func recheckOffsetsCoverTheMeasuredWriteDelay() {
        let offsets = LyricsFlowModel.historyRecheckOffsets
        #expect(offsets == [.milliseconds(5200), .seconds(6), .seconds(7)])
        #expect(offsets.first! > .milliseconds(5050), "第一點晚於實測最大延遲")
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 < $1 }, "遞增")
    }

    @Test func alreadyCaughtUpAtTheChangeDoesNotRecheck() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        try h.writeHistory(Array(Self.fullHistory.dropFirst()) + [1])
        await play(h, 2)
        await settle(200)

        #expect(h.played.last == pid(1))
        #expect(await gated(h).requested.isEmpty, "換歌當下的讀檔已追上，不排重讀")
    }

    @Test func aPollThatCatchesUpStopsTheRecheck() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        await play(h, 2)
        await gated(h).waitUntilPending(1)

        try h.writeHistory(Array(Self.fullHistory.dropFirst()) + [1])
        await h.model.refreshSources()
        await releaseNextRecheck(h)

        #expect(await gated(h).requested.count == 1, "輪詢先追上 → 醒來看到已追上就停")
        #expect(await gated(h).pendingCount == 0)
    }

    @Test func aNewChangeRestartsTheRecheck() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        await play(h, 2)
        await gated(h).waitUntilPending(1)

        await play(h, 3)
        await gated(h).waitUntilPending(1)
        try h.writeHistory(Array(Self.fullHistory.dropFirst(2)) + [1, 2])
        await releaseNextRecheck(h)

        #expect(h.played.suffix(2) == [pid(1), pid(2)])
        #expect(await gated(h).pendingCount == 0, "新的 expected（2）追上就停；舊的追趕已取消")
    }

    @Test func aStaleRecheckThatAlreadyWokeCannotPublish() async throws {
        let clock = UncancellableGateClock()
        let h = try makeHarness(recheckClock: clock)
        defer { h.tearDown() }
        await play(h, 1)
        await play(h, 2)
        await clock.waitUntilPending(1)
        await play(h, 3)
        await clock.waitUntilPending(2)

        try h.writeHistory(Array(Self.fullHistory.dropFirst()) + [1])
        await clock.releaseFirst()           // 舊世代的追趕：取消了卻照樣醒來
        await settle(200)
        await h.model.settleForTesting()

        #expect(h.played.last == pid(110), "舊世代醒來也不得讀檔、不得 publish")
    }

    @Test func anUnchangedOrIdenticalRecheckDoesNotFetchDetails() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await h.music.setTrackDetailsOutcome(.failure(.scriptingFailure("details")))
        await play(h, 1)
        await play(h, 2)
        await settle(200)
        let before = await h.music.trackDetailsRequests.count

        await releaseNextRecheck(h)                                  // .unchanged
        try h.writeHistory(Self.fullHistory)                         // 內容相同、屬性變
        await releaseNextRecheck(h)
        await releaseNextRecheck(h)

        #expect(await h.music.trackDetailsRequests.count == before, "履歴沒變就不 publish，不多問 Music")
    }

    @Test func recheckFollowsTheSameHistoryTransitions() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        await play(h, 2)

        try Data("not a plist".utf8).write(to: h.historyURL)
        await releaseNextRecheck(h)
        #expect(h.played.last == pid(110), ".failed 保留最後一份有效的履歴")

        try FileManager.default.removeItem(at: h.historyURL)
        await releaseNextRecheck(h)
        #expect(h.played == [pid(1)], ".missing 退回本 app 觀察到的歷史（與 readSources 同）")
    }

    @Test func noRecheckAfterStopPolling() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        h.model.stopPolling()

        await play(h, 2)
        await settle(200)

        #expect(await gated(h).requested.isEmpty)
    }

    /// F3（使用者 2026-09-27 裁定甲）：往回跳不改 History.dat，左側照履歴逐列顯示——
    /// 往回跳到剛播完的那首時，它在左鄰（先前播完的那次）與正中（正在播）各一張，
    /// 與 Music「次に再生」面板的履歴＋迷你播放器一致（計劃 2026-09-27-coverflow-f3 E1–E8）
    @Test func skippingBackKeepsTheHistoryRowOfTheSameSong() async throws {
        let h = try makeHarness()
        defer { h.tearDown() }
        await play(h, 1)
        try h.writeHistory(Array(Self.fullHistory.dropFirst()) + [1])
        await play(h, 2)

        await play(h, 1)

        #expect(h.played.last == pid(1), "履歴最後一列是先前播完的那次，不藏")
        let current = try #require(h.coverFlow.deck.cards.first { $0.side == .current })
        #expect(current.persistentID == pid(1))
    }

    @Test func historyCatchingUpDuringTheSlideKeepsItGoing() async throws {
        let h = try makeHarness(slides: true)
        defer { h.tearDown() }
        await play(h, 1)
        let current = try #require(h.coverFlow.deck.currentCardID)
        h.coverFlow.playingCardCentering(cardID: current, isCentered: true)
        await play(h, 2)
        #expect(h.coverFlow.slide == CoverFlowSlideRequest(generation: 1, slots: 1))

        try h.writeHistory(Array(Self.fullHistory.dropFirst()) + [1])
        await releaseNextRecheck(h)

        #expect(h.played.last == pid(1))
        #expect(h.coverFlow.slide == CoverFlowSlideRequest(generation: 1, slots: 1), "平移中追上不打斷平移")
        #expect(h.coverFlow.cards.contains { $0.id == "q:0:10" }, "暫留卡原位取代同一首的履歴卡")
    }
}

/// 不理會取消的時鐘：模擬「已取消，但 sleep 仍照常返回」的 task（R1-3）
private actor UncancellableGateClock: PollClock {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for interval: Duration) async throws {
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilPending(_ count: Int) async {
        for _ in 0..<20_000 where waiters.count < count { await Task.yield() }
    }

    func releaseFirst() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}
