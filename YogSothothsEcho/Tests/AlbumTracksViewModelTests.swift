import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S4 T11（sprint-4-detail.md §4.8；CR-013(f)）：控制用極簡曲目選擇器——分頁取完、點歌各結果、世代

@MainActor
struct AlbumTracksViewModelTests {
    let client = FakePlaybackClient()
    let sleeper = ManualSleeper()
    let model: AlbumTracksViewModel

    init() {
        model = AlbumTracksViewModel(sleep: { [sleeper] in await sleeper.sleep($0) }, retry: CancellableSleeper().options)
        client.lock.withLock {
            client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks(
                [PlaybackSamples.song(PlaybackSamples.t1, 1), PlaybackSamples.song(PlaybackSamples.t2, 2)], next: "c2"))
            client.tracks[PlaybackSamples.album + "|c2"] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t3, 3)]))
        }
        model.attach(client)
    }

    @Test func openLoadsEveryPage() async {
        await model.open(PlaybackSamples.albumSummary)
        #expect(model.songs.map(\.id) == [PlaybackSamples.t1, PlaybackSamples.t2, PlaybackSamples.t3])
        #expect(model.phase == .ready && model.contextPlayable)
    }

    /// F-L1 R3：曲目頁一直 busy／rateLimited＝試滿 3 次後失敗（不卡在載入中）；中途恢復＝照常載完
    @Test func persistentlyBusyTracksFailAfterThreeTries() async {
        client.lock.withLock { client.tracks = [PlaybackSamples.album: .failure(.remote(.busy))] }
        await model.open(PlaybackSamples.albumSummary)
        #expect(model.phase == .failed(.network))
        #expect(client.trackCalls(PlaybackSamples.album).count == 3)
    }

    @Test func briefRateLimitIsRetriedTransparently() async {
        client.lock.withLock { client.trackSequence[PlaybackSamples.album + "|"] = [.failure(.remote(.rateLimited))] }
        await model.open(PlaybackSamples.albumSummary)
        #expect(model.phase == .ready)
        #expect(model.songs.map(\.id) == [PlaybackSamples.t1, PlaybackSamples.t2, PlaybackSamples.t3])
    }

    @Test func nonContextAlbumIsFlagged() async {
        client.lock.withLock {
            client.tracks = [PlaybackSamples.album: .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t1, 1)],
                                                                                    contextPlayable: false))]
        }
        await model.open(PlaybackSamples.albumSummary)
        #expect(!model.contextPlayable)
    }

    @Test func playShowsPreparingThenClearsOnVerified() async {
        await model.open(PlaybackSamples.albumSummary)
        client.lock.withLock { client.holdPlay = true }
        let task = Task { await model.play(model.songs[1]) }
        while client.heldPlays == 0 { await Task.yield() }
        #expect(model.pendingTrackID == PlaybackSamples.t2)
        client.releasePlay()
        await task.value
        #expect(model.pendingTrackID == nil && model.notice == nil)
        #expect(client.recorded.last == "play:\(PlaybackSamples.t2)")
    }

    /// 點了新的一首：舊的點歌結果（superseded 或晚到）不改畫面
    @Test func newerPlayWinsOverOlderResult() async {
        await model.open(PlaybackSamples.albumSummary)
        client.lock.withLock {
            client.holdPlay = true
            client.playResults = [.success(PlayResult(outcome: .degraded, reason: .queueMismatch)),
                                  .success(PlayResult(outcome: .verified, reason: nil))]
        }
        let first = Task { await model.play(model.songs[0]) }
        while client.heldPlays < 1 { await Task.yield() }
        let second = Task { await model.play(model.songs[2]) }
        while client.heldPlays < 2 { await Task.yield() }
        client.releasePlay()
        await first.value
        await second.value
        #expect(model.notice == nil && model.pendingTrackID == nil)
    }

    @Test func supersededIsSilent() async {
        await model.open(PlaybackSamples.albumSummary)
        client.lock.withLock { client.playResults = [.failure(.remote(.superseded))] }
        await model.play(model.songs[0])
        #expect(model.notice == nil)
    }

    @Test func busyShowsTooFast() async {
        await model.open(PlaybackSamples.albumSummary)
        client.lock.withLock { client.playResults = [.failure(.remote(.busy))] }
        await model.play(model.songs[0])
        #expect(model.notice == .tooFast)
    }

    @Test func closingStopsShowingTheAlbum() async {
        await model.open(PlaybackSamples.albumSummary)
        model.close()
        #expect(model.album == nil && model.songs.isEmpty)
    }

    // MARK: F7（s4-followups-2026-10-19.md T1）：斷線時開的專輯，重連後自動載入

    private func addOtherAlbum() {
        client.lock.withLock {
            client.tracks[PlaybackSamples.otherAlbum] = .success(AlbumTracksResponse(
                albumID: PlaybackSamples.otherAlbum, version: "00000000000000aa",
                songs: [PlaybackSamples.song(PlaybackSamples.t9, 1)], nextCursor: nil, contextPlayable: true))
        }
    }

    private func waitForHeldTracks(_ count: Int) async {
        while client.heldTracks < count { await Task.yield() }
    }

    @Test func albumOpenedWhileDisconnectedLoadsOnReattach() async {
        model.detach()
        await model.open(PlaybackSamples.albumSummary)
        #expect(model.phase == .loading)
        model.attach(client)
        await settleMain()
        #expect(model.phase == .ready)
        #expect(model.songs.map(\.id) == [PlaybackSamples.t1, PlaybackSamples.t2, PlaybackSamples.t3])
    }

    @Test func loadInterruptedByDisconnectRetriesOnReattach() async {
        client.lock.withLock { client.holdTracks = true }
        let opening = Task { await model.open(PlaybackSamples.albumSummary) }
        await waitForHeldTracks(1)
        model.detach()
        await settleMain()
        #expect(client.cancelledTrackLoads == 1)
        client.lock.withLock { client.holdTracks = false }
        model.attach(client)
        await settleMain()
        #expect(model.phase == .ready && model.songs.count == 3)
        client.releaseTracks()
        await opening.value
    }

    @Test func openingAnotherAlbumWhileDisconnectedLoadsOnReattach() async {
        addOtherAlbum()
        await model.open(PlaybackSamples.albumSummary)
        model.detach()
        await model.open(PlaybackSamples.otherAlbumSummary)
        #expect(model.phase == .loading)
        model.attach(client)
        await settleMain()
        #expect(model.phase == .ready)
        #expect(model.songs.map(\.id) == [PlaybackSamples.t9])
    }

    @Test func reattachDoesNotReloadReadyAlbum() async {
        await model.open(PlaybackSamples.albumSummary)
        let before = client.recorded.count
        model.detach()
        model.attach(client)
        await settleMain()
        #expect(client.recorded.count == before)
        #expect(model.phase == .ready)
    }

    @Test func closeCancelsInFlightLoad() async {
        client.lock.withLock { client.holdTracks = true }
        let opening = Task { await model.open(PlaybackSamples.albumSummary) }
        await waitForHeldTracks(1)
        model.close()
        await settleMain()
        #expect(client.cancelledTrackLoads == 1)
        #expect(model.phase == .idle && model.songs.isEmpty)
        client.lock.withLock { client.holdTracks = false }   // 放行後還有第二頁，不關會再停住
        client.releaseTracks()
        await opening.value
    }

    @Test func openingNewAlbumCancelsPreviousLoad() async {
        addOtherAlbum()
        client.lock.withLock { client.holdTracks = true }
        let first = Task { await model.open(PlaybackSamples.albumSummary) }
        await waitForHeldTracks(1)
        client.lock.withLock { client.holdTracks = false }
        await model.open(PlaybackSamples.otherAlbumSummary)
        await settleMain()
        #expect(client.cancelledTrackLoads == 1)
        #expect(model.songs.map(\.id) == [PlaybackSamples.t9])
        client.releaseTracks()
        await first.value
        #expect(model.songs.map(\.id) == [PlaybackSamples.t9])
    }

    /// F16（#4-1 9c 真機）：手動操作後被隔離擋下的點歌，提示要換成不同的文案（原本兩次都是「無法確認」，看起來像沒反應）
    @Test func blockedPickAfterManualChangeShowsADifferentNotice() async {
        await model.open(PlaybackSamples.albumSummary)
        client.lock.withLock {
            client.playResults = [.success(PlayResult(outcome: .indeterminate, reason: .manualChange)),
                                  .success(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive))]
        }
        await model.play(model.songs[0])
        #expect(model.notice == .uncertain)
        await model.play(model.songs[1])
        #expect(model.notice == .picksPaused)
    }
}
