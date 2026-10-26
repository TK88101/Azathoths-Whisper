#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T6（sprint-4-detail.md §4.4；CR-006②；D6）：確認式節奏的受管佇列。
// 時間全用手動時鐘：測試推進時間，佇列裡的等待才會醒（真實時間不參與判定）

/// 手動時鐘：sleep 掛起直到測試推進到喚醒時刻
actor ManualControlClock: ControlClock {
    private var current: Double = 0
    private var sleepers: [(wake: Double, id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    nonisolated func now() async -> Double { await current }

    func sleep(seconds: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sleepers.append((current + seconds, id, continuation))
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    var sleeperCount: Int { sleepers.count }
    var time: Double { current }

    /// 喚醒最早一個 wake ≤ limit 的睡眠者並把時間設到它；沒有則把時間推到 limit。回傳是否喚醒了誰
    func step(until limit: Double) -> Bool {
        guard let index = sleepers.indices.filter({ sleepers[$0].wake <= limit }).min(by: { sleepers[$0].wake < sleepers[$1].wake })
        else { current = max(current, limit); return false }
        let sleeper = sleepers.remove(at: index)
        current = max(current, sleeper.wake)
        sleeper.continuation.resume()
        return true
    }
}

extension ManualControlClock {
    /// 推進到 `target`：先等系統安定（剛啟動的背景迴圈還沒睡就推進，時間會直接跳過它），
    /// 再逐一喚醒到期的睡眠者，每次喚醒後讓系統跑到下一個穩定點
    func advance(to target: Double) async {
        await settle()
        while step(until: target) { await settle() }
        await settle()
    }

    func advance(by seconds: Double) async { await advance(to: await time + seconds) }

    /// 等系統安定：連續幾次觀察睡眠者數量不變
    nonisolated func settle() async {
        var stable = 0, last = -1
        while stable < 5 {
            try? await Task.sleep(for: .milliseconds(2))
            let count = await sleeperCount
            stable = count == last ? stable + 1 : 0
            last = count
        }
    }
}

/// Music 替身：依時間表回報目前曲；記下送出的指令
actor FakeControlTarget: ControlTarget {
    var trackID: String? = "0000000000000001"
    var state: PlaybackState = .playing
    /// 進度＝錨點＋（播放中才）經過的時間：真的 Music 播放中進度會往前走
    private var anchor: (position: Double, at: Double) = (10, 0)
    var duration: Double? = 200
    var failure: MusicLaneError?
    /// 只讓播放／暫停、seek 這個指令本身失敗（讀回照常）
    var sendFailure: MusicLaneError?
    /// next／previous 送出後過多久換曲（nil＝不理會）
    var changeDelay: Double? = 0.4
    /// 播放／暫停送出後過多久狀態才改變（0＝立刻；nil＝不理會）。真機的 Music 會晚幾百毫秒才反映（#4-1）
    var toggleDelay: Double? = 0
    /// next／previous 這個 Apple Event 本身花多久才送完（Music 忙時可到 appleEventTimeout）
    var sendDelay: Double = 0
    /// 每次讀回花多久（Music 忙時一次 AE 可到 2 s）
    var readDelay: Double = 0
    /// 這段時間內的讀回都失敗（AE 錯誤，非未開／未授權）
    var failingReads: Range<Double>?
    private(set) var sent: [String] = []
    /// next／previous 實際送給 Music 的時刻（確認式節奏：換曲觀測後 1 s 內不得送下一個）
    private(set) var sentAt: [Double] = []
    private var pendingChange: (at: Double, to: String)?
    private var pendingToggle: (at: Double, to: PlaybackState)?
    /// 依時刻改寫的讀回（trackID：.none＝不動、.some(nil)＝換歌瞬間的空 ID）
    private var scripted: [(at: Double, position: Double?, trackID: String??)] = []
    private let clock: ManualControlClock

    init(clock: ManualControlClock) { self.clock = clock }

    func set(failure: MusicLaneError?) { self.failure = failure }
    func set(sendFailure: MusicLaneError?) { self.sendFailure = sendFailure }
    func set(changeDelay: Double?) { self.changeDelay = changeDelay }
    func set(trackID: String?) { self.trackID = trackID }
    func set(toggleDelay: Double?) { self.toggleDelay = toggleDelay }
    func set(sendDelay: Double) { self.sendDelay = sendDelay }
    func set(readDelay: Double) { self.readDelay = readDelay }
    func set(failingReads: Range<Double>?) { self.failingReads = failingReads }
    func set(position: Double) async { anchor = (position, await clock.now()) }
    func set(state: PlaybackState) async {
        let now = await clock.now()
        anchor = (position(at: now), now); self.state = state
    }

    private func position(at now: Double) -> Double { anchor.position + (state == .playing ? now - anchor.at : 0) }
    func schedule(at time: Double, position: Double? = nil, trackID: String?? = .none) {
        scripted.append((time, position, trackID)); scripted.sort { $0.at < $1.at }
    }

    private func applyPending() async {
        let now = await clock.now()
        if let change = pendingChange, now >= change.at { trackID = change.to; pendingChange = nil; anchor = (0, change.at) }
        if let toggle = pendingToggle, now >= toggle.at { anchor = (position(at: toggle.at), toggle.at); state = toggle.to; pendingToggle = nil }
        while let first = scripted.first, now >= first.at {
            scripted.removeFirst()
            if let value = first.position { anchor = (value, first.at) }
            if let value = first.trackID { trackID = value }
        }
    }

    func snapshot() async throws(MusicLaneError) -> MusicSnapshot {
        if let failure { throw failure }
        if let failingReads, failingReads.contains(await clock.now()) { throw .failed(code: -1712) }
        if readDelay > 0 { try? await clock.sleep(seconds: readDelay) }
        await applyPending()
        return MusicSnapshot(state: state, trackID: trackID, duration: duration, position: position(at: await clock.now()))
    }

    private func step(_ name: String, delta: Int) async throws(MusicLaneError) {
        if let failure { throw failure }
        if sendDelay > 0 { try? await clock.sleep(seconds: sendDelay) }
        sent.append(name)
        sentAt.append(await clock.now())
        guard let delay = changeDelay, let current = trackID, let value = UInt64(current, radix: 16) else { return }
        let next = String(format: "%016llx", UInt64(Int(value) + delta))
        pendingChange = (await clock.now() + delay, next)
    }

    func next() async throws(MusicLaneError) { try await step("next", delta: 1) }
    func previous() async throws(MusicLaneError) { try await step("previous", delta: -1) }
    func togglePlayPause() async throws(MusicLaneError) {
        if let failure { throw failure }
        if let sendFailure { throw sendFailure }
        sent.append("toggle")
        guard let delay = toggleDelay else { return }
        pendingToggle = (await clock.now() + delay, state == .playing ? .paused : .playing)
        await applyPending()
    }
    func seek(to seconds: Double) async throws(MusicLaneError) {
        if let failure { throw failure }
        if let sendFailure { throw sendFailure }
        sent.append("seek"); anchor = (seconds, await clock.now())
    }
}

/// play.track 替身：花指定的時間後回結果
actor FakePlayTrack: PlayTrackRunning {
    private let clock: ManualControlClock
    var duration: Double = 5
    private(set) var requests: [PlayTrackRequest] = []
    var started: [String] { requests.map(\.trackID) }
    var startedAlbums: [String] { requests.map(\.albumID) }
    private(set) var startedAt: [Double] = []

    init(clock: ManualControlClock) { self.clock = clock }

    func play(_ request: PlayTrackRequest, shouldContinue: @escaping @Sendable () -> Bool) async -> PlayTrackOutcome {
        requests.append(request)
        startedAt.append(await clock.now())
        try? await clock.sleep(seconds: duration)
        return .result(PlayResult(outcome: .verified, reason: nil))
    }
}

/// 不阻塞地看受管指令有沒有結束（舊行為會卡住，測試不能 await 它）
final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (ManagedOutcome, Double)?
    func set(_ value: (ManagedOutcome, Double)) { lock.withLock { stored = value } }
    var value: (ManagedOutcome, Double)? { lock.withLock { stored } }
}

final class AliveSet: @unchecked Sendable {
    private let lock = NSLock()
    private var dead: Set<UUID> = []
    func kill(_ id: UUID) { lock.withLock { _ = dead.insert(id) } }
    func isAlive(_ id: UUID) -> Bool { lock.withLock { !dead.contains(id) } }
}

private func event(_ snapshot: MusicSnapshot) -> PlaybackEvent {
    PlaybackEvent(availability: .ok, trackID: snapshot.trackID, albumID: nil, state: snapshot.state,
                  position: snapshot.position, duration: snapshot.duration, sampledAt: 0)
}

private let play = PlayTrackRequest(trackID: "00000000000000aa", albumID: "00000000000000bb")
private func play(_ id: String, album: String = "00000000000000bb") -> PlayTrackRequest { PlayTrackRequest(trackID: id, albumID: album) }

@Suite(.serialized, .timeLimit(.minutes(1))) struct RemoteCommandQueueTests {   // 准入回歸會讓 submit 永遠等不到回覆：卡住改為逾時紅
    let clock = ManualControlClock()
    let alive = AliveSet()
    let target: FakeControlTarget
    let player: FakePlayTrack
    let queue: RemoteCommandQueue
    let ipad = UUID()
    let local = LocalOperationLog()

    init() {
        target = FakeControlTarget(clock: clock)
        player = FakePlayTrack(clock: clock)
        let alive = self.alive
        queue = RemoteCommandQueue(target: target, playTrack: player, clock: clock, event: event, isAlive: { alive.isAlive($0) },
                                   local: local)
    }

    private func submit(_ command: ManagedCommand, from connection: UUID? = nil) -> Task<ManagedOutcome, Never> {
        let queue = self.queue, connection = connection ?? ipad
        return Task { await queue.submit(command, connection: connection) }
    }

    /// 送出並等它進佇列（固定到達順序）
    private func enqueue(_ command: ManagedCommand, from connection: UUID? = nil) async -> Task<ManagedOutcome, Never> {
        let before = await queue.acceptedCount
        let task = submit(command, from: connection)
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        return task
    }

    /// thecure 2026-10-18（N-01）：看到換曲就回覆（0.1 s 一讀），不再多等 1 s；1 s 改為佇列的送出間隔
    @Test func nextRepliesAsSoonAsTheChangeIsSeen() async {
        let queue = self.queue, clock = self.clock, ipad = self.ipad
        let task = Task { (await queue.submit(.next, connection: ipad), await clock.time) }
        _ = await eventually { await queue.acceptedCount > 0 }
        await clock.settle()
        await clock.advance(to: 3)
        let (outcome, at) = await task.value
        guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return }
        #expect(result.outcome == .applied && result.playback.trackID == "0000000000000002")
        #expect(at >= 0.4 && at < 0.55)     // 0.4 換曲，下一次 0.1 s 讀回就回覆
    }

    /// 回覆提早，但下一個受管指令仍要等到「換曲觀測＋1 s」才送給 Music（B2 的保護不變）
    @Test func nextCommandIsHeldUntilSettleAfterEarlyReply() async {
        let first = await enqueue(.next)
        let second = await enqueue(.next)
        await clock.advance(to: 6)
        _ = await first.value
        _ = await second.value
        let times = await target.sentAt
        #expect(times.count == 2)
        #expect(times.count == 2 && times[1] >= times[0] + 0.4 + PlaybackLimits.gateSettle - 0.05)
    }

    /// 點歌也一樣被擋到 settle 結束
    @Test func playTrackIsHeldUntilSettleAfterEarlyReply() async {
        let first = await enqueue(.next)
        let play = await enqueue(.playTrack(play("00000000000000a1")))
        await clock.advance(to: 10)
        _ = await first.value
        _ = await play.value
        let started = await player.startedAt
        #expect(started.count == 1 && started[0] >= 0.4 + PlaybackLimits.gateSettle - 0.05)
    }

    /// settle 期間執行中那筆的預約仍保留：再收 3 筆等待，第 4 筆 busy
    @Test func reservationIsHeldDuringSettle() async {
        let replied = Flag(false)
        let queue = self.queue, ipad = self.ipad
        let first = Task { let outcome = await queue.submit(.next, connection: ipad); replied.set(true); return outcome }
        _ = await eventually { await queue.acceptedCount > 0 }
        await clock.settle()
        await clock.advance(to: 0.6)                                   // 已回覆、仍在 settle
        #expect(replied.value)
        let waiting = [await enqueue(.next), await enqueue(.next), await enqueue(.next)]
        #expect(await submit(.next).value == .error(.busy))
        await clock.advance(to: 30)
        _ = await first.value
        for task in waiting { if case .error = await task.value { Issue.record("accepted one failed") } }
    }

    /// 未生效＝即刻放行，不等 settle
    @Test func notAppliedReleasesTheQueueImmediately() async {
        await target.set(changeDelay: nil)
        let first = await enqueue(.next)
        let second = await enqueue(.next)
        await clock.advance(to: 7)
        _ = await first.value
        _ = await second.value
        let times = await target.sentAt
        #expect(times.count == 2 && times[1] - times[0] < PlaybackLimits.gateNoChangeDeadline + 0.2)
    }

    @Test func unchangedForThreeSecondsIsNotAppliedAndQueueContinues() async {
        await target.set(changeDelay: nil)
        let first = await enqueue(.next)
        let second = await enqueue(.previous)
        await clock.advance(to: 3.1)
        guard case .control(let r1) = await first.value else { Issue.record("first"); return }
        #expect(r1.outcome == .notApplied && r1.playback.trackID == "0000000000000001")
        await clock.advance(to: 6.5)
        guard case .control(let r2) = await second.value else { Issue.record("second"); return }
        #expect(r2.outcome == .notApplied)
        #expect(await target.sent == ["next", "previous"])
    }

    @Test func fifoWithoutMergingEachGetsItsOwnResult() async {
        let tasks = [await enqueue(.next), await enqueue(.next), await enqueue(.previous)]
        await clock.advance(to: 20)
        let ids = await tasks.asyncMap { task -> String? in
            if case .control(let r) = await task.value { r.playback.trackID } else { nil }
        }
        #expect(ids == ["0000000000000002", "0000000000000003", "0000000000000002"])
        #expect(await target.sent == ["next", "next", "previous"])
    }

    @Test func fourthWaiterIsBusy() async {
        let running = await enqueue(.next)
        let waiting = [await enqueue(.next), await enqueue(.next), await enqueue(.next)]
        let rejected = await submit(.next).value
        #expect(rejected == .error(.busy))
        await clock.advance(to: 40)
        for task in [running] + waiting { if case .error = await task.value { Issue.record("accepted one failed") } }
    }

    @Test func pendingPlayTrackIsSupersededByNewerOne() async {
        let running = await enqueue(.playTrack(play("00000000000000a1")))
        let old = await enqueue(.playTrack(play("00000000000000a2")))
        let newer = await enqueue(.playTrack(play("00000000000000a3")))
        #expect(await old.value == .error(.superseded))
        await clock.advance(to: 20)
        _ = await running.value
        _ = await newer.value
        #expect(await player.started == ["00000000000000a1", "00000000000000a3"])
    }

    /// PRD §6-5「連點兩張專輯」（S7 T9 追溯缺口）：點了 A 專輯的歌、還在跑時連點 B、C 專輯——C 取代 B，最後播的是 C 專輯，
    /// 中途不會出現 B 專輯（取代與專輯無關，以不同 albumID 明證）
    @Test func rapidPicksAcrossAlbumsEndOnTheLastAlbum() async {
        let running = await enqueue(.playTrack(play("00000000000000a1", album: "000000000000aaaa")))
        let second = await enqueue(.playTrack(play("00000000000000b1", album: "000000000000bbbb")))
        let third = await enqueue(.playTrack(play("00000000000000c1", album: "000000000000cccc")))
        #expect(await second.value == .error(.superseded))
        await clock.advance(to: 20)
        _ = await running.value
        _ = await third.value
        #expect(await player.startedAlbums == ["000000000000aaaa", "000000000000cccc"])
    }

    /// 准入預算 80 s：執行中 play.track（36）＋等待中 play.track（36）＋next（11）＝83 → next 回 busy（simcodex R2 LOW-1）；
    /// 再一個 play.track 取代等待中那筆（預約重算仍 72）准入
    @Test func admissionBudgetRejectsLateNextButLetsPlayTrackSupersede() async {
        let running = await enqueue(.playTrack(play("00000000000000a1")))
        let pending = await enqueue(.playTrack(play("00000000000000a2")))
        #expect(await submit(.next).value == .error(.busy))
        let replacement = await enqueue(.playTrack(play("00000000000000a3")))
        #expect(await pending.value == .error(.superseded))
        await clock.advance(to: 60)
        _ = await running.value
        _ = await replacement.value
        #expect(await player.started == ["00000000000000a1", "00000000000000a3"])
    }

    /// simcodex R2 LOW-1 後仍成立：執行中 next（11）時點歌，等待中的 play.track 只會有一筆（新的取代舊的，11＋36＝47 ≤ 80）
    @Test func runningNextStillAdmitsAPlayTrackThatSupersedesThePendingOne() async {
        await target.set(changeDelay: nil)
        let running = await enqueue(.next)
        let pending = await enqueue(.playTrack(play("00000000000000b1")))
        let replacement = await enqueue(.playTrack(play("00000000000000b2")))
        #expect(await pending.value == .error(.superseded))
        await clock.advance(to: 60)
        _ = await running.value
        _ = await replacement.value
        #expect(await player.started == ["00000000000000b2"])
    }

    // MARK: 上一首回到本曲開頭（#4-1 真機：Music 的 previous track 播數秒後先回開頭；thecure 2026-10-18 定案）

    /// 送出受管指令、把時間推過最長期限（約 4 s），回傳結果與回覆時刻（舊行為不會卡住、而是斷言失敗）
    private func gated(_ command: ManagedCommand) async -> (ControlResult?, Double) {
        let before = await queue.acceptedCount
        let queue = self.queue, clock = self.clock, ipad = self.ipad
        let task = Task { (await queue.submit(command, connection: ipad), await clock.time) }
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        await clock.advance(to: 4.6)
        let (outcome, at) = await task.value
        guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return (nil, at) }
        return (result, at)
    }

    /// 同一首、進度明顯倒回＝候補；settle 中持續成立 1 s＝applied（不等 3 s）
    @Test func previousRewindWithinTrackIsApplied() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 0.3, position: 0.3)
        let (result, at) = await gated(.previous)
        #expect(result?.outcome == .applied && result?.playback.trackID == "0000000000000001")
        #expect(at < PlaybackLimits.gateNoChangeDeadline)
    }

    /// 暫停中也一樣：期望位置＝送出前的位置
    @Test func pausedPreviousRewindIsApplied() async {
        await target.set(changeDelay: nil)
        await target.set(state: .paused)
        await target.set(position: 12)
        await target.schedule(at: 0.3, position: 0)
        let (result, _) = await gated(.previous)
        #expect(result?.outcome == .applied)
    }

    /// 單發的 0（讀不到進度）下一次讀回又回到原位置＝取消候補，3 s 內沒有變化＝notApplied
    @Test func singleZeroReadThatRecoversIsNotApplied() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 0.4, position: 0)
        await target.schedule(at: 0.9, position: 13)
        let (result, at) = await gated(.previous)
        #expect(result?.outcome == .notApplied)
        #expect(at >= PlaybackLimits.gateNoChangeDeadline)
    }

    /// 送出前沒有目前曲（trackID nil）：不當候補
    @Test func noTrackBeforeIsNeverARewind() async {
        await target.set(changeDelay: nil)
        await target.set(trackID: nil)
        await target.set(position: 12)
        await target.schedule(at: 0.3, position: 0)
        let (result, _) = await gated(.previous)
        #expect(result?.outcome == .notApplied)
    }

    /// 候補中讀到空 ID：略過（不確定也不取消），之後恢復同一首＝照常 applied
    @Test func nilTrackDuringRewindSettleIsSkipped() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 0.3, position: 0.3)
        await target.schedule(at: 0.8, position: 0.8, trackID: .some(nil))
        await target.schedule(at: 1.3, position: 1.3, trackID: "0000000000000001")
        let (result, at) = await gated(.previous)
        #expect(result?.outcome == .applied)
        #expect(abs(at - 1.3) < 0.01)   // 0.1 s 一讀：0.3 候補、0.8–1.2 空 ID 略過、1.3 確認滿 1 s（不是把空 ID 當換歌）
    }

    /// 期限前看到候補、期限後被取消＝立刻 notApplied（最長約 4 s，有界）
    @Test func rewindCancelledAfterDeadlineIsNotAppliedImmediately() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 2.5, position: 0)       // 期限前立候補
        await target.schedule(at: 3.2, position: 15)      // 期限後、未滿 1 s 被取消
        let (result, at) = await gated(.previous)
        #expect(result?.outcome == .notApplied)
        #expect(abs(at - 3.2) < 0.01)                     // 取消的那一次讀回就回覆，不再等
    }

    /// S4 後半 security MEDIUM-1：倒回候補後 Music 一直回報沒有目前曲——閘門不得無限讀下去，
    /// 最長「3 s 期限＋確認所需的 gateSettle」就 notApplied、放行佇列
    @Test func rewindCandidateFollowedByNoTrackEndsAtTheHardCap() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 0.3, position: 0.3)
        await target.schedule(at: 0.8, trackID: .some(nil))
        let queue = self.queue, clock = self.clock, ipad = self.ipad
        let finished = OutcomeBox()
        let before = await queue.acceptedCount
        let task = Task {
            let outcome = await queue.submit(.previous, connection: ipad)
            finished.set((outcome, await clock.time))
        }
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        await clock.advance(to: 4.6)
        let done = await eventually { finished.value != nil }
        #expect(done)
        if let (outcome, at) = finished.value {
            guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return }
            #expect(result.outcome == .notApplied)
            #expect(abs(at - (PlaybackLimits.gateNoChangeDeadline + PlaybackLimits.gateSettle)) < 0.11)
        } else {
            await target.schedule(at: 5, trackID: "0000000000000001")   // 舊行為的收尾：讓卡住的閘門結束
            await clock.advance(to: 7)
        }
        await task.value
    }

    /// security MEDIUM-1：等換曲期間連線斷了＝不再讀 Music、立刻結束（.dropped）
    @Test func deadConnectionDuringGateStopsReading() async {
        await target.set(changeDelay: nil)
        let task = await enqueue(.next)
        await clock.advance(to: 0.5)
        alive.kill(ipad)
        await clock.advance(to: 4.6)
        #expect(await task.value == .dropped)
    }

    // MARK: 期限自送出起算（Codex S4 後半 P2；設計 §4.4 原文「自送出起 3 s」）

    /// Music 忙、指令花 1.5 s 才送完，送完後 2 s 換曲：仍在「送出後 3 s」內＝applied（舊行為在 3.0 s 判 notApplied）
    @Test func slowSendStillGetsTheFullDeadlineToSeeTheChange() async {
        await target.set(sendDelay: 1.5)
        await target.set(changeDelay: 2.0)
        let (result, at) = await gated(.next)
        #expect(result?.outcome == .applied)
        #expect(abs(at - 3.5) < 0.11)
    }

    /// 讀回暫時失敗（AE 逾時等）時繼續等，這個「還在期限內」也自送完起算：送出 1.5 s、1.6–3.2 s 讀回失敗、之後看到換曲＝applied
    /// （舊行為：自送出前起算，3.0 s 後的失敗直接回錯誤）
    @Test func failedReadsAfterSlowSendKeepWaitingUntilTheDeadlineFromDispatch() async {
        await target.set(sendDelay: 1.5)
        await target.set(changeDelay: 0.5)
        await target.set(failingReads: 1.6..<3.2)
        let (result, _) = await gated(.next)
        #expect(result?.outcome == .applied)
    }

    /// simcodex R2 Codex P2：送出後每次讀回都失敗到期限＝回讀取錯誤，不得假裝成 notApplied（附送出前的舊狀態）
    @Test func readsThatAllFailUntilTheDeadlineReportTheReadError() async {
        await target.set(changeDelay: nil)
        await target.set(failingReads: 0.05..<10)
        let queue = self.queue, clock = self.clock, ipad = self.ipad
        let before = await queue.acceptedCount
        let task = Task { await queue.submit(.next, connection: ipad) }
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        await clock.advance(to: 4.6)
        #expect(await task.value == .error(.busy))
    }

    /// 同上（Codex 第 1 項修改）：讀成功過一次、之後一直失敗＝到期限回 notApplied＋最後一次讀到的狀態，不是讀取錯誤
    @Test func readsThatFailAfterOneSuccessEndAsNotAppliedWithTheLastRead() async {
        await target.set(changeDelay: nil)
        await target.set(failingReads: 0.15..<10)
        let (result, _) = await gated(.next)
        #expect(result?.outcome == .notApplied && result?.playback.trackID == "0000000000000001")
    }

    /// 同上：上一首看到倒回候補後讀回一直失敗＝讀到硬上限（3 s＋gateSettle）才以最後一次讀到的狀態回 notApplied
    @Test func readsThatFailAfterARewindCandidateWaitForTheHardCap() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 0.3, position: 0.3)
        await target.set(failingReads: 0.45..<10)
        let (result, at) = await gated(.previous)
        #expect(result?.outcome == .notApplied)
        #expect(at >= PlaybackLimits.gateNoChangeDeadline + PlaybackLimits.gateSettle)
    }

    /// Codex（2026-10-19 第 2 輪）：讀回很慢時，「要不要結束」要用讀完的時刻判斷，否則期限前開始的讀回結束後還會再多讀一輪、
    /// 超過設計 §4.4 的上界。每次讀回 1.9 s：0.1–2.0、2.1–4.0（期限前開始、沒變）→ 讀完已過 3 s＝4.0 s 就 notApplied（舊行為再讀一輪到 6.0）
    @Test func slowReadsStopAtTheFirstReadThatEndsPastTheDeadline() async {
        await target.set(changeDelay: nil)
        let queue = self.queue, clock = self.clock, ipad = self.ipad
        let finished = OutcomeBox()
        let before = await queue.acceptedCount
        let task = Task {
            let outcome = await queue.submit(.next, connection: ipad)
            finished.set((outcome, await clock.time))
        }
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        await target.set(readDelay: 1.9)   // 送出前的那一次讀回不算（已在 0 s 完成）
        await clock.advance(to: 7)
        #expect(await eventually { finished.value != nil })
        if let (outcome, at) = finished.value {
            guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return }
            #expect(result.outcome == .notApplied)
            #expect(abs(at - 4.0) < 0.11)
        }
        await task.value
    }

    /// Codex（2026-10-19 第 3 輪）：倒回候補後的確認讀回也不得越過上界——過了硬上限就不再開新的讀回。
    /// 讀回很慢（每次 1.22 s）時，倒回路徑的回覆時刻仍在硬上限內。
    /// 註：用替身沒能重現「確認讀回在硬上限後才開始」的時序（實測 3.96 s 即 applied），此條為上界的特性測試；
    /// 迴圈開頭的硬上限檢查以推理保證（最後一次讀回必在上限前開始）
    @Test func slowReadsDoNotStartAConfirmingReadPastTheHardCap() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 2.6, position: 0.3)
        let queue = self.queue, clock = self.clock, ipad = self.ipad
        let finished = OutcomeBox()
        let before = await queue.acceptedCount
        let task = Task {
            let outcome = await queue.submit(.previous, connection: ipad)
            finished.set((outcome, await clock.time))
        }
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        await target.set(readDelay: 1.22)
        await clock.advance(to: 7)
        #expect(await eventually { finished.value != nil })
        if let (_, at) = finished.value {
            #expect(at <= PlaybackLimits.gateNoChangeDeadline + PlaybackLimits.gateSettle + 0.11)
        }
        await task.value
    }

    /// 倒回判斷的「照常播放應到的位置」仍從送出前起算（送出那段時間歌也在播）：
    /// 1.3 s 讀到 11.5——自送出前起算應在 13.3（11.5＋容差 1＜13.3＝倒回），若誤從送完起算只應在 12.3（不算倒回）
    @Test func slowSendPreviousRewindIsStillApplied() async {
        await target.set(changeDelay: nil)
        await target.set(sendDelay: 1.0)
        await target.set(position: 12)
        await target.schedule(at: 1.3, position: 11.5)
        let (result, _) = await gated(.previous)
        #expect(result?.outcome == .applied)
    }

    /// 硬上限也自送出起：送出 1 s＋4 s＝5 s
    @Test func hardCapCountsFromDispatch() async {
        await target.set(changeDelay: nil)
        await target.set(sendDelay: 1.0)
        await target.set(position: 12)
        await target.schedule(at: 1.3, position: 0.3)
        await target.schedule(at: 1.8, trackID: .some(nil))
        let queue = self.queue, clock = self.clock, ipad = self.ipad
        let finished = OutcomeBox()
        let before = await queue.acceptedCount
        let task = Task {
            let outcome = await queue.submit(.previous, connection: ipad)
            finished.set((outcome, await clock.time))
        }
        _ = await eventually { await queue.acceptedCount > before }
        await clock.settle()
        await clock.advance(to: 5.6)
        #expect(await eventually { finished.value != nil })
        if let (outcome, at) = finished.value {
            guard case .control(let result) = outcome else { Issue.record("\(outcome)"); return }
            #expect(result.outcome == .notApplied)
            #expect(abs(at - 5.0) < 0.11)
        }
        await task.value
    }

    /// 下一首不適用倒回判定
    @Test func nextDoesNotTreatRewindAsApplied() async {
        await target.set(changeDelay: nil)
        await target.set(position: 12)
        await target.schedule(at: 0.3, position: 0)
        let (result, _) = await gated(.next)
        #expect(result?.outcome == .notApplied)
    }

    /// #4-1 N-01 診斷：閘門一行只記方向、判定路徑與兩段毫秒（送出、送出 → 看到變化）
    @Test func gateTraceLineHasPathAndMilliseconds() {
        #expect(RemoteCommandQueue.gateLine(forward: false, path: "changed", sendSeconds: 0.0123, detectSeconds: 0.4567)
                == "gate dir=previous path=changed sendMs=12 detectMs=457")
    }

    @Test func toggleAndSeekAreNotGated() async {
        let gated = await enqueue(.next)
        let toggle = await queue.toggle()
        guard case .success(let result) = toggle else { Issue.record("\(toggle)"); return }
        #expect(result.outcome == .applied && result.playback.state == .paused)
        await clock.advance(to: 2)
        _ = await gated.value
    }

    /// #4-1 真機：Music 晚 0.3 s 才變成暫停——不得立刻判「沒有生效」，要等讀回看到改變
    @Test func toggleWaitsForDelayedStateChange() async {
        await target.set(toggleDelay: 0.3)
        let task = Task { await queue.toggle() }
        await clock.advance(to: 0.5)
        guard case .success(let result) = await task.value else { Issue.record("toggle"); return }
        #expect(result.outcome == .applied && result.playback.state == .paused)
        let recorded = await local.recent(now: await clock.time).map(\.operation)
        #expect(recorded == [.toggle(stateAfter: .paused)])
    }

    /// CR-016：真機 Music 偶發 1.1–1.2 s 才起播——1 s 判 notApplied 會誤報；2 s 內看到改變＝applied
    @Test func toggleSeesStateChangeAfterOneAndAHalfSeconds() async {
        await target.set(toggleDelay: 1.5)
        let task = Task { await queue.toggle() }
        await clock.advance(to: 1.7)
        guard case .success(let result) = await task.value else { Issue.record("toggle"); return }
        #expect(result.outcome == .applied && result.playback.state == .paused)
    }

    /// security LOW-2：上一次播放／暫停還在讀回時再按＝busy（不再送第二個 playpause，免得互相翻回、讀回量加倍）
    @Test func secondToggleWhileReadingBackIsBusy() async {
        await target.set(toggleDelay: nil)
        let first = Task { await queue.toggle() }
        _ = await eventually { await target.sent == ["toggle"] }
        await clock.settle()
        let second = Task { await queue.toggle() }   // 舊行為會送第二個 playpause 並在手動時鐘上睡，不能直接 await
        _ = await eventually { await target.sent.count >= 2 }
        await clock.settle()
        await clock.advance(to: 2.2)
        #expect(await second.value == .failure(.busy))
        #expect(await target.sent == ["toggle"])
        _ = await first.value
        await target.set(toggleDelay: 0)
        guard case .success = await queue.toggle() else { Issue.record("third toggle"); return }   // 讀回結束後照常可按
    }

    /// 2 s 內都沒變才判 notApplied（附讀回狀態；CR-016）
    @Test func toggleUnchangedForTwoSecondsIsNotApplied() async {
        await target.set(toggleDelay: nil)
        let task = Task { (await queue.toggle(), await clock.time) }   // 回覆時刻：不得早於期限
        await clock.advance(to: 1.9)
        await clock.advance(to: 2.2)
        let (toggle, answeredAt) = await task.value
        guard case .success(let result) = toggle else { Issue.record("toggle"); return }
        #expect(result.outcome == .notApplied && result.playback.state == .playing)
        #expect(answeredAt >= PlaybackLimits.toggleReadbackDeadline)
    }

    /// 真機 N-01（2026-10-19 14:43:59）：點歌驗證佇列時 iPad 按暫停，狀態機在 toggle 讀回結束前就看到「暫停」，
    /// 本地紀錄還沒有這筆 → 判手動、終止捷徑並隔離。送出前先登記預期效果（在途意圖），讀回期間就能解釋（simcodex R2 第 5 項，Codex 設計）
    @Test func toggleIntentIsVisibleWhileReadingBack() async {
        await target.set(toggleDelay: 0.3)
        let task = Task { await queue.toggle() }
        _ = await eventually { await target.sent == ["toggle"] }
        await clock.settle()
        let during = await local.recent(now: await clock.time).map(\.operation)
        #expect(during == [.toggle(stateAfter: .paused)])
        await clock.advance(to: 0.5)
        _ = await task.value
        #expect(await local.recent(now: await clock.time).map(\.operation) == [.toggle(stateAfter: .paused)])   // 確認後只留一筆
    }

    /// 2 s 都沒變（notApplied）＝撤銷在途意圖：之後 Mac 上真的手動暫停不得被它背書
    @Test func notAppliedToggleRevokesItsIntent() async {
        await target.set(toggleDelay: nil)
        let task = Task { await queue.toggle() }
        await clock.advance(to: 1.9)
        await clock.advance(to: 2.2)
        _ = await task.value
        #expect(await local.recent(now: await clock.time).isEmpty)
    }

    /// 指令本身失敗＝撤銷在途意圖（toggle 與 seek）
    @Test func failedSendRevokesTheIntent() async {
        await target.set(sendFailure: .failed(code: -1712))
        #expect(await queue.toggle() == .failure(.busy))
        _ = await queue.seek(SeekRequest(trackID: "0000000000000001", seconds: 30))
        #expect(await local.recent(now: await clock.time).isEmpty)
    }

    /// 已執行的 toggle／seek 記進本地操作紀錄（點歌狀態機用來區分 iPad 操作與 Mac 上的手動操作，§4.5）
    @Test func appliedToggleAndSeekAreRecordedAsLocalOperations() async {
        _ = await queue.toggle()
        _ = await queue.seek(SeekRequest(trackID: "0000000000000001", seconds: 42))
        let recorded = await local.recent(now: await clock.time).map(\.operation)
        #expect(recorded == [.toggle(stateAfter: .paused), .seek(positionAfter: 42)])
    }

    @Test func seekOnAnotherTrackIsNotApplied() async {
        let result = await queue.seek(SeekRequest(trackID: "00000000000000ff", seconds: 5))
        guard case .success(let control) = result else { Issue.record("\(result)"); return }
        #expect(control.outcome == .notApplied)
        #expect(await target.sent.isEmpty)
    }

    @Test func seekBeyondDurationIsNotApplied() async {
        let result = await queue.seek(SeekRequest(trackID: "0000000000000001", seconds: 999))
        guard case .success(let control) = result else { Issue.record("\(result)"); return }
        #expect(control.outcome == .notApplied)
    }

    @Test func seekOnCurrentTrackApplies() async {
        let result = await queue.seek(SeekRequest(trackID: "0000000000000001", seconds: 42))
        guard case .success(let control) = result else { Issue.record("\(result)"); return }
        #expect(control.outcome == .applied && control.playback.position == 42)
    }

    @Test func deadConnectionsPendingCommandIsDroppedAndOthersRun() async {
        let other = UUID()
        let running = await enqueue(.next)
        let doomed = await enqueue(.next)
        let kept = await enqueue(.next, from: other)
        alive.kill(ipad)
        await clock.advance(to: 20)
        _ = await running.value
        #expect(await doomed.value == .dropped)
        guard case .control = await kept.value else { Issue.record("kept"); return }
        #expect(await target.sent == ["next", "next"])
    }

    @Test(arguments: [(MusicLaneError.notRunning, ErrorCode.musicNotRunning), (.notAuthorized, .musicNotAuthorized)])
    func laneErrorsMapToProtocolErrors(failure: MusicLaneError, code: ErrorCode) async {
        await target.set(failure: failure)
        #expect(await submit(.next).value == .error(code))
        #expect(await queue.toggle() == .failure(code))
    }
}

/// 准入的純模型：可枚舉（§4.4 Codex 第 3 輪 P2-2）
struct ManagedAdmissionTests {
    /// 對所有長度 ≤ 4 的 kind 序列（每次都在 t=0 入列，最壞情況），檢查：預約 ≤ 入列＋80、等待存活者 ≤ 3、取代後預約只會變早
    @Test func exhaustiveSequencesKeepInvariants() {
        let kinds: [ManagedKind] = [.nextPrevious, .playTrack, .genius]   // .genius：CR-030
        var sequences: [[ManagedKind]] = [[]]
        for _ in 0..<5 { sequences += sequences.flatMap { s in kinds.map { s + [$0] } }.filter { $0.count <= 5 } }
        for sequence in Set(sequences.map { $0.map(\.rawValue) }).map({ $0.compactMap(ManagedKind.init) }) {
            var admission = ManagedAdmission()
            for (index, kind) in sequence.enumerated() {
                let before = admission.reservations
                let decision = admission.admit(kind, now: 0, id: UUID())
                switch decision {
                case .accepted(_, let superseded):
                    #expect(admission.reservations.allSatisfy { $0.deadline <= 0 + PlaybackLimits.managedAdmissionBudget })
                    #expect(admission.waitingCount <= PlaybackLimits.maxPendingManaged)
                    if superseded != nil {
                        let oldMax = before.map(\.deadline).max() ?? 0
                        #expect((admission.reservations.map(\.deadline).max() ?? 0) <= oldMax + 0.0001, "\(sequence) at \(index)")
                    }
                case .rejected:
                    #expect(admission.reservations == before)
                }
            }
        }
    }

    @Test func runningKeepsItsReservationWhileWaitersAccumulate() {
        var admission = ManagedAdmission()
        let firstID = UUID()
        guard case .accepted(let first, nil) = admission.admit(.nextPrevious, now: 0, id: firstID) else { Issue.record("first"); return }
        #expect(first == PlaybackLimits.worstNextPrevious)
        admission.start(firstID)   // 執行中者保留原預約
        guard case .accepted(let second, nil) = admission.admit(.playTrack, now: 1, id: UUID()) else { Issue.record("second"); return }
        #expect(second == PlaybackLimits.worstNextPrevious + PlaybackLimits.worstPlayTrack)
        // 還沒開始的等待者，最壞也只能從「現在」起算：時間過去，它的預約跟著往後
        guard case .accepted(let third, nil) = admission.admit(.nextPrevious, now: 50, id: UUID()) else { Issue.record("third"); return }
        #expect(third == 50 + PlaybackLimits.worstPlayTrack + PlaybackLimits.worstNextPrevious)
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var result: [T] = []
        for element in self { result.append(await transform(element)) }
        return result
    }
}
#endif
