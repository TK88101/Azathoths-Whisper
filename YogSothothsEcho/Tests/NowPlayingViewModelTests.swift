import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S4 T11（sprint-4-detail.md §4.8）：目前曲、控制按鈕、亂序事件、斷線、世代、曲名快取

@MainActor
struct NowPlayingViewModelTests {
    let client = FakePlaybackClient()
    let now = ManualNow()
    let sleeper = ManualSleeper()
    let model: NowPlayingViewModel

    init() {
        model = NowPlayingViewModel(now: now.now, sleep: { [sleeper] in await sleeper.sleep($0) })
    }

    private func attached() async -> NowPlayingViewModel {
        model.attach(client)
        await settle()
        return model
    }

    @Test func eventsDriveCurrentTrackAndInterpolatedPosition() async {
        let model = await attached()
        client.push(PlaybackSamples.event(position: 10, at: 1))
        await settle()
        #expect(model.currentTrackID == PlaybackSamples.t1)
        now.advance(2.5)
        #expect(model.position() == 12.5)
    }

    @Test func outOfOrderEventsAreDropped() async {
        let model = await attached()
        client.push(PlaybackSamples.event(PlaybackSamples.t2, at: 5))
        client.push(PlaybackSamples.event(PlaybackSamples.t1, at: 4))
        await settle()
        #expect(model.currentTrackID == PlaybackSamples.t2)
    }

    /// 新連線（重連或 Mac 重啟）重置排序基準
    @Test func reconnectResetsOrdering() async {
        let model = await attached()
        client.push(PlaybackSamples.event(PlaybackSamples.t2, at: 5000))
        await settle()
        model.detach()
        let second = FakePlaybackClient()
        model.attach(second)
        second.push(PlaybackSamples.event(PlaybackSamples.t3, at: 2))
        await settle()
        #expect(model.currentTrackID == PlaybackSamples.t3)
    }

    @Test func controlReplyUpdatesStateThroughSameOrdering() async {
        let model = await attached()
        client.lock.withLock {
            client.controlResult = .success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(PlaybackSamples.t1, .paused, at: 9)))
        }
        await model.toggle()
        #expect(model.clock?.event.state == .paused)
        #expect(client.recorded == ["toggle"])
        // 晚到的舊事件不得蓋掉回覆裡的新狀態
        client.push(PlaybackSamples.event(PlaybackSamples.t1, .playing, at: 8))
        await settle()
        #expect(model.clock?.event.state == .paused)
    }

    @Test func busyShowsTooFastAndDoesNotResend() async {
        let model = await attached()
        client.lock.withLock { client.controlResult = .failure(.remote(.busy)) }
        await model.next()
        #expect(model.notice == .tooFast)
        #expect(client.recorded == ["next"])
    }

    @Test func notAppliedShowsNoticeAndAdoptsReadback() async {
        let model = await attached()
        client.lock.withLock {
            client.controlResult = .success(ControlResult(outcome: .notApplied, playback: PlaybackSamples.event(PlaybackSamples.t3, at: 3)))
        }
        await model.next()
        #expect(model.notice == .notApplied && model.currentTrackID == PlaybackSamples.t3)
    }

    @Test func fadingNoticeClearsAfterTimer() async {
        let model = await attached()
        client.lock.withLock { client.controlResult = .failure(.remote(.busy)) }
        await model.next()
        await settle()
        await sleeper.wake()
        await settle()
        #expect(model.notice == nil)
    }

    /// 拖進度條：等待回覆期間顯示預期值；回覆後回到事件值
    @Test func seekPreviewHoldsUntilReply() async {
        let model = await attached()
        client.push(PlaybackSamples.event(position: 10, at: 1))
        await settle()
        model.previewSeek(to: 120)
        #expect(model.position() == 120)
        client.lock.withLock {
            client.controlResult = .success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(position: 118, at: 2)))
        }
        await model.commitSeek()
        #expect(model.position() == 118 && model.seekPreview == nil)
        #expect(client.recorded.filter { $0.hasPrefix("seek:") } == ["seek:120.0"])
    }

    /// #6-1 F11：放開由兩條路觸發（Slider 的編輯結束、手指離開的手勢）——同一次拖曳只送一次 seek
    @Test func doubleCommitSendsOnce() async {
        let model = await attached()
        client.push(PlaybackSamples.event(position: 10, at: 1))
        await settle()
        model.previewSeek(to: 90)
        client.lock.withLock { client.holdControl = true }
        let first = Task { await model.commitSeek() }
        while client.heldControls < 1 { await Task.yield() }
        let second = Task { await model.commitSeek() }
        await settle()
        client.lock.withLock { client.holdControl = false }
        client.releaseOneControl()
        await first.value
        await second.value
        #expect(client.recorded.filter { $0.hasPrefix("seek:") } == ["seek:90.0"])
    }

    /// 等待回覆期間該按鈕記為進行中（按鈕不變淡、不鎖死）；同一按鈕連按，各次分開計數
    @Test func pendingIsCountedPerRequest() async {
        let model = await attached()
        client.lock.withLock { client.holdControl = true }
        let first = Task { await model.previous() }
        while client.heldControls < 1 { await Task.yield() }
        let second = Task { await model.previous() }
        while client.heldControls < 2 { await Task.yield() }
        #expect(model.pendingCount(.previous) == 2 && model.pendingCount(.next) == 0)
        client.releaseOneControl()
        await first.value
        #expect(model.pendingCount(.previous) == 1)     // 先回來的那次不會把後一次的進行中清掉
        client.lock.withLock { client.holdControl = false }
        client.releaseControls()
        await second.value
        #expect(model.pendingCount(.previous) == 0)
    }

    /// 轉圈只在等得比正常久時出現（> 2 s，thecure 2026-10-18 暫定，N-01 後定案）；回覆後消失
    @Test func spinnerAppearsOnlyAfterSlowThreshold() async {
        let model = await attached()
        client.lock.withLock { client.holdControl = true }
        let task = Task { await model.previous() }
        while client.heldControls == 0 { await Task.yield() }
        await settle()
        #expect(!model.isSlow(.previous))
        #expect(await sleeper.requested == [NowPlayingViewModel.slowControlThreshold])
        await sleeper.wake()
        await settle()
        #expect(model.isSlow(.previous))
        client.releaseControls()
        await task.value
        #expect(!model.isSlow(.previous))
    }

    /// 回覆在門檻前回來：計時到了也不轉圈
    @Test func fastReplyNeverShowsSpinner() async {
        let model = await attached()
        await model.previous()
        await sleeper.wake()
        await settle()
        #expect(!model.isSlow(.previous) && model.pendingCount(.previous) == 0)
    }

    /// 斷線：控制不可用；在途回覆（disconnected）不顯示提示；舊連線的晚到回覆不更新畫面
    @Test func detachDisablesControlsAndIgnoresLateReplies() async {
        let model = await attached()
        client.lock.withLock { client.controlResult = .failure(.disconnected) }
        await model.toggle()
        #expect(model.notice == nil)
        model.detach()
        #expect(model.availability == .disconnected && !PlaybackPresentation.controlsEnabled(model.availability))
        await model.toggle()
        #expect(client.recorded == ["toggle"])
    }

    /// CR-017：逐曲歌手與曲名一起快取（合輯每首不同）；換曲即換
    @Test func trackArtistFollowsCurrentTrack() async {
        client.lock.withLock {
            client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks([
                PlaybackSamples.song(PlaybackSamples.t1, 1, artist: "Made-up Singer A"),
                PlaybackSamples.song(PlaybackSamples.t2, 2, artist: "Made-up Singer B")]))
        }
        let model = await attached()
        #expect(model.trackArtist == nil)
        client.push(PlaybackSamples.event(PlaybackSamples.t1, at: 1))
        await settle()
        #expect(model.trackArtist == "Made-up Singer A")
        client.push(PlaybackSamples.event(PlaybackSamples.t2, at: 2))
        await settle()
        #expect(model.trackArtist == "Made-up Singer B" && model.trackTitle == "Made-up Song 2")
    }

    /// 曲名：以 albumID 取一次 album.tracks（分頁取完）並快取；專輯名由 library 對照
    @Test func trackTitleIsFetchedOncePerAlbum() async {
        client.lock.withLock {
            client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t1, 1)], next: "c2"))
            client.tracks[PlaybackSamples.album + "|c2"] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t2, 2)]))
        }
        model.albumLookup = { $0 == PlaybackSamples.album ? PlaybackSamples.albumSummary : nil }
        let model = await attached()
        client.push(PlaybackSamples.event(PlaybackSamples.t1, at: 1))
        client.push(PlaybackSamples.event(PlaybackSamples.t2, at: 2))
        await settle()
        #expect(model.trackTitle == "Made-up Song 2" && model.albumTitle == "Made-up Album")
        #expect(client.recorded.filter { $0.hasPrefix("tracks:") } == ["tracks:\(PlaybackSamples.album):-", "tracks:\(PlaybackSamples.album):c2"])
    }
}

/// CR-030 G6：Genius 送出與結果（Genius 專用處理，不走一般控制的 notApplied 提示）
@MainActor
struct NowPlayingGeniusTests {
    let client = FakePlaybackClient()
    let now = ManualNow()
    let sleeper = ManualSleeper()
    let model: NowPlayingViewModel

    init() {
        model = NowPlayingViewModel(now: now.now, sleep: { [sleeper] in await sleeper.sleep($0) })
    }

    private func attached(_ genius: GeniusAvailability? = .ready) async -> NowPlayingViewModel {
        model.attach(client)
        client.push(PlaybackSamples.event(at: 1, genius: genius))
        await settle()
        return model
    }

    /// 只看控制指令（事件帶 albumID 時 VM 會另取曲名）
    private var controls: [String] { client.recorded.filter { !$0.hasPrefix("tracks:") } }

    private func reply(_ result: Result<ControlResult, EchoRequestError>) {
        client.lock.withLock { client.controlResult = result }
    }

    @Test func readySendsOnceAndAdoptsTheNewSong() async {
        let model = await attached()
        reply(.success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(PlaybackSamples.t2, at: 5, genius: .ready))))
        await model.genius()
        #expect(controls == ["genius"])
        #expect(model.currentTrackID == PlaybackSamples.t2 && model.notice == nil)
    }

    @Test func needsAccessibilityShowsHintWithoutSending() async {
        let model = await attached(.needsAccessibility)
        await model.genius()
        #expect(controls.isEmpty)
        #expect(model.notice == .needsAccessibility)
    }

    @Test func oldMacNeverSends() async {
        let model = await attached(nil)
        await model.genius()
        #expect(controls.isEmpty && model.notice == nil)
    }

    /// CR-031：沒歌且停止也可送；換到新曲但暫停＝照樣採用讀回（applied＝換曲已確認，膠囊顯示 ▶）
    @Test func idleStoppedSendsAndAdoptsAPausedReadback() async {
        model.attach(client)
        client.push(PlaybackSamples.event(.none, .stopped, at: 1, albumID: nil, genius: .ready))
        await settle()
        #expect(model.geniusButton == .ready && model.currentTrackID == nil)
        reply(.success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(PlaybackSamples.t2, .paused, at: 5, genius: .ready))))
        await model.genius()
        #expect(controls == ["genius"])
        #expect(model.currentTrackID == PlaybackSamples.t2 && model.clock?.event.state == .paused && model.notice == nil)
    }

    /// 有殘留曲卻停止＝停用、不送
    @Test func stoppedWithLeftoverSongNeverSends() async {
        let model = await attached()
        client.push(PlaybackSamples.event(PlaybackSamples.t1, .stopped, at: 2, genius: .ready))
        await settle()
        #expect(model.geniusButton == .disabled)
        await model.genius()
        #expect(controls.isEmpty)
    }

    /// 按了但沒觀測到換曲：可能已改寫「接下來」＝無法確認＋Resync，採用讀回
    @Test func pressedButUnobservedIsUncertainAndAdoptsReadback() async {
        let model = await attached()
        reply(.success(ControlResult(outcome: .notApplied, playback: PlaybackSamples.event(PlaybackSamples.t1, .paused, at: 5, genius: .ready))))
        await model.genius()
        #expect(model.notice == .uncertain)
        #expect(model.clock?.event.state == .paused)
    }

    @Test(arguments: [(EchoRequestError.timeout, PlaybackPresentation.Notice.uncertain), (.disconnected, .uncertain),
                      (.remote(.notApplied), .notApplied), (.remote(.accessibilityDenied), .needsAccessibility),
                      (.remote(.busy), .tooFast)])
    func failuresMapToGeniusNotices(error: EchoRequestError, notice: PlaybackPresentation.Notice) async {
        let model = await attached()
        reply(.failure(error))
        await model.genius()
        #expect(controls == ["genius"])
        #expect(model.notice == notice)
    }

    /// 權限在 Mac 上改了：下一筆事件就更新鈕
    @Test func geniusAvailabilityFollowsEvents() async {
        let model = await attached(.needsAccessibility)
        #expect(model.geniusButton == .needsAccessibility)
        client.push(PlaybackSamples.event(at: 2, genius: .ready))
        await settle()
        #expect(model.geniusButton == .ready)
        #expect(model.pendingCount(.genius) == 0)
    }
}

