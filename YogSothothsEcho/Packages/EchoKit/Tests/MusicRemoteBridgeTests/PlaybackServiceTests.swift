#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T9（sprint-4-detail.md §4.2、§4.4、§4.5 步驟 9、§4.7、§4.13）：PlaybackService 的組合與接線。
// 各元件自身的行為已由各自的測試涵蓋；這裡只驗「接起來」的部分：共用時鐘、連線存活與推送的接口、收件時驗證、隔離的靜止觀測

private let album = "00000000000000bb"
private let t1 = "0000000000000001", t2 = "0000000000000002", t3 = "0000000000000003", other = "00000000000000ff"
private let speaker = "00000000000000c1", tv = "00000000000000c2"

/// ScriptedMusic 加上 AirPlay 輸出與指令計數
actor ServiceMusic: PlaybackMusic {
    let base: ScriptedMusic
    private(set) var devices = [OutputDeviceSummary(id: speaker, kind: 1, selected: true),
                                OutputDeviceSummary(id: tv, kind: 2, selected: false)]
    private(set) var sent: [String] = []
    /// 非 nil＝每個操作都回這個錯誤（Music 未開、未授權）
    var failure: MusicLaneError?

    init(base: ScriptedMusic) { self.base = base }

    func set(failure: MusicLaneError?) { self.failure = failure }

    /// 送過奇數次 toggle＝播放／暫停對調（真的 Music 會改變狀態；不變的話 toggle 會等到讀回期限）
    private var toggled = false

    func snapshot() async throws(MusicLaneError) -> MusicSnapshot {
        if let failure { throw failure }
        let snapshot = try await base.snapshot()
        guard toggled else { return snapshot }
        let flipped: PlaybackState = snapshot.state == .playing ? .paused : snapshot.state == .paused ? .playing : snapshot.state
        return MusicSnapshot(state: flipped, trackID: snapshot.trackID, duration: snapshot.duration, position: snapshot.position)
    }
    func playOnce(trackID: String) async throws(MusicLaneError) -> Bool { try await base.playOnce(trackID: trackID) }
    func next() async throws(MusicLaneError) { sent.append("next") }
    func previous() async throws(MusicLaneError) { sent.append("previous") }
    func togglePlayPause() async throws(MusicLaneError) {
        if let failure { throw failure }
        sent.append("toggle"); toggled.toggle()
    }
    func seek(to seconds: Double) async throws(MusicLaneError) { sent.append("seek") }
    func outputs() async throws(MusicLaneError) -> [OutputDeviceSummary] { devices }
    func setOutputs(_ ids: [String]) async throws(MusicLaneError) -> Bool {
        sent.append("setOutputs")
        devices = devices.map { OutputDeviceSummary(id: $0.id, kind: $0.kind, selected: ids.contains($0.id)) }
        return true
    }
}

/// Genius 按鈕替身：照常 prepare／stillWanted，按下後 0.4 s 換到 a9（寫進 ScriptedMusic 的時間表）
actor ServiceGenius: GeniusPressing {
    let clock: ManualControlClock
    let scripted: ScriptedMusic
    private(set) var pressedAt: [Double] = []

    init(clock: ManualControlClock, scripted: ScriptedMusic) {
        self.clock = clock
        self.scripted = scripted
    }

    func pressGenius(prepare: @Sendable () async -> Bool, stillWanted: @Sendable () async -> Bool) async -> GeniusPress {
        guard await prepare(), await stillWanted() else { return .withheld }
        let now = await clock.now()
        pressedAt.append(now)
        await scripted.at(now + 0.4, MusicSnapshot(state: .playing, trackID: "00000000000000a9", duration: 180, position: 0))
        return .pressed
    }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct PlaybackServiceTests {
    let clock = ManualControlClock()
    let plans = FakePlans()
    let binding = FakeBindingStatus()
    let starter = FakeStarter()
    let scripted: ScriptedMusic
    let music: ServiceMusic
    let queue: ScriptedQueue
    let pushes = PushLog()
    let genius = GeniusBox()
    let presser: ServiceGenius
    let service: PlaybackService

    init() {
        scripted = ScriptedMusic(clock: clock, initial: MusicSnapshot(state: .playing, trackID: other, duration: 200, position: 30))
        music = ServiceMusic(base: scripted)
        queue = ScriptedQueue(clock: clock)
        let genius = self.genius
        presser = ServiceGenius(clock: clock, scripted: scripted)
        service = PlaybackService(music: music, plans: plans, albumOf: { $0 == other ? album : nil }, binding: binding,
                                  starter: starter, queueReader: queue, clock: clock, geniusAvailability: { genius.value },
                                  genius: presser)
    }

    private func attach() {
        let pushes = self.pushes
        service.setOutlets(PlaybackOutlets(isAlive: { _ in true }, push: { pushes.append($0) }))
    }

    private func play(_ track: String = t2, for span: Double) async -> ManagedOutcome {
        let service = self.service
        let task = Task { await service.play(PlayTrackRequest(trackID: track, albumID: album), connection: UUID()) }
        await clock.settle()
        await clock.advance(by: span)
        return await task.value
    }

    // MARK: 連線存活與推送的接口

    @Test func commandsBeforeOutletsAreAttachedNeverRun() async {
        #expect(await service.next(connection: UUID()) == .dropped)
        #expect(await music.sent.isEmpty)
    }

    @Test func detachingOutletsDropsLaterCommands() async {
        attach()
        service.setOutlets(nil)
        #expect(await service.previous(connection: UUID()) == .dropped)
        #expect(await music.sent.isEmpty)
    }

    @Test func pollerPushesThroughOutletsWithAlbumIDAndSharedClock() async {
        attach()
        await clock.advance(to: 4)
        await service.startWatching()
        let first = try? #require(pushes.all.first)
        #expect(first?.trackID == other && first?.albumID == album && first?.sampledAt == 4 && first?.availability == .ok)
        await service.stopWatching()
        let count = pushes.all.count
        await clock.advance(by: 30)
        #expect(pushes.all.count == count)
    }

    @Test func newConnectionResendsLatestState() async {
        attach()
        await service.startWatching()
        let count = pushes.all.count
        await service.connectionAdded()
        #expect(pushes.all.count == count + 1 && pushes.all.last == pushes.all.first)
        await service.stopWatching()
    }

    @Test func controlResultsCarryAlbumIDAndSharedClockTime() async {
        attach()
        await clock.advance(to: 7)
        guard case .success(let result) = await service.toggle() else { Issue.record("toggle failed"); return }
        #expect(result.playback.albumID == album && result.playback.sampledAt == 7)
        #expect(await music.sent == ["toggle"])
    }

    /// CR-030 G2：控制回覆的讀回與輪詢推送都從同一個注入點帶 Genius 可用性
    @Test func controlRepliesAndPushesCarryInjectedGeniusAvailability() async {
        attach()
        guard case .success(let denied) = await service.toggle() else { Issue.record("toggle failed"); return }
        #expect(denied.playback.genius == .needsAccessibility)
        genius.value = .ready
        guard case .success(let ready) = await service.toggle() else { Issue.record("toggle failed"); return }
        #expect(ready.playback.genius == .ready)
        await service.startWatching()
        #expect(pushes.all.first?.genius == .ready)
        await service.stopWatching()
    }

    /// CR-030 G5：Genius 經受管佇列執行（替身按鈕），回覆帶讀回；之後下一次輪詢一律推送
    @Test func geniusRunsThroughTheManagedQueue() async {
        attach()
        let service = self.service
        let task = Task { await service.genius(connection: UUID()) }
        _ = await eventually { await presser.pressedAt.count == 1 }
        await clock.settle()
        await clock.advance(by: 2)
        guard case .control(let result) = await task.value else { Issue.record("genius"); return }
        #expect(result.outcome == .applied && result.playback.trackID == "00000000000000a9")
        #expect(result.playback.genius == .needsAccessibility)
    }

    @Test func geniusBeforeOutletsAreAttachedNeverPresses() async {
        #expect(await service.genius(connection: UUID()) == .dropped)
        #expect(await presser.pressedAt.isEmpty)
    }

    /// 控制（toggle 等）之後的下一次輪詢一律推送
    @Test func controlTriggersAFreshPushOnNextPoll() async {
        attach()
        await service.startWatching()
        await clock.settle()
        let before = pushes.all.count
        _ = await service.toggle()
        await clock.advance(by: PlaybackLimits.pollInterval + 0.01)
        #expect(pushes.all.count > before)
        await service.stopWatching()
    }

    // MARK: 收件時驗證（不合法的請求不進佇列、不取代等待中的點歌）

    @Test func malformedPlayIsRejectedWithoutPlanning() async {
        attach()
        #expect(await service.play(PlayTrackRequest(trackID: "XYZ", albumID: album), connection: UUID()) == .error(.invalidRequest))
        #expect(starter.startCount == 0)
    }

    @Test func trackOutsideAlbumIsRejectedBeforeQueueing() async {
        attach()
        await plans.set(.failure(.invalidRequest))
        #expect(await play(for: 1) == .error(.invalidRequest))
        #expect(starter.startCount == 0)
        #expect(await binding.calls == 0)
    }

    @Test func malformedSeekIsRejected() async {
        attach()
        #expect(await service.seek(SeekRequest(trackID: other, seconds: -1)) == .failure(.invalidRequest))
        #expect(await music.sent.isEmpty)
    }

    // MARK: 捷徑無回應的全域隔離：輪詢器回報靜止才解除（§4.5 步驟 9）

    @Test func quarantineLiftsOnlyAfterPollerObservesQuiet() async {
        attach()
        // 捷徑一直不結束、目標曲不到：6 s 判無回應、終止並隔離
        #expect(await play(for: 10) == .play(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(starter.startCount == 1 && starter.last?.terminated == true)
        // 隔離中：不啟新捷徑
        #expect(await play(for: 1) == .play(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(starter.startCount == 1)
        // 沒有輪詢＝沒有靜止觀測：時間過了也不解除
        await clock.advance(by: 30)
        #expect(await play(for: 1) == .play(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(starter.startCount == 1)
        // 輪詢看到 Music 與佇列連續 3 s 不變 → 解除，下一次點歌會啟動捷徑
        await service.startWatching()
        await clock.settle()   // 等輪詢器進入第一次睡眠，否則時間會直接跳過它
        await clock.advance(by: 4)
        _ = await play(for: 10)
        #expect(starter.startCount == 2)
        await service.stopWatching()
    }

    /// simcodex R3 Codex P2：隔離中從服務入口點歌也不查目錄——目錄索引不在時 `plan` 會讀 ITLibrary；
    /// 入口只做格式驗證，隔離中一律回「暫停接受點歌」（連目錄閘門會拒絕的曲目也不 playOnce）
    @Test func quarantinedEntryNeverPlansOrTouchesMusic() async {
        attach()
        #expect(await play(for: 10) == .play(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        let planned = await plans.calls
        await plans.set(.success(.refused(.gateAmbiguousTitle)))
        #expect(await play(for: 1) == .play(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(await plans.calls == planned)
        #expect(await scripted.playOnceCalls.isEmpty)
    }

    /// security review MEDIUM-1：點歌在查捷徑時中繼被關掉（接口拆下）→ 不啟捷徑、不動 Music，回 dropped
    @Test func relayStoppedMidRequestNeverStartsShortcut() async {
        attach()
        let service = self.service
        await binding.set(onStatus: { service.setOutlets(nil) })
        #expect(await play(for: 20) == .dropped)
        let plays = await scripted.playOnceCalls
        #expect(starter.startCount == 0 && plays.isEmpty)
    }

    // MARK: §4.9 失敗狀態的 Mac 側（名稱照計劃表）

    /// #1：曲庫讀不到 → 點歌回 libraryUnavailable、不啟捷徑；曲庫恢復 → 下一次點歌照常走捷徑
    @Test func libraryUnavailableBlocksPlayAndRecovers() async {
        attach()
        await plans.set(.failure(.libraryUnavailable))
        #expect(await play(for: 1) == .error(.libraryUnavailable))
        #expect(starter.startCount == 0)
        await plans.set(.success(.admitted(ShortcutPlan(album: "A", albumArtist: "", artist: "B", order: [t1, t2, t3]))))
        _ = await play(for: 20)
        #expect(starter.startCount == 1)
    }

    /// #2：-1743 → 推 automationDenied、控制回 musicNotAuthorized；權限改回 → 退避（10 s）後的下一次輪詢推 ok
    @Test func automationDeniedMapsAndRecovers() async {
        attach()
        await music.set(failure: .notAuthorized)
        await service.startWatching()
        #expect(pushes.all.last?.availability == .automationDenied)
        #expect(await service.toggle() == .failure(.musicNotAuthorized))
        await music.set(failure: nil)
        await clock.settle()
        await clock.advance(by: 10.5)
        #expect(pushes.all.last?.availability == .ok)
        await service.stopWatching()
    }

    /// #3：Music 沒在跑 → 推 musicNotRunning、不送任何指令（MusicLane 綁 PID 不叫起，見 MusicLaneTests）；Music 開了 → 下一次輪詢推 ok
    @Test func musicNotRunningNeverLaunchesAndRecovers() async {
        attach()
        await music.set(failure: .notRunning)
        await service.startWatching()
        #expect(pushes.all.last?.availability == .musicNotRunning)
        #expect(await service.toggle() == .failure(.musicNotRunning))
        #expect(await music.sent.isEmpty)
        await music.set(failure: nil)
        await clock.settle()
        await clock.advance(by: 0.6)
        #expect(pushes.all.last?.availability == .ok)
        await service.stopWatching()
    }

    // MARK: AirPlay（§4.13）

    @Test func outputsAreListed() async {
        attach()
        #expect(await service.outputs() == .success(OutputListResponse(devices: await music.devices)))
    }

    @Test func unknownOutputDeviceIsInvalid() async {
        attach()
        #expect(await service.setOutputs(OutputSetRequest(deviceIDs: ["00000000000000dd"])) == .failure(.invalidRequest))
        #expect(await music.sent.isEmpty)
    }

    @Test func knownOutputDevicesAreSetAndReadBack() async {
        attach()
        guard case .success(let after) = await service.setOutputs(OutputSetRequest(deviceIDs: [tv])) else {
            Issue.record("setOutputs failed"); return
        }
        #expect(after.devices.filter(\.selected).map(\.id) == [tv])
        #expect(await music.sent == ["setOutputs"])
    }
}
#endif
