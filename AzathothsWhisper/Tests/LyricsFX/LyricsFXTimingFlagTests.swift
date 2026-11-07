import Foundation
import Testing

@testable import AzathothsWhisper

/// 標記後端的替身：記錄請求；可掛住到測試放行（亂序測試用）
@MainActor
final class FlagBackendSpy {
    private(set) var toggles: [TimingFlagRequest] = []
    private(set) var lookups: [TimingFlagKey] = []
    var holdToggle = false
    var holdLookup = false
    var toggleAnswer = true
    var lookupAnswer = false
    private var toggleWaiters: [CheckedContinuation<Bool, Never>] = []
    private var lookupWaiters: [CheckedContinuation<Bool, Never>] = []

    func toggle(_ request: TimingFlagRequest) async -> Bool {
        toggles.append(request)
        guard holdToggle else { return toggleAnswer }
        return await withCheckedContinuation { toggleWaiters.append($0) }
    }

    func lookup(_ key: TimingFlagKey) async -> Bool {
        lookups.append(key)
        guard holdLookup else { return lookupAnswer }
        return await withCheckedContinuation { lookupWaiters.append($0) }
    }

    var heldToggles: Int { toggleWaiters.count }
    var heldLookups: Int { lookupWaiters.count }

    func releaseToggle(_ answer: Bool) {
        guard !toggleWaiters.isEmpty else { Issue.record("no held toggle"); return }
        toggleWaiters.removeFirst().resume(returning: answer)
    }

    func releaseLookup(_ answer: Bool) {
        guard !lookupWaiters.isEmpty else { Issue.record("no held lookup"); return }
        lookupWaiters.removeFirst().resume(returning: answer)
    }
}

// ⑪ 計劃 §4.1、§4.3：VM 保存畫面實際套用的時間軸快照；標記請求在 await 前擷取；pending 與 epoch 防亂序。歌詞為編造句
@MainActor
@Suite("LyricsFX timing flag")
struct LyricsFXTimingFlagTests {
    static let track = TrackInfo.fixture(id: "0123456789ABCDEF")
    static let other = TrackInfo.fixture(id: "FEDCBA9876543210")
    static let lyrics = "Lanterns over the river\nAsh in the wind"
    static let metadata = TrackMetadata(genre: "Black Metal", duration: 200)
    static let found: [TimingRecord.LineStart] = [.init(index: 0, start: 5), .init(index: 1, start: 9)]
    static let key = TimingFlagKey(persistentID: track.persistentID, lyricsHash: .of(lyrics))

    struct Harness {
        let model: LyricsFXViewModel
        let backend: FlagBackendSpy
    }

    private func harness(foundTiming: Bool = true) async -> Harness {
        let music = MockMusicClient()
        await music.setPlaybackPositions([.success(PlaybackPosition(persistentID: Self.track.persistentID, seconds: 12.34, state: .playing, readAt: .now, roundTrip: .zero))])
        let model = LyricsFXViewModel(positionClock: PlaybackPositionClock(music: music, pollClock: GatedPollClock()))
        let found = Self.found
        model.timingLookup = { @Sendable request in
            TimingResolution(persistentID: request.persistentID, lyricsHash: .of(request.lyrics), outcome: foundTiming ? .found(.lrclib, found) : .notFound)
        }
        let backend = FlagBackendSpy()
        model.onToggleTimingFlag = { await backend.toggle($0) }
        model.timingFlagLookup = { await backend.lookup($0) }
        return Harness(model: model, backend: backend)
    }

    /// 播放並顯示特效層，等外部時間軸熱替換上來
    private func playingWithFoundTiming(_ h: Harness, track: TrackInfo = track, lyrics: String = lyrics) async {
        h.model.handle(.trackChanged(track, existingLyrics: lyrics, metadata: Self.metadata))
        h.model.setVisible(true)
        await waitUntil({ h.model.timeline?.source == .lrclib }, iterations: 2000)
        await waitUntil({ h.model.positionClock.anchor != nil }, iterations: 2000)
    }

    @Test func theSnapshotIsTheTimingActuallyApplied() async {
        let h = await harness()
        await playingWithFoundTiming(h)
        #expect(h.model.appliedTiming == AppliedTiming(source: .lrclib, anchors: Self.found))
        #expect(h.model.canToggleTimingFlag)
    }

    @Test func embeddedLRCGetsASnapshotOfItsOwnLineStarts() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: "[00:01.00]Lanterns\n[00:03.50]Ash", metadata: Self.metadata))
        #expect(h.model.appliedTiming == AppliedTiming(source: .embeddedLRC, anchors: [.init(index: 0, start: 1), .init(index: 1, start: 3.5)]))
        #expect(h.model.canToggleTimingFlag)
    }

    @Test func estimatedTimingHasNoSnapshotAndCannotBeFlagged() async {
        let h = await harness(foundTiming: false)
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.setVisible(true)
        await settle()
        #expect(h.model.timeline?.source == .estimated)
        #expect(h.model.appliedTiming == nil)
        #expect(!h.model.canToggleTimingFlag)
        h.model.toggleTimingFlag()
        await settle()
        #expect(h.backend.toggles.isEmpty)
    }

    @Test func withoutABackendFlaggingIsUnavailable() async {
        let h = await harness()
        h.model.onToggleTimingFlag = nil
        await playingWithFoundTiming(h)
        #expect(!h.model.canToggleTimingFlag)
    }

    @Test func aNewTrackClearsTheSnapshotAndTheFlagState() async {
        let h = await harness()
        await playingWithFoundTiming(h)
        h.model.toggleTimingFlag()
        await waitUntil({ h.model.timingFlag == .flagged })
        h.model.handle(.trackChanged(Self.other, existingLyrics: "Quiet harbor", metadata: Self.metadata))
        #expect(h.model.timeline?.source == .estimated)
        #expect(h.model.appliedTiming == nil)
        #expect(h.model.timingFlag == .unflagged)
    }

    @Test func flaggingSendsTheCurrentSongTheSnapshotAndThePosition() async throws {
        let h = await harness()
        await playingWithFoundTiming(h)
        h.model.toggleTimingFlag()
        #expect(h.model.timingFlag == .pending)
        await waitUntil({ h.model.timingFlag == .flagged })
        let request = try #require(h.backend.toggles.first)
        #expect(request.key == Self.key)
        #expect(request.applied == AppliedTiming(source: .lrclib, anchors: Self.found))
        #expect(request.wantsFlagged)
        let position = try #require(request.position)
        #expect(abs(position - 12.3) < 0.051)   // 0.1 s 粒度
        #expect(h.model.timingMark == .flagged)

        h.model.toggleTimingFlag()
        await waitUntil({ h.model.timingFlag == .unflagged })
        #expect(h.backend.toggles.last?.wantsFlagged == false)
        #expect(h.model.timingMark == .none)
    }

    @Test func theRequestIsCapturedBeforeAnySuspension() async throws {
        let h = await harness()
        h.backend.holdToggle = true
        await playingWithFoundTiming(h)
        h.model.toggleTimingFlag()
        // 按下之後馬上換歌：送出的仍是按下當時那首
        h.model.handle(.trackChanged(Self.other, existingLyrics: "Quiet harbor", metadata: Self.metadata))
        await waitUntil({ h.backend.heldToggles == 1 })
        #expect(h.backend.toggles.first?.key == Self.key)
        h.backend.releaseToggle(true)
        await settle()
        #expect(h.model.timingFlag == .unflagged)   // 舊歌的結果不套到新歌
    }

    @Test func aPendingToggleCannotBeTriggeredAgain() async {
        let h = await harness()
        h.backend.holdToggle = true
        await playingWithFoundTiming(h)
        h.model.toggleTimingFlag()
        await waitUntil({ h.backend.heldToggles == 1 })
        #expect(!h.model.canToggleTimingFlag)
        h.model.toggleTimingFlag()
        await settle()
        #expect(h.backend.toggles.count == 1)
        h.backend.releaseToggle(true)
        await waitUntil({ h.model.timingFlag == .flagged })
        #expect(h.model.canToggleTimingFlag)
    }

    @Test func aFailedToggleRestoresThePreviousState() async {
        let h = await harness()
        h.backend.toggleAnswer = false
        await playingWithFoundTiming(h)
        h.model.toggleTimingFlag()
        await waitUntil({ h.model.timingFlag != .pending })
        #expect(h.model.timingFlag == .unflagged)
    }

    @Test func aStoredFlagIsPickedUpWhenTheSongComesBack() async {
        let h = await harness()
        h.backend.lookupAnswer = true
        await playingWithFoundTiming(h)
        await waitUntil({ h.model.timingFlag == .flagged })
        #expect(h.backend.lookups == [Self.key])
        #expect(h.model.timingMark == .flagged)
    }

    @Test func aFlaggedSongShowsOnlyTheTildeUntilItsTimingIsBack() async {
        let h = await harness()
        h.backend.lookupAnswer = true
        let hold = AsyncHold()
        let found = Self.found
        h.model.timingLookup = { @Sendable request in
            await hold.wait()
            return TimingResolution(persistentID: request.persistentID, lyricsHash: .of(request.lyrics), outcome: .found(.lrclib, found))
        }
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.setVisible(true)
        await waitUntil({ h.model.timingFlag == .flagged })
        #expect(h.model.timingMark == .estimated)
        await hold.release()
        await waitUntil({ h.model.timeline?.source == .lrclib }, iterations: 2000)
        #expect(h.model.timingMark == .flagged)
    }

    @Test func aLookupThatReturnsAfterAToggleCompletedIsDropped() async {
        let h = await harness()
        h.backend.holdLookup = true
        await playingWithFoundTiming(h)
        await waitUntil({ h.backend.heldLookups == 1 })
        h.model.toggleTimingFlag()
        await waitUntil({ h.model.timingFlag == .flagged })
        h.backend.releaseLookup(false)
        await settle()
        #expect(h.model.timingFlag == .flagged)
    }

    @Test func aLookupThatReturnsWhileAToggleIsPendingIsDropped() async {
        let h = await harness()
        h.backend.holdLookup = true
        h.backend.holdToggle = true
        await playingWithFoundTiming(h)
        await waitUntil({ h.backend.heldLookups == 1 })
        h.model.toggleTimingFlag()
        await waitUntil({ h.backend.heldToggles == 1 })
        h.backend.releaseLookup(true)
        await settle()
        #expect(h.model.timingFlag == .pending)
        h.backend.releaseToggle(false)
        await waitUntil({ h.model.timingFlag != .pending })
        #expect(h.model.timingFlag == .unflagged)
    }

    @Test func newMetadataForTheSameLyricsKeepsTheFlagWithoutAskingAgain() async {
        let h = await harness()
        h.backend.lookupAnswer = true
        await playingWithFoundTiming(h)
        await waitUntil({ h.model.timingFlag == .flagged })
        h.model.metadataUpdated(persistentID: Self.track.persistentID, metadata: TrackMetadata(genre: "Doom Metal", duration: 200))
        await settle()
        #expect(h.model.timingFlag == .flagged)
        #expect(h.backend.lookups.count == 1)
    }

    @Test func changedLyricsAreAnotherKey() async {
        let h = await harness()
        h.backend.lookupAnswer = true
        await playingWithFoundTiming(h)
        await waitUntil({ h.model.timingFlag == .flagged })
        h.backend.lookupAnswer = false
        h.model.lyricsUpdated(persistentID: Self.track.persistentID, text: "Quiet harbor\nSalt on the glass")
        await waitUntil({ h.backend.lookups.count == 2 })
        await settle()
        #expect(h.backend.lookups.last == TimingFlagKey(persistentID: Self.track.persistentID, lyricsHash: .of("Quiet harbor\nSalt on the glass")))
        #expect(h.model.timingFlag == .unflagged)
    }
}

/// 掛住一個 async 呼叫直到放行
actor AsyncHold {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
