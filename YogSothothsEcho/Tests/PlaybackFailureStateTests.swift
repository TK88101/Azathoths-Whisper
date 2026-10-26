import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S4 T11（sprint-4-detail.md §4.9；D4）：12 種失敗狀態的 iPad 側（V）——觸發 → 顯示 → 恢復。
// 每條對應一條 Mac 側（U／L）測試，名稱見計劃 §4.9 表

@MainActor
struct PlaybackFailureStateTests {
    let client = FakePlaybackClient()
    let sleeper = ManualSleeper()
    let nowPlaying: NowPlayingViewModel
    let tracks: AlbumTracksViewModel

    init() {
        nowPlaying = NowPlayingViewModel(now: ManualNow().now, sleep: { [sleeper] in await sleeper.sleep($0) })
        tracks = AlbumTracksViewModel(sleep: { [sleeper] in await sleeper.sleep($0) })
        client.lock.withLock {
            client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t1, 1),
                                                                                    PlaybackSamples.song(PlaybackSamples.t2, 2)]))
        }
        let nowPlaying = self.nowPlaying
        tracks.onResync = { nowPlaying.resync() }
        nowPlaying.attach(client)
        tracks.attach(client)
    }

    private func play(_ result: Result<PlayResult, EchoRequestError>) async {
        if tracks.album == nil { await tracks.open(PlaybackSamples.albumSummary) }
        client.lock.withLock { client.playResults = [result] }
        await tracks.play(PlaybackSamples.song(PlaybackSamples.t2, 2))
    }

    // #1 曲庫權限被拒：曲目清單與點歌都回 libraryUnavailable → 說明＋點歌不可用；Mac 恢復後重試即正常
    @Test func failureState1_libraryUnavailable() async {
        client.lock.withLock { client.tracks[PlaybackSamples.album] = .failure(.remote(.libraryUnavailable)) }
        await tracks.open(PlaybackSamples.albumSummary)
        #expect(tracks.phase == .failed(.libraryUnavailable) && !tracks.canPlay)
        client.lock.withLock { client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t1, 1)])) }
        await tracks.retry()
        #expect(tracks.phase == .ready && tracks.canPlay)
    }

    // #2 Music 自動化權限被拒：事件 availability=automationDenied → 說明、控制不可用；事件回 ok → 解除
    @Test func failureState2_automationDenied() async {
        client.push(PlaybackSamples.event(at: 1, availability: .automationDenied))
        await settle()
        #expect(nowPlaying.availability == .musicNotAuthorized && !PlaybackPresentation.controlsEnabled(nowPlaying.availability))
        client.push(PlaybackSamples.event(at: 2))
        await settle()
        #expect(nowPlaying.availability == .ready)
    }

    // #3 Music 未開：事件 availability=musicNotRunning → 「請在 Mac 上開啟 Music」＋重試；Music 開了推 ok → 解除
    @Test func failureState3_musicNotRunning() async {
        client.push(PlaybackSamples.event(nil, .stopped, availability: .musicNotRunning, albumID: nil))
        await settle()
        #expect(nowPlaying.availability == .musicNotRunning)
        #expect(PlaybackPresentation.offersRetry(.musicNotRunning))
        client.push(PlaybackSamples.event(at: 3))
        await settle()
        #expect(nowPlaying.availability == .ready)
    }

    // #4 剛在 Mac 手動操作：畫面跟著事件變，沒有任何提示
    @Test func failureState4_manualChangeOnMac() async {
        client.push(PlaybackSamples.event(PlaybackSamples.t1, .playing, at: 1))
        client.push(PlaybackSamples.event(PlaybackSamples.t2, .paused, at: 2))
        await settle()
        #expect(nowPlaying.currentTrackID == PlaybackSamples.t2 && nowPlaying.clock?.event.state == .paused)
        #expect(nowPlaying.notice == nil && tracks.notice == nil)
    }

    // #5 曲庫變動：點歌途中換版也照常出結果、沒有錯誤提示
    @Test func failureState5_catalogChangeDuringPlay() async {
        await tracks.open(PlaybackSamples.albumSummary)
        await play(.success(PlayResult(outcome: .verified, reason: nil)))
        #expect(tracks.notice == nil && tracks.phase == .ready)
    }

    // #6 斷線：控制不可用、在途點歌以 disconnected 結束不顯示結果；重連收到最新事件 → 恢復
    @Test func failureState6_disconnected() async {
        await play(.failure(.disconnected))
        #expect(tracks.notice == nil && tracks.pendingTrackID == nil)
        nowPlaying.detach()
        tracks.detach()
        #expect(nowPlaying.availability == .disconnected)
        let again = FakePlaybackClient()
        nowPlaying.attach(again)
        again.push(PlaybackSamples.event(at: 1))
        await settle()
        #expect(nowPlaying.availability == .ready)
    }

    // #7 捷徑未安裝：降級「已只播這首（Mac 缺少捷徑）」；之後 verified 無提示
    @Test func failureState7_missingShortcut() async {
        await play(.success(PlayResult(outcome: .degraded, reason: .shortcutMissing)))
        #expect(tracks.notice == .playedOnlyThis(.missingShortcut))
        await play(.success(PlayResult(outcome: .verified, reason: nil)))
        #expect(tracks.notice == nil)
    }

    // #8 捷徑被改動：(a) 佇列不符 → 已只播這首；(b) 不播 → 狀態無法確定
    @Test func failureState8_editedShortcut() async {
        await play(.success(PlayResult(outcome: .degraded, reason: .queueMismatch)))
        #expect(tracks.notice == .playedOnlyThis(.queueMismatch))
        await play(.success(PlayResult(outcome: .indeterminate, reason: .targetTimeout)))
        #expect(tracks.notice == .uncertain)
    }

    // #9 捷徑執行失敗：已只播這首＋重試；重試成功 → 無提示
    @Test func failureState9_shortcutFailed() async {
        await play(.success(PlayResult(outcome: .degraded, reason: .shortcutFailed)))
        #expect(tracks.notice == .playedOnlyThis(.shortcutFailed) && PlaybackPresentation.offersRetry(.playedOnlyThis(.shortcutFailed)))
        client.lock.withLock { client.playResults = [.success(PlayResult(outcome: .verified, reason: nil))] }
        await tracks.retryPlay()
        #expect(tracks.notice == nil)
        #expect(client.recorded.filter { $0 == "play:\(PlaybackSamples.t2)" }.count == 2)
    }

    // #10 驗證逾時：狀態無法確定＋重新同步；按下 → 提示消失、等下一筆事件為準
    @Test func failureState10_verifyTimeout() async {
        await play(.success(PlayResult(outcome: .indeterminate, reason: .queueTimeout)))
        #expect(tracks.notice == .uncertain)
        tracks.resync()
        #expect(tracks.notice == nil)
        client.push(PlaybackSamples.event(PlaybackSamples.t2, at: 4))
        await settle()
        #expect(nowPlaying.currentTrackID == PlaybackSamples.t2)
    }

    // #11 驗證不一致：已只播這首；10 s 後或下一次點歌時淡出
    @Test func failureState11_queueMismatchFades() async {
        await play(.success(PlayResult(outcome: .degraded, reason: .queueMismatch)))
        #expect(tracks.notice == .playedOnlyThis(.queueMismatch))
        await settle()
        await sleeper.wake()
        await settle()
        #expect(tracks.notice == nil)
    }

    // #12 遲到完成／手動操作：狀態無法確定；畫面跟著實際狀態，iPad 不自動重送
    @Test func failureState12_lateOrManualChange() async {
        await play(.success(PlayResult(outcome: .indeterminate, reason: .manualChange)))
        #expect(tracks.notice == .uncertain)
        client.push(PlaybackSamples.event(PlaybackSamples.t1, .paused, at: 6))
        await settle()
        #expect(nowPlaying.currentTrackID == PlaybackSamples.t1)
        #expect(client.recorded.filter { $0.hasPrefix("play:") }.count == 1)
    }
}
