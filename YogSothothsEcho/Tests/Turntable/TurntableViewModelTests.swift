import Foundation
import RemoteProtocol
import RemoteTransport
import Testing
import UIKit

@testable import YogSothothsEcho

// S5 T7（sprint-5-detail.md §4.1、§4.4–§4.6、D9）：組合狀態、標籤佔位、封面載入世代守衛、樣式偏好；
// T13（§4.4 v1.3，G7）：甩動轉場——送一次、展示快照、依已採用狀態分路、1.5 s 期限、加速、斷線與關閉取消計時

/// 封面讀取替身：每個專輯一個閘門，測試決定放行順序
actor ArtworkGate {
    private var waiting: [String: CheckedContinuation<UIImage?, Never>] = [:]
    func load(_ albumID: String) async -> UIImage? { await withCheckedContinuation { waiting[albumID] = $0 } }
    func release(_ albumID: String, _ image: UIImage?) { waiting.removeValue(forKey: albumID)?.resume(returning: image) }
    func isWaiting(_ albumID: String) -> Bool { waiting[albumID] != nil }
}

actor LoadCounter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}

/// 轉場計時替身：依時長分辨各段計時，測試決定哪一個到期（取消的計時仍掛著，用來驗證舊計時到期被忽略）
actor KeyedSleeper {
    private var waiters: [(Duration, CheckedContinuation<Void, Never>)] = []
    func sleep(_ duration: Duration) async { await withCheckedContinuation { waiters.append((duration, $0)) } }
    /// 放行所有該時長的計時；回傳放行數
    @discardableResult func wake(_ duration: Duration) -> Int {
        let due = waiters.filter { $0.0 == duration }
        waiters.removeAll { $0.0 == duration }
        due.forEach { $0.1.resume() }
        return due.count
    }
    func isWaiting(_ duration: Duration) -> Bool { waiters.contains { $0.0 == duration } }
}

private func solid(_ color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}

@MainActor
struct TurntableViewModelTests {
    let client = FakePlaybackClient()
    let nowPlaying = NowPlayingViewModel(now: ManualNow().now, sleep: { _ in })
    let store = InMemorySettingsStore()
    let gate = ArtworkGate()
    let timers = KeyedSleeper()
    let model: TurntableViewModel

    init() {
        let gate = gate, timers = timers
        model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2,
                                   artwork: { await gate.load($0) },
                                   palette: { _ in AlbumColors(primary: .white, text: .black, secondary: .white) },
                                   sleep: { _ in }, transitionSleep: { await timers.sleep($0) })
    }

    private static let lift = Duration.milliseconds(350), deadline = Duration.milliseconds(1500)

    /// 放行一個計時並等主執行緒處理完
    private func fire(_ duration: Duration) async {
        while !(await timers.isWaiting(duration)) { await Task.yield() }
        await timers.wake(duration)
        await settle()
    }

    private func reply(_ outcome: ControlOutcome, _ track: String?, album: String? = PlaybackSamples.album, state: PlaybackState = .playing,
                       at: Double = 2) {
        client.lock.withLock {
            client.controlResult = .success(ControlResult(outcome: outcome,
                                                          playback: PlaybackSamples.event(track, state, position: 0, at: at, albumID: album)))
        }
    }

    private func swipeLeft(reduceMotion: Bool = false) async {
        model.swipeChanged(CGSize(width: -5, height: 0))
        model.swipeEnded(CGSize(width: -80, height: 0), reduceMotion: reduceMotion)
        await settle()
    }

    private func start(_ state: PlaybackState = .playing, track: String = PlaybackSamples.t1) async {
        nowPlaying.attach(client)
        await settle()
        client.push(PlaybackSamples.event(track, state, at: 1))
        await settle()
    }

    private var controls: [String] { client.recorded.filter { !$0.hasPrefix("tracks:") } }

    @Test func recordStylePersists() {
        #expect(model.recordStyle == .random)
        model.recordStyle = .marble
        #expect(store.string(forKey: TurntableViewModel.recordStyleKey) == "marble")
        let again = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { _ in nil },
                                       palette: { _ in .fallback }, sleep: { _ in })
        #expect(again.recordStyle == .marble && again.resolvedStyle == .marble)
    }

    /// 標籤：沒有目前曲＝空；有曲但曲名未到＝「…」；到了就換上（含逐曲歌手）
    @Test func labelPlaceholderUntilTitleArrives() async {
        #expect(model.label == TurntableViewModel.Label(title: "", artist: ""))
        client.lock.withLock { client.holdTracks = true }
        await start()
        #expect(model.label == TurntableViewModel.Label(title: "…", artist: "…"))
        client.lock.withLock {
            client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t1, 1, artist: "Made-up Singer")]))
        }
        client.releaseTracks()
        await settle()
        #expect(model.label == TurntableViewModel.Label(title: "Made-up Song 1", artist: "Made-up Singer"))
    }

    /// 換專輯時舊封面晚到不得覆蓋新的；沒封面＝封面套用佔位、背景保留上一張、取色回退
    @Test func staleArtworkDoesNotOverwriteNewAlbum() async {
        let first = Task { await model.loadArtwork(albumID: "a1") }
        while !(await gate.isWaiting("a1")) { await Task.yield() }
        let second = Task { await model.loadArtwork(albumID: "a2") }
        while !(await gate.isWaiting("a2")) { await Task.yield() }
        let red = solid(.red), blue = solid(.blue)
        await gate.release("a2", blue)
        await second.value
        await gate.release("a1", red)
        await first.value
        #expect(model.cover === blue && model.backgroundSource === blue)
        #expect(model.colors.primary == .white)
        let third = Task { await model.loadArtwork(albumID: "a3") }
        while !(await gate.isWaiting("a3")) { await Task.yield() }
        await gate.release("a3", nil)
        await third.value
        #expect(model.cover == nil && model.backgroundSource === blue && model.colors == .fallback)
    }

    /// 取色期間換了專輯：舊專輯取完色也不得套用（取色後的過時守衛）
    @Test func paletteFinishingAfterAlbumChangeIsDiscarded() async {
        let paletteGate = ArtworkGate()
        let spineGate = gate
        let model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { await spineGate.load($0) },
                                       palette: { _ in _ = await paletteGate.load("palette"); return .fallback }, sleep: { _ in })
        let first = Task { await model.loadArtwork(albumID: "a1") }
        while !(await gate.isWaiting("a1")) { await Task.yield() }
        await gate.release("a1", solid(.red))
        while !(await paletteGate.isWaiting("palette")) { await Task.yield() }
        let second = Task { await model.loadArtwork(albumID: "a2") }
        while !(await gate.isWaiting("a2")) { await Task.yield() }
        await paletteGate.release("palette", nil)
        await first.value
        #expect(model.cover == nil)
        await gate.release("a2", nil)
        await second.value
    }

    /// 同一張專輯的封面 token 換了（視圖重新載入）：先前那次晚到的結果不得覆蓋新的（codex R1）
    @Test func laterLoadOfSameAlbumWins() async {
        let calls = ArtworkGate()
        let counter = LoadCounter()
        let model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2,
                                       artwork: { _ in await calls.load("call\(await counter.next())") },
                                       palette: { _ in .fallback }, sleep: { _ in })
        let first = Task { await model.loadArtwork(albumID: "a1") }
        while !(await calls.isWaiting("call1")) { await Task.yield() }
        let second = Task { await model.loadArtwork(albumID: "a1") }
        while !(await calls.isWaiting("call2")) { await Task.yield() }
        let fresh = solid(.green), stale = solid(.gray)
        await calls.release("call2", fresh)
        await second.value
        await calls.release("call1", stale)
        await first.value
        #expect(model.cover === fresh)
    }

    /// CR-018：先顯示 spine，原圖到了換上；換專輯後晚到的原圖不覆蓋；原圖取不到＝留在 spine
    @Test func detailReplacesSpineAndIsStaleGuarded() async {
        let detailGate = ArtworkGate()
        let spineGate = gate
        let model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { await spineGate.load($0) },
                                       detailArtwork: { await detailGate.load($0) }, palette: { _ in .fallback }, sleep: { _ in })
        let red = solid(.red), blue = solid(.blue), green = solid(.green)
        let load = Task { await model.loadArtwork(albumID: "a1") }
        while !(await gate.isWaiting("a1")) { await Task.yield() }
        await gate.release("a1", red)
        while !(await detailGate.isWaiting("a1")) { await Task.yield() }
        #expect(model.cover === red)
        await detailGate.release("a1", blue)
        await load.value
        #expect(model.cover === blue && model.backgroundSource === blue)
        let second = Task { await model.loadArtwork(albumID: "a2") }
        while !(await gate.isWaiting("a2")) { await Task.yield() }
        await gate.release("a2", green)
        while !(await detailGate.isWaiting("a2")) { await Task.yield() }
        await detailGate.release("a2", nil)
        await second.value
        #expect(model.cover === green)
    }

    /// D4：甩動閾值取自畫面的 displayScale；甩動進行中不換（避免同一手勢用到兩種閾值）
    @Test func displayScaleUpdatesThresholdOnlyWhenIdle() {
        model.setDisplayScale(3)
        #expect(abs(model.swipe.threshold - 100.0 / 3) < 1e-9)
        model.swipeChanged(CGSize(width: -5, height: 0))
        model.setDisplayScale(1)
        #expect(abs(model.swipe.threshold - 100.0 / 3) < 1e-9)
    }

    @Test func tapRecordToggles() async {
        await start()
        await model.tapRecord()
        #expect(controls == ["toggle"])
    }

    /// 同專輯：放手即送一次；回覆先到時畫面仍是舊曲（快照），抬臂計時到才換標籤，200 ms 後回 idle 解除凍結
    @Test func sameAlbumSendsOnceAndRelabelsAfterLift() async {
        await start()
        reply(.applied, PlaybackSamples.t2)
        await swipeLeft()
        #expect(controls == ["next"])
        #expect(nowPlaying.currentTrackID == PlaybackSamples.t2)
        #expect(model.groupDeck.trackID == PlaybackSamples.t1 && model.swipe.armLifted)
        await fire(Self.lift)
        #expect(model.swipe.phase == .relabeling && model.groupDeck.trackID == PlaybackSamples.t2)
        await fire(.milliseconds(200))
        #expect(model.swipe.phase == .idle && model.incomingDeck == nil && model.groupDeck.trackID == PlaybackSamples.t2)
        #expect(controls == ["next"])
    }

    @Test func rightSwipeSendsPrevious() async {
        await start()
        model.swipeChanged(CGSize(width: 5, height: 0))
        model.swipeEnded(CGSize(width: 80, height: 0), reduceMotion: false)
        await settle()
        #expect(controls == ["previous"])
    }

    /// notApplied 但 Mac 已在別張專輯（第三首）：依已採用狀態前進＝換封套，不回到舊曲
    @Test func notAppliedButMovedFollowsAdoptedState() async {
        await start()
        reply(.notApplied, PlaybackSamples.t9, album: PlaybackSamples.otherAlbum)
        await swipeLeft()
        await fire(Self.lift)
        #expect(model.swipe.phase == .clearing(.next))
        #expect(model.groupDeck.trackID == PlaybackSamples.t1 && model.incomingDeck?.trackID == PlaybackSamples.t9)
    }

    /// 錯誤早回不算 ready：期限到才決定；期間採用到換曲事件＝前進，沒有＝同曲回 idle
    @Test(arguments: [true, false])
    func errorWaitsForDeadline(eventArrives: Bool) async {
        await start()
        client.lock.withLock { client.controlResult = .failure(.remote(.busy)) }
        await swipeLeft()
        await fire(Self.lift)
        #expect(model.swipe.phase == .awaiting(.next))
        if eventArrives {
            client.push(PlaybackSamples.event(PlaybackSamples.t2, at: 5))
            await settle()
            #expect(model.swipe.phase == .awaiting(.next) && model.groupDeck.trackID == PlaybackSamples.t1)
        }
        await fire(Self.deadline)
        #expect(model.swipe.phase == (eventArrives ? .relabeling : .idle))
    }

    /// 底層請求一直沒回：1.5 s 期限到依已採用狀態決定；之後晚到的回覆照 S4 採用，但不再推進轉場
    @Test func deadlineDecidesAndLateReplyDoesNotRestart() async {
        await start()
        client.lock.withLock { client.holdControl = true }
        reply(.applied, PlaybackSamples.t2)
        await swipeLeft()
        await fire(Self.lift)
        await fire(Self.deadline)
        #expect(model.swipe.phase == .idle && model.incomingDeck == nil)
        client.releaseControls()
        await settle()
        #expect(nowPlaying.currentTrackID == PlaybackSamples.t2)
        #expect(model.swipe.phase == .idle && model.groupDeck.trackID == PlaybackSamples.t2)
    }

    /// 在途再甩只加速：不送第二個指令；之後進入的段 ×0.4
    @Test func reswipeAcceleratesWithoutSending() async {
        await start()
        client.lock.withLock { client.holdControl = true }
        await swipeLeft()
        await swipeLeft()
        #expect(controls == ["next"] && model.swipe.accelerated)
        await model.tapRecord()
        #expect(controls == ["next"])
        client.lock.withLock { client.controlResult = .success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(
            PlaybackSamples.t9, position: 0, at: 2, albumID: PlaybackSamples.otherAlbum))) }
        client.releaseControls()
        await settle()
        await fire(Self.lift)
        await fire(.milliseconds(60))   // clearing 150 × 0.4（v2.1 T6）
        #expect(model.swipe.phase == .sheathing(.next))
    }

    /// 不能送（未連線）：不開始轉場、不凍結
    @Test func cannotSendDoesNotStart() async {
        await swipeLeft()
        #expect(controls.isEmpty && model.swipe.phase == .returning && model.outgoingDeck == nil)
    }

    /// 斷線與關閉唱機：回 idle、解除凍結；被取消的舊計時到期也不推進
    @Test(arguments: [true, false])
    func disconnectOrCloseCancels(disconnect: Bool) async {
        await start()
        client.lock.withLock { client.holdControl = true }
        await swipeLeft()
        if disconnect {
            nowPlaying.detach()
            model.connectionLost()
        } else {
            model.cancelTransition()
        }
        #expect(model.swipe.phase == .idle && model.outgoingDeck == nil && !model.swipe.armLifted)
        await timers.wake(Self.lift)
        await timers.wake(Self.deadline)
        await settle()
        #expect(model.swipe.phase == .idle)
    }

    /// 甩動中點唱片、點封面套都忽略
    @Test func busyBlocksTaps() async {
        await start()
        client.lock.withLock { client.holdControl = true }
        await swipeLeft()
        await model.tapRecord()
        #expect(controls == ["next"] && !model.tapSleeve())
    }

    /// liveDeck 不借用別張專輯的封面；異專輯 incoming 只收同 albumID 的封面；背景到新封套進場才換
    @Test func decksUseOwnAlbumArtworkAndBackgroundWaitsForEntry() async {
        await start()
        let red = solid(.red), blue = solid(.blue)
        let first = Task { await model.loadArtwork(albumID: PlaybackSamples.album) }
        while !(await gate.isWaiting(PlaybackSamples.album)) { await Task.yield() }
        await gate.release(PlaybackSamples.album, red)
        await first.value
        #expect(model.liveDeck.cover === red && model.backgroundSource === red)
        reply(.applied, PlaybackSamples.t9, album: PlaybackSamples.otherAlbum)
        await swipeLeft()
        #expect(model.liveDeck.cover == nil && model.groupDeck.cover === red)
        await fire(Self.lift)
        #expect(model.incomingDeck?.cover == nil)
        let second = Task { await model.loadArtwork(albumID: PlaybackSamples.otherAlbum) }
        while !(await gate.isWaiting(PlaybackSamples.otherAlbum)) { await Task.yield() }
        await gate.release(PlaybackSamples.otherAlbum, blue)
        await second.value
        #expect(model.incomingDeck?.cover === blue && model.groupDeck.cover === red)
        #expect(model.backgroundSource === red)
        await fire(.milliseconds(150))   // clearing（v2.1 T6）
        await fire(.milliseconds(160))   // sheathing
        #expect(model.swipe.phase == .exchanging(.next) && model.backgroundSource === blue)
    }

    /// 換曲後 Mac 是暫停：收尾唱臂維持 0°、唱片不轉
    @Test func pausedAfterSwitchKeepsArmUp() async {
        await start()
        reply(.applied, PlaybackSamples.t2, state: .paused)
        await swipeLeft()
        await fire(Self.lift)
        await fire(.milliseconds(200))
        #expect(model.swipe.phase == .idle && model.armAngle() == 0)
        _ = model.recordAngle(at: 0)
        #expect(model.recordAngle(at: 10) == 0)
    }

    /// Reduce Motion：唱臂不抬、唱片不煞停；決定後交叉淡化
    @Test func reduceMotionCrossfades() async {
        await start()
        reply(.applied, PlaybackSamples.t9, album: PlaybackSamples.otherAlbum)
        await swipeLeft(reduceMotion: true)
        #expect(!model.swipe.armLifted)
        await fire(Self.lift)
        #expect(model.swipe.phase == .crossfading && model.groupDeck.trackID == PlaybackSamples.t9)
    }

    /// 唱臂顯示角：轉場中抬臂；否則跟播放進度（唱機不提供拖唱頭，CR-019）；轉場中唱片煞停
    @Test func armAngleSources() async {
        await start()
        #expect(abs(model.armAngle() - ResolvedTurntableSkin.classic.angle(progress: 10.0 / 200)) < 1e-9)
        model.swipeChanged(CGSize(width: -5, height: 0))
        #expect(model.armAngle() != 0)
        client.lock.withLock { client.holdControl = true }
        model.swipeEnded(CGSize(width: -80, height: 0), reduceMotion: false)
        #expect(model.armAngle() == 0)
        _ = model.recordAngle(at: 0)
        _ = model.recordAngle(at: 10)
        #expect(abs(model.recordAngle(at: 10) - model.recordAngle(at: 20)) < 1e-9)
    }

    /// 唱片只在播放中旋轉
    @Test func spinsOnlyWhilePlaying() async {
        await start()
        _ = model.recordAngle(at: 0)
        #expect(model.recordAngle(at: 10) == 180)
    }

    @Test func doesNotSpinWhilePaused() async {
        await start(.paused)
        _ = model.recordAngle(at: 0)
        #expect(model.recordAngle(at: 10) == 0)
    }
}
