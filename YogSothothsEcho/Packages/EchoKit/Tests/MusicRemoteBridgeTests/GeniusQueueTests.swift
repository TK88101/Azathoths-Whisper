#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// CR-030 G4（s6-61-genius.md §4.2 佇列）：Genius 與 next／previous／play.track 同 FIFO；執行中（含 hold）toggle／seek＝busy；
// 按下後一律以讀回確認（applied＝目前曲換了；期限內沒換＝ControlResult.notApplied），不回錯誤

/// Genius 按鈕替身：定位耗時 → prepare → 讀啟用耗時 → stillWanted → 按下（之後 changeDelay 秒換曲）
actor FakeGenius: GeniusPressing {
    private let clock: ManualControlClock
    private let target: FakeControlTarget
    var refusal: ErrorCode?
    var locateCost: Double = 0
    var enabledCost: Double = 0
    /// 按下後過多久換曲（nil＝Music 不理會）
    var changeDelay: Double? = 0.4
    private(set) var pressedAt: [Double] = []

    init(clock: ManualControlClock, target: FakeControlTarget) {
        self.clock = clock
        self.target = target
    }

    func set(refusal: ErrorCode?) { self.refusal = refusal }
    func set(locateCost: Double) { self.locateCost = locateCost }
    func set(enabledCost: Double) { self.enabledCost = enabledCost }
    func set(changeDelay: Double?) { self.changeDelay = changeDelay }

    func pressGenius(prepare: @Sendable () async -> Bool, stillWanted: @Sendable () async -> Bool) async -> GeniusPress {
        if let refusal { return .refused(refusal) }
        if locateCost > 0 { try? await clock.sleep(seconds: locateCost) }
        guard await prepare() else { return .withheld }
        if enabledCost > 0 { try? await clock.sleep(seconds: enabledCost) }
        guard await stillWanted() else { return .withheld }
        let now = await clock.now()
        pressedAt.append(now)
        if let changeDelay { await target.schedule(at: now + changeDelay, trackID: .some("00000000000000a9")) }
        return .pressed
    }
}

private func event(_ snapshot: MusicSnapshot) -> PlaybackEvent {
    PlaybackEvent(availability: .ok, trackID: snapshot.trackID, albumID: nil, state: snapshot.state,
                  position: snapshot.position, duration: snapshot.duration, sampledAt: 0)
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct GeniusQueueTests {
    let clock = ManualControlClock()
    let alive = AliveSet()
    let target: FakeControlTarget
    let player: FakePlayTrack
    let genius: FakeGenius
    let queue: RemoteCommandQueue
    let ipad = UUID()

    init() {
        target = FakeControlTarget(clock: clock)
        player = FakePlayTrack(clock: clock)
        genius = FakeGenius(clock: clock, target: target)
        let alive = self.alive
        queue = RemoteCommandQueue(target: target, playTrack: player, clock: clock, event: event, isAlive: { alive.isAlive($0) },
                                   genius: genius)
    }

    private func enqueue(_ command: ManagedCommand, from connection: UUID? = nil) async -> Task<(ManagedOutcome, Double), Never> {
        let queue = self.queue, clock = self.clock, connection = connection ?? ipad
        let before = await queue.acceptedCount
        let task = Task { (await queue.submit(command, connection: connection), await clock.time) }
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        return task
    }

    @Test func geniusIsAppliedAsSoonAsTheSongChangesAndHoldsTheQueueForSettle() async {
        let first = await enqueue(.genius)
        let next = await enqueue(.next)
        await clock.advance(to: 6)
        let (outcome, at) = await first.value
        guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return }
        #expect(result.outcome == .applied && result.playback.trackID == "00000000000000a9")
        #expect(at >= 0.4 && at < 0.55)
        _ = await next.value
        let sent = await target.sentAt
        #expect(sent.count == 1 && sent[0] >= 0.4 + PlaybackLimits.gateSettle - 0.05)
    }

    /// 按了但期限內沒換曲＝ControlResult.notApplied（不是錯誤；iPad 顯示「無法確認」）
    @Test func pressedWithoutChangeIsNotAppliedAfterTheDeadline() async {
        await genius.set(changeDelay: nil)
        let task = await enqueue(.genius)
        await clock.advance(to: 5)
        let (outcome, at) = await task.value
        guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return }
        #expect(result.outcome == .notApplied && result.playback.trackID == "0000000000000001")
        #expect(at >= PlaybackLimits.gateNoChangeDeadline)
    }

    /// 按下後讀回全失敗：仍回 ControlResult（按下可能已生效，不回錯誤）
    @Test func pressedThenFailingReadsStillAnswersWithAControlResult() async {
        await genius.set(changeDelay: nil)
        await target.set(failingReads: 0.05..<100)
        let task = await enqueue(.genius)
        await clock.advance(to: 5)
        guard case .control(let result) = await task.value.0 else { Issue.record("expected control"); return }
        #expect(result.outcome == .notApplied)
        #expect(await genius.pressedAt.count == 1)
    }

    @Test(arguments: [ErrorCode.accessibilityDenied, .musicNotRunning, .busy, .notApplied])
    func refusedPressIsAnErrorReply(code: ErrorCode) async {
        await genius.set(refusal: code)
        let task = await enqueue(.genius)
        await clock.advance(to: 1)
        #expect(await task.value.0 == .error(code))
    }

    /// 按下前讀回失敗＝不按，照實回錯
    @Test func failedReadBeforePressingIsAnErrorWithoutPressing() async {
        await target.set(failure: .notRunning)
        let task = await enqueue(.genius)
        await clock.advance(to: 1)
        #expect(await task.value.0 == .error(.musicNotRunning))
        #expect(await genius.pressedAt.isEmpty)
    }

    /// 定位中連線撤離＝按下前最後一刻查到、不按
    @Test func connectionGoneBeforePressingIsDroppedWithoutPressing() async {
        await genius.set(locateCost: 1)
        let task = await enqueue(.genius)
        alive.kill(ipad)
        await clock.advance(to: 3)
        #expect(await task.value.0 == .dropped)
        #expect(await genius.pressedAt.isEmpty)
    }

    /// 最壞：定位 5＋按下前讀回 2＋讀啟用 2＋等換曲 3＋跨界讀回 2 ≤ worstGenius
    @Test func slowAXAndSlowReadsFinishWithinWorstGenius() async {
        await genius.set(locateCost: GeniusMenu.locateDeadline + Double(GeniusMenu.messagingTimeout))
        await genius.set(enabledCost: Double(GeniusMenu.messagingTimeout))
        await genius.set(changeDelay: nil)
        await target.set(readDelay: PlaybackLimits.appleEventTimeout)
        let task = await enqueue(.genius)
        await clock.advance(to: 40)
        let (outcome, at) = await task.value
        guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return }
        #expect(result.outcome == .notApplied)
        #expect(at <= PlaybackLimits.worstGenius)
    }

    /// CR-031：按下前停止、沒歌 → 按下後有歌＝applied（不論播放或暫停：applied＝換曲已確認）；按下後仍沒歌＝notApplied
    @Test(arguments: [PlaybackState.playing, .paused])
    func idleStoppedToANewSongIsApplied(after: PlaybackState) async {
        await target.set(trackID: nil)
        await target.set(state: .stopped)
        let task = await enqueue(.genius)
        await clock.advance(to: 0.3)
        await target.set(state: after)
        await clock.advance(to: 5)
        guard case .control(let result) = await task.value.0 else { Issue.record("genius"); return }
        #expect(result.outcome == .applied && result.playback.trackID == "00000000000000a9" && result.playback.state == after)
    }

    @Test func idleStoppedThatStaysEmptyIsNotApplied() async {
        await target.set(trackID: nil)
        await target.set(state: .stopped)
        await genius.set(changeDelay: nil)
        let task = await enqueue(.genius)
        await clock.advance(to: 5)
        guard case .control(let result) = await task.value.0 else { Issue.record("genius"); return }
        #expect(result.outcome == .notApplied && result.playback.trackID == nil)
    }

    @Test func geniusRunsInFifoOrderWithNextAndPlayTrack() async {
        let next = await enqueue(.next)
        let geniusTask = await enqueue(.genius)
        let pick = await enqueue(.playTrack(PlayTrackRequest(trackID: "00000000000000aa", albumID: "00000000000000bb")))
        await clock.advance(to: 30)
        _ = await next.value
        _ = await geniusTask.value
        _ = await pick.value
        let nextAt = await target.sentAt, pressedAt = await genius.pressedAt, playAt = await player.startedAt
        #expect(nextAt.count == 1 && pressedAt.count == 1 && playAt.count == 1)
        #expect(pressedAt[0] >= nextAt[0] + 0.4 + PlaybackLimits.gateSettle - 0.05)
        #expect(playAt[0] >= pressedAt[0] + 0.4 + PlaybackLimits.gateSettle - 0.05)
    }

    /// 執行中（定位、按下前讀回、按下前、確認中、hold）toggle／seek 一律 busy；放行後照常
    @Test(arguments: [0.5, 1.2, 2.0, 2.8, 3.4])
    func toggleAndSeekAreBusyWhileGeniusRuns(at time: Double) async {
        await genius.set(locateCost: 1)                 // 0–1 定位
        await target.set(readDelay: 0.5)                // 1–1.5 按下前讀回
        await genius.set(enabledCost: 1)                // 1.5–2.5 讀啟用；2.5 按下，2.9 換曲
        let task = await enqueue(.genius)               // 2.6–3.1 讀回看到換曲 → hold 到 3.6
        await clock.advance(to: time)
        #expect(await queue.toggle() == .failure(.busy))
        #expect(await queue.seek(SeekRequest(trackID: "0000000000000001", seconds: 1)) == .failure(.busy))
        await clock.advance(to: 4)
        guard case .control(let result) = await task.value.0 else { Issue.record("genius"); return }
        #expect(result.outcome == .applied)
        let toggled = Task { await queue.toggle() }
        await clock.advance(to: 6)
        guard case .success = await toggled.value else { Issue.record("toggle after release"); return }
        #expect(await target.sent == ["toggle"])
    }
}

struct GeniusLimitsTests {
    @Test func worstGeniusCoversItsDeadlineGraphAndFitsTheBudget() {
        let locate = GeniusMenu.locateDeadline + Double(GeniusMenu.messagingTimeout)
        let path = locate + PlaybackLimits.appleEventTimeout + Double(GeniusMenu.messagingTimeout)
            + PlaybackLimits.gateNoChangeDeadline + PlaybackLimits.appleEventTimeout
        #expect(path <= PlaybackLimits.worstGenius)
        #expect(PlaybackLimits.worstGenius == 16)
        #expect(ManagedKind.genius.worst == PlaybackLimits.worstGenius)
        #expect(PlaybackLimits.worstPlayTrack + PlaybackLimits.worstGenius + PlaybackLimits.worstNextPrevious * 2
                <= PlaybackLimits.managedAdmissionBudget)
        #expect(ManagedCommand.genius.kind == .genius)
    }
}
#endif
