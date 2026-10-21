import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.5：退路鏈與停止規則、失敗不存 notFound、加入同一份工作、新詞取消舊工作、搶占、時限、佇列上限、停用開關、關閉。
// 來源一律是替身；歌詞為編造句
@Suite("TimingResolver")
struct TimingResolverTests {
    static let id = "0123456789ABCDEF"
    static let lyrics = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn"
    static let otherLyrics = "Engines in the night\nNeon on the road\nRunning out of time\nStatic on the radio"
    static let query = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200)
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let matched = MatchedTrack(artist: "Some Band", title: "Lantern Song", duration: 200)
    static let aligned = ProviderOutcome.timed(
        [LRCLine(start: 10, text: "Lanterns over the river"), LRCLine(start: 14, text: "Ash in the wind"),
         LRCLine(start: 20, text: "Count the silent bells"), LRCLine(start: 24, text: "Paper boats at dawn")], matched: matched
    )
    static let otherAligned = ProviderOutcome.timed(
        [LRCLine(start: 30, text: "Engines in the night"), LRCLine(start: 34, text: "Neon on the road"),
         LRCLine(start: 40, text: "Running out of time"), LRCLine(start: 44, text: "Static on the radio")], matched: matched
    )
    static let unaligned = ProviderOutcome.timed(
        [LRCLine(start: 10, text: "Something else entirely"), LRCLine(start: 14, text: "Nothing like it"), LRCLine(start: 20, text: "Another line")], matched: matched
    )

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-resolver-\(UUID().uuidString)")
    }

    private func resolver(
        _ providers: [FakeTimingProvider], store: TimingStore? = nil, metadata: TimingQuery? = TimingResolverTests.query,
        switches: TimingSwitches = .allEnabled, deadline: any PollClock = NeverSleeper(), queueLimit: Int = TimingResolver.defaultQueueLimit,
        clock: FakeTimingClock = FakeTimingClock(), diagnostics: any TimingDiagnostics = NoopTimingDiagnostics()
    ) -> (TimingResolver, TimingStore) {
        let store = store ?? TimingStore(directory: directory())
        let resolver = TimingResolver(
            providers: providers, store: store, metadata: { _ in metadata }, switches: switches,
            deadlineSleeper: deadline, clock: clock, now: { Self.now }, queueLimit: queueLimit, diagnostics: diagnostics
        )
        return (resolver, store)
    }

    private func request(_ lyrics: String = Self.lyrics, query: TimingQuery? = nil) -> TimingRequest {
        TimingRequest(persistentID: Self.id, lyrics: lyrics, query: query)
    }

    // MARK: 退路鏈

    @Test func theFirstAnsweringSourceStopsTheChain() async throws {
        let first = FakeTimingProvider(.lrclib, [.outcome(.noTiming(.notFound))])
        let second = FakeTimingProvider(.youtubeMusic, [.outcome(Self.aligned)])
        let third = FakeTimingProvider(.deezer, [])
        let (resolver, store) = resolver([first, second, third])
        let result = await resolver.resolve(request(), priority: .background)
        #expect(result.outcome == .found(.youtubeMusic, [.init(index: 0, start: 10), .init(index: 1, start: 14), .init(index: 2, start: 20), .init(index: 3, start: 24)]))
        #expect(await third.callCount == 0)
        #expect(await store.load(persistentID: Self.id)?.outcome == .found(source: .youtubeMusic, lines: [.init(index: 0, start: 10), .init(index: 1, start: 14), .init(index: 2, start: 20), .init(index: 3, start: 24)]))
    }

    @Test func aTimelineThatDoesNotAlignFallsThroughToTheNextSource() async {
        let first = FakeTimingProvider(.lrclib, [.outcome(Self.unaligned)])
        let second = FakeTimingProvider(.netease, [.outcome(Self.aligned)])
        let (resolver, _) = resolver([first, second])
        guard case .found(.netease, _) = await resolver.resolve(request(), priority: .background).outcome else {
            Issue.record("expected netease"); return
        }
    }

    @Test func everySourceSayingNoIsStoredAsNotFound() async {
        let (resolver, store) = resolver([FakeTimingProvider(.lrclib, []), FakeTimingProvider(.qq, [.outcome(.noTiming(.mismatch))])])
        #expect(await resolver.resolve(request(), priority: .background).outcome == .notFound)
        #expect(await store.load(persistentID: Self.id)?.outcome == .notFound)
    }

    /// 服務暫時掛掉不得換來 7 天的「沒有」
    @Test func aFailingSourceMeansUnavailableAndNothingIsStored() async {
        let (resolver, store) = resolver([FakeTimingProvider(.lrclib, [.failure(.server(status: 503))]), FakeTimingProvider(.qq, [])])
        #expect(await resolver.resolve(request(), priority: .background).outcome == .unavailable)
        #expect(await store.load(persistentID: Self.id) == nil)
    }

    @Test func afterAnUnavailableResultTheSongBacksOff() async {
        let provider = FakeTimingProvider(.lrclib, [.failure(.timedOut)])
        let (resolver, _) = resolver([provider])
        _ = await resolver.resolve(request(), priority: .background)
        #expect(await resolver.resolve(request(), priority: .background).outcome == .unavailable)
        #expect(await provider.callCount == 1)
    }

    @Test func missingMetadataSkipsTheNetwork() async {
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, store) = resolver([provider], metadata: TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 0))
        #expect(await resolver.resolve(request(), priority: .background).outcome == .skipped(.missingMetadata))
        #expect(await provider.callCount == 0)
        #expect(await store.load(persistentID: Self.id) == nil)
    }

    @Test func anAbsurdDurationSkipsTheNetwork() async {
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, _) = resolver([provider], metadata: TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 1e19))
        #expect(await resolver.resolve(request(), priority: .background).outcome == .skipped(.missingMetadata))
        #expect(await provider.callCount == 0)
    }

    /// 特效層一次只顯示一首：快速切歌時，別首還沒開始的 visible 工作降為背景（不取消：寫入後補查不得消失），
    /// 最新那首先跑
    @Test func aNewVisibleSongDemotesOlderWaitingVisibleSongs() async {
        let blocker = FakeTimingProvider(.lrclib, [.suspend(then: Self.aligned), .outcome(Self.aligned), .outcome(Self.otherAligned)])
        let (resolver, _) = resolver([blocker])
        let running = Task { await resolver.resolve(TimingRequest(persistentID: "AAAAAAAAAAAAAAAA", lyrics: Self.lyrics, query: nil), priority: .visible) }
        while await blocker.callCount == 0 { await Task.yield() }
        let stale = Task { await resolver.resolve(TimingRequest(persistentID: "BBBBBBBBBBBBBBBB", lyrics: Self.lyrics, query: nil), priority: .visible) }
        while await resolver.pendingCount < 1 { await Task.yield() }
        let latest = Task { await resolver.resolve(TimingRequest(persistentID: "CCCCCCCCCCCCCCCC", lyrics: Self.lyrics, query: nil), priority: .visible) }
        await blocker.release()
        _ = await running.value
        guard case .found = await latest.value.outcome else { Issue.record("latest should run first"); return }
        // 降級的那首稍後照樣跑完（拿到第三個腳本＝對不上詞的另一首 → 全部明確說沒有）
        #expect(await stale.value.outcome == .notFound)
        #expect(await blocker.callCount == 3)
    }

    @Test func knownMetadataIsUsedWithoutAskingMusic() async {
        let provider = FakeTimingProvider(.lrclib, [])
        let given = TimingQuery(artist: "Given", title: "Known", duration: 123)
        let (resolver, _) = resolver([provider], metadata: nil)
        _ = await resolver.resolve(request(query: given), priority: .visible)
        #expect(await provider.queries == [given])
    }

    // MARK: 候選排序（候選排序計劃 §3.3–§3.6）

    /// 對上 3／4 行、LRC 側全對上：通過但不完美
    static let partial = ProviderOutcome.timed(
        [LRCLine(start: 10, text: "Lanterns over the river"), LRCLine(start: 14, text: "Ash in the wind"),
         LRCLine(start: 20, text: "Count the silent bells")], matched: matched
    )
    /// 對上 3／4 行、LRC 側 3／4：通過，比 `partial` 差
    static let weaker = ProviderOutcome.timed(
        [LRCLine(start: 11, text: "Lanterns over the river"), LRCLine(start: 15, text: "Ash in the wind"),
         LRCLine(start: 21, text: "Count the silent bells"), LRCLine(start: 30, text: "Something else entirely")], matched: matched
    )
    static let partialLines: [TimingRecord.LineStart] = [.init(index: 0, start: 10), .init(index: 1, start: 14), .init(index: 2, start: 20)]
    static let alignedLines: [TimingRecord.LineStart] = [.init(index: 0, start: 10), .init(index: 1, start: 14), .init(index: 2, start: 20), .init(index: 3, start: 24)]

    static func candidate(_ id: String, duration: Double = 200) -> TimingCandidate {
        TimingCandidate(track: MatchedTrack(artist: "Some Band", title: "Lantern Song", duration: duration), id: id)
    }

    static let threeCandidates = [candidate("c0"), candidate("c1"), candidate("c2")]

    @Test func theBetterAlignedLaterCandidateIsStored() async {
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.outcome(Self.weaker)], "c1": [.outcome(Self.partial)], "c2": [.outcome(Self.unaligned)],
        ])
        let (resolver, store) = resolver([provider])
        #expect(await resolver.resolve(request(), priority: .background).outcome == .found(.lrclib, Self.partialLines))
        #expect(await provider.fetched == ["c0", "c1", "c2"])
        #expect(await store.load(persistentID: Self.id)?.outcome == .found(source: .lrclib, lines: Self.partialLines))
    }

    @Test func aPerfectFirstCandidateStopsFurtherFetches() async {
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: ["c0": [.outcome(Self.aligned)]])
        let (resolver, _) = resolver([provider])
        #expect(await resolver.resolve(request(), priority: .background).outcome == .found(.lrclib, Self.alignedLines))
        #expect(await provider.fetched == ["c0"])
    }

    @Test func onlyTheTopThreeCandidatesAreFetched() async {
        let four = Self.threeCandidates + [Self.candidate("c3")]
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(four)], timings: ["c3": [.outcome(Self.aligned)]])
        let (resolver, _) = resolver([provider])
        #expect(await resolver.resolve(request(), priority: .background).outcome == .notFound)
        #expect(await provider.fetched == ["c0", "c1", "c2"])
    }

    @Test func aFailingFirstCandidateFallsThroughToTheSecond() async {
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.failure(.transport)], "c1": [.outcome(Self.partial)],
        ])
        let (resolver, _) = resolver([provider])
        #expect(await resolver.resolve(request(), priority: .background).outcome == .found(.lrclib, Self.partialLines))
    }

    @Test func whenNoCandidateAlignsTheNextSourceIsAsked() async {
        let first = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.outcome(Self.unaligned)], "c1": [.outcome(.noTiming(.plainOnly))], "c2": [.outcome(Self.unaligned)],
        ])
        let second = FakeTimingProvider(.youtubeMusic, [.outcome(Self.aligned)])
        let (resolver, _) = resolver([first, second])
        #expect(await resolver.resolve(request(), priority: .background).outcome == .found(.youtubeMusic, Self.alignedLines))
        #expect(await first.fetched == ["c0", "c1", "c2"])
    }

    @Test func atExactlyTenSecondsTheNextCandidateIsStillFetched() async {
        let clock = FakeTimingClock()
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.advancing(10, .outcome(Self.unaligned))], "c1": [.outcome(Self.aligned)],
        ], clock: clock)
        let (resolver, _) = resolver([provider], clock: clock)
        #expect(await resolver.resolve(request(), priority: .background).outcome == .found(.lrclib, Self.alignedLines))
        #expect(await provider.fetched == ["c0", "c1"])
    }

    @Test func pastTenSecondsTheNextSourceIsAskedInstead() async {
        let clock = FakeTimingClock()
        let first = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.advancing(10.001, .outcome(Self.unaligned))], "c1": [.outcome(Self.partial)],
        ], clock: clock)
        let second = FakeTimingProvider(.youtubeMusic, [.outcome(Self.aligned)])
        let (resolver, _) = resolver([first, second], clock: clock)
        #expect(await resolver.resolve(request(), priority: .background).outcome == .found(.youtubeMusic, Self.alignedLines))
        #expect(await first.fetched == ["c0"])
        #expect(await second.callCount == 1)
    }

    @Test func atTheDeadlineAnAlreadyAcceptedCandidateIsStored() async {
        let deadline = GatedPollClock()
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.outcome(Self.partial)], "c1": [.suspend(then: Self.aligned)],
        ])
        let (resolver, store) = resolver([provider], deadline: deadline)
        let result = Task { await resolver.resolve(request(), priority: .visible) }
        while await provider.fetched.count < 2 { await Task.yield() }
        await deadline.waitUntilPending(1)
        await deadline.releaseAll()
        #expect(await result.value.outcome == .found(.lrclib, Self.partialLines))
        #expect(await store.load(persistentID: Self.id)?.outcome == .found(source: .lrclib, lines: Self.partialLines))
    }

    @Test func atTheDeadlineWithoutAnAcceptedCandidateNothingIsStored() async {
        let deadline = GatedPollClock()
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.outcome(Self.unaligned)], "c1": [.suspend(then: Self.aligned)],
        ])
        let (resolver, store) = resolver([provider], deadline: deadline)
        let result = Task { await resolver.resolve(request(), priority: .visible) }
        while await provider.fetched.count < 2 { await Task.yield() }
        await deadline.waitUntilPending(1)
        await deadline.releaseAll()
        #expect(await result.value.outcome == .unavailable)
        #expect(await store.load(persistentID: Self.id) == nil)
    }

    @Test func aCandidateThatAlignsOnlyAfterTheDeadlineIsNotStored() async {
        let deadline = GatedPollClock()
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.suspendIgnoringCancel(then: Self.aligned)],
        ])
        let (resolver, store) = resolver([provider], deadline: deadline)
        let result = Task { await resolver.resolve(request(), priority: .visible) }
        while await provider.fetched.isEmpty { await Task.yield() }
        await deadline.waitUntilPending(1)
        await deadline.releaseAll()
        while await resolver.isCollectingCandidates { await Task.yield() }
        await provider.release()
        #expect(await result.value.outcome == .unavailable)
        #expect(await store.load(persistentID: Self.id) == nil)
    }

    @Test func preemptedBackgroundWorkSearchesAgainFromScratch() async {
        let shared = FakeTimingProvider(.lrclib, searches: [
            .candidates([Self.candidate("bg0"), Self.candidate("bg1")]), .candidates([]), .candidates([Self.candidate("bg0")]),
        ], timings: [
            "bg0": [.outcome(Self.partial), .outcome(Self.unaligned)], "bg1": [.suspend(then: Self.aligned)],
        ])
        let fallback = FakeTimingProvider(.youtubeMusic, [.outcome(Self.aligned), .outcome(.noTiming(.notFound))])
        let (resolver, _) = resolver([shared, fallback])
        let background = Task { await resolver.resolve(TimingRequest(persistentID: "AAAAAAAAAAAAAAAA", lyrics: Self.lyrics, query: nil), priority: .background) }
        while await shared.fetched.count < 2 { await Task.yield() }
        let visible = await resolver.resolve(request(), priority: .visible)
        #expect(visible.outcome == .found(.youtubeMusic, Self.alignedLines))
        // 重跑從頭搜尋；第一次已通過的 bg0 不被沿用（這次 bg0 對不上）→ 全部明確沒有
        #expect(await background.value.outcome == .notFound)
        #expect(await shared.callCount == 3)
    }

    @Test func newLyricsDiscardTheOldWorksAcceptedCandidates() async {
        let provider = FakeTimingProvider(.lrclib, searches: [
            .candidates([Self.candidate("c0"), Self.candidate("c1")]), .candidates([Self.candidate("n0")]),
        ], timings: [
            "c0": [.outcome(Self.partial)], "c1": [.suspendIgnoringCancel(then: Self.weaker)], "n0": [.outcome(Self.otherAligned)],
        ])
        let (resolver, store) = resolver([provider])
        async let old = resolver.resolve(request(), priority: .background)
        while await provider.fetched.count < 2 { await Task.yield() }
        async let new = resolver.resolve(request(Self.otherLyrics), priority: .background)
        await Task.yield()
        await provider.release()
        let (oldResult, newResult) = await (old, new)
        #expect(oldResult.outcome == .cancelled)
        #expect(newResult.outcome == .found(.lrclib, [.init(index: 0, start: 30), .init(index: 1, start: 34), .init(index: 2, start: 40), .init(index: 3, start: 44)]))
        #expect(await store.load(persistentID: Self.id)?.lyricsHash == .of(Self.otherLyrics))
    }

    @Test func diagnosticsCarryTheRankAndThePick() async {
        let diagnostics = RecordingTimingDiagnostics()
        let provider = FakeTimingProvider(.lrclib, searches: [.candidates(Self.threeCandidates)], timings: [
            "c0": [.outcome(Self.unaligned)], "c1": [.outcome(Self.partial)], "c2": [.outcome(Self.weaker)],
        ])
        let (resolver, _) = resolver([provider], diagnostics: diagnostics)
        _ = await resolver.resolve(request(), priority: .background)
        let ranks = diagnostics.events.compactMap { event -> Int? in
            if case .answer(_, let rank, _, _) = event { return rank }
            return nil
        }
        #expect(ranks == [0, 1, 2])
        let picks = diagnostics.events.compactMap { event -> String? in
            if case .picked(let source, let rank, let tried) = event { return "\(source.rawValue) \(rank) \(tried)" }
            return nil
        }
        #expect(picks == ["lrclib 1 3"])
    }

    // MARK: 存檔

    @Test func aStoredAnswerIsReturnedWithoutTheNetwork() async throws {
        let store = TimingStore(directory: directory())
        try await store.save(TimingRecord(persistentID: Self.id, lyricsHash: .of(Self.lyrics), outcome: .found(source: .qq, lines: [.init(index: 0, start: 5)]), fetchedAt: Self.now))
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, _) = resolver([provider], store: store)
        #expect(await resolver.resolve(request(), priority: .visible).outcome == .found(.qq, [.init(index: 0, start: 5)]))
        #expect(await provider.callCount == 0)
    }

    @Test func aStoredAnswerWhoseIndicesNoLongerFitIsLookedUpAgain() async throws {
        let store = TimingStore(directory: directory())
        try await store.save(TimingRecord(persistentID: Self.id, lyricsHash: .of(Self.lyrics), outcome: .found(source: .qq, lines: [.init(index: 9, start: 5)]), fetchedAt: Self.now))
        let provider = FakeTimingProvider(.lrclib, [.outcome(Self.aligned)])
        let (resolver, _) = resolver([provider], store: store)
        guard case .found(.lrclib, _) = await resolver.resolve(request(), priority: .visible).outcome else { Issue.record("expected lookup"); return }
    }

    @Test func aRecentNotFoundIsReturnedWithoutTheNetwork() async throws {
        let store = TimingStore(directory: directory())
        try await store.save(TimingRecord(persistentID: Self.id, lyricsHash: .of(Self.lyrics), outcome: .notFound, fetchedAt: Self.now.addingTimeInterval(-86_400)))
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, _) = resolver([provider], store: store)
        #expect(await resolver.resolve(request(), priority: .visible).outcome == .notFound)
        #expect(await provider.callCount == 0)
    }

    /// 舊對齊版本的 found 重查一次；重查全是「沒有」時保留舊錨點、回給畫面、且不再重查（Codex review P2，2026-10-20）
    @Test func anOldAlignerFoundThatFindsNothingNewIsKeptAndNotRetriedAgain() async throws {
        let store = TimingStore(directory: directory())
        let old = TimingRecord(persistentID: Self.id, lyricsHash: .of(Self.lyrics), outcome: .found(source: .qq, lines: [.init(index: 0, start: 5)]),
                               fetchedAt: Self.now.addingTimeInterval(-86_400), alignerRevision: LRCAligner.revision - 1)
        try await store.save(old)
        let provider = FakeTimingProvider(.lrclib, [.outcome(.noTiming(.notFound)), .outcome(.noTiming(.notFound))])
        let (resolver, _) = resolver([provider], store: store)
        #expect(await resolver.resolve(request(), priority: .visible).outcome == .found(.qq, [.init(index: 0, start: 5)]))
        #expect(await provider.callCount == 1)
        #expect(await store.load(persistentID: Self.id)?.alignerRevision == LRCAligner.revision)
        #expect(await resolver.resolve(request(), priority: .visible).outcome == .found(.qq, [.init(index: 0, start: 5)]))
        #expect(await provider.callCount == 1)
    }

    @Test func aWeekOldNotFoundIsLookedUpAgain() async throws {
        let store = TimingStore(directory: directory())
        try await store.save(TimingRecord(persistentID: Self.id, lyricsHash: .of(Self.lyrics), outcome: .notFound, fetchedAt: Self.now.addingTimeInterval(-8 * 86_400)))
        let provider = FakeTimingProvider(.lrclib, [.outcome(Self.aligned)])
        let (resolver, _) = resolver([provider], store: store)
        guard case .found = await resolver.resolve(request(), priority: .visible).outcome else { Issue.record("expected lookup"); return }
    }

    // MARK: 去重、取消、搶占

    @Test func aSecondCallerForTheSameSongJoinsTheSameWork() async {
        let provider = FakeTimingProvider(.lrclib, [.suspend(then: Self.aligned)])
        let (resolver, _) = resolver([provider])
        async let first = resolver.resolve(request(), priority: .background)
        while await provider.callCount == 0 { await Task.yield() }
        async let second = resolver.resolve(request(), priority: .visible)
        await Task.yield()
        await provider.release()
        let (a, b) = await (first, second)
        #expect(a == b)
        #expect(await provider.callCount == 1)
    }

    @Test func newLyricsCancelTheOldWorkAndTheOldResultIsNeverStored() async throws {
        let provider = FakeTimingProvider(.lrclib, [.suspendIgnoringCancel(then: Self.aligned), .outcome(Self.otherAligned)])
        let (resolver, store) = resolver([provider])
        async let old = resolver.resolve(request(), priority: .background)
        while await provider.callCount == 0 { await Task.yield() }
        async let new = resolver.resolve(request(Self.otherLyrics), priority: .background)
        await Task.yield()
        await provider.release()
        let (oldResult, newResult) = await (old, new)
        #expect(oldResult.outcome == .cancelled)
        guard case .found = newResult.outcome else { Issue.record("expected new found"); return }
        #expect(await store.load(persistentID: Self.id)?.lyricsHash == .of(Self.otherLyrics))
    }

    @Test func aVisibleRequestPreemptsRunningBackgroundWorkWhichResumesAfterwards() async {
        let slow = FakeTimingProvider(.lrclib, [.suspend(then: Self.aligned), .outcome(Self.aligned), .outcome(Self.aligned)])
        let (resolver, _) = resolver([slow])
        let background = Task { await resolver.resolve(TimingRequest(persistentID: "AAAAAAAAAAAAAAAA", lyrics: Self.lyrics, query: nil), priority: .background) }
        while await slow.callCount == 0 { await Task.yield() }
        let visible = await resolver.resolve(request(), priority: .visible)
        guard case .found = visible.outcome else { Issue.record("visible should finish"); return }
        guard case .found = await background.value.outcome else { Issue.record("background should resume and finish"); return }
        #expect(await slow.callCount == 3)
    }

    @Test func aLookupThatRunsPastTheDeadlineIsUnavailable() async {
        let stuck = FakeTimingProvider(.lrclib, [.suspend(then: Self.aligned)])
        let (resolver, store) = resolver([stuck], deadline: FakeTimingClock())
        #expect(await resolver.resolve(request(), priority: .visible).outcome == .unavailable)
        #expect(await store.load(persistentID: Self.id) == nil)
    }

    @Test func theOldestWaitingBackgroundSongIsDroppedWhenTheQueueIsFull() async {
        let blocker = FakeTimingProvider(.lrclib, [.suspend(then: Self.aligned)])
        let (resolver, _) = resolver([blocker], queueLimit: 1)
        let running = Task { await resolver.resolve(TimingRequest(persistentID: "AAAAAAAAAAAAAAAA", lyrics: Self.lyrics, query: nil), priority: .background) }
        while await blocker.callCount == 0 { await Task.yield() }
        let dropped = Task { await resolver.resolve(TimingRequest(persistentID: "BBBBBBBBBBBBBBBB", lyrics: Self.lyrics, query: nil), priority: .background) }
        while await resolver.pendingCount < 1 { await Task.yield() }
        let kept = Task { await resolver.resolve(TimingRequest(persistentID: "CCCCCCCCCCCCCCCC", lyrics: Self.lyrics, query: nil), priority: .background) }
        #expect(await dropped.value.outcome == .skipped(.queueFull))
        await blocker.release()
        _ = await running.value
        _ = await kept.value
    }

    // MARK: 停用開關、關閉

    @Test func theGlobalSwitchDisablesEverything() async {
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, _) = resolver([provider], switches: TimingSwitches(lookupDisabled: true, disabledSources: []))
        #expect(await resolver.resolve(request(), priority: .visible).outcome == .skipped(.disabled))
        #expect(await provider.callCount == 0)
    }

    @Test func everySourceDisabledIsSkippedAndNothingIsStored() async {
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, store) = resolver([provider], switches: TimingSwitches(lookupDisabled: false, disabledSources: [.lrclib]))
        #expect(await resolver.resolve(request(), priority: .visible).outcome == .skipped(.disabled))
        #expect(await store.load(persistentID: Self.id) == nil)
    }

    @Test(arguments: ["", "   \n  ", "[Chorus]"])
    func blankLyricsAreSkippedAndNothingIsStored(lyrics: String) async {
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, store) = resolver([provider])
        #expect(await resolver.resolve(request(lyrics), priority: .background).outcome == .skipped(.noLyrics))
        #expect(await provider.callCount == 0)
        #expect(await store.load(persistentID: Self.id) == nil)
    }

    @Test func aDisabledSourceIsNotAsked() async {
        let off = FakeTimingProvider(.lrclib, [])
        let on = FakeTimingProvider(.qq, [.outcome(Self.aligned)])
        let (resolver, _) = resolver([off, on], switches: TimingSwitches(lookupDisabled: false, disabledSources: [.lrclib]))
        guard case .found(.qq, _) = await resolver.resolve(request(), priority: .visible).outcome else { Issue.record("expected qq"); return }
        #expect(await off.callCount == 0)
    }

    @Test func shutdownCancelsEverythingAndRefusesNewWork() async {
        let provider = FakeTimingProvider(.lrclib, [.suspend(then: Self.aligned)])
        let (resolver, store) = resolver([provider])
        let running = Task { await resolver.resolve(request(), priority: .background) }
        while await provider.callCount == 0 { await Task.yield() }
        await resolver.shutdown()
        #expect(await running.value.outcome == .cancelled)
        #expect(await resolver.resolve(request(Self.otherLyrics), priority: .visible).outcome == .cancelled)
        #expect(await provider.callCount == 1)
        #expect(await store.load(persistentID: Self.id) == nil)
    }
}
