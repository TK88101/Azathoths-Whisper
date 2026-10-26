#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T7（sprint-4-detail.md §4.5、§4.9 #7–#12；CR-005、CR-014）：play.track 狀態機。時間全用手動時鐘

private let album = "00000000000000bb"
private let t1 = "0000000000000001", t2 = "0000000000000002", t3 = "0000000000000003", other = "00000000000000ff"
private let albumPlan = ShortcutPlan(album: "Album", albumArtist: "", artist: "Someone", order: [t1, t2, t3])
private let request = PlayTrackRequest(trackID: t2, albumID: album)
private let bound = ShortcutIdentifier("8CF4FBAD-400E-412D-A7BA-D3BC9D2939CF")!

actor FakePlans: PlayPlanProviding {
    var result: Result<AdmissionResult, ErrorCode> = .success(.admitted(albumPlan))
    func set(_ value: Result<AdmissionResult, ErrorCode>) { result = value }
    private(set) var calls = 0
    func plan(for request: PlayTrackRequest) async -> Result<AdmissionResult, ErrorCode> { calls += 1; return result }
}

actor FakeBindingStatus: ShortcutBindingChecking {
    var value: ShortcutBindingStatus = .bound(bound)
    private(set) var calls = 0
    /// 查詢期間發生的事（例如中繼被關掉）
    var onStatus: (@Sendable () -> Void)?
    func set(_ status: ShortcutBindingStatus) { value = status }
    func set(onStatus hook: (@Sendable () -> Void)?) { onStatus = hook }
    func status() async -> ShortcutBindingStatus { calls += 1; onStatus?(); return value }
}

/// 可控的捷徑子行程：測試決定何時結束、結束碼；也記錄是否被終止
final class ScriptedRun: LaunchedProcess, @unchecked Sendable {
    let lock = NSLock()
    private var exit: ProcessExit?
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []
    private(set) var terminated = false

    func finish(_ code: Int32?) {
        let (value, pending) = lock.withLock { () -> (ProcessExit, [CheckedContinuation<ProcessExit, Never>]) in
            let value = ProcessExit(code: code, stdout: Data(), stderrNonEmpty: false)
            exit = value
            defer { waiters = [] }
            return (value, waiters)
        }
        pending.forEach { $0.resume(returning: value) }
    }

    func waitForExit() async -> ProcessExit {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> ProcessExit? in
                if let exit { return exit }
                waiters.append(continuation)
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    func terminate() {
        lock.withLock { terminated = true }
        finish(nil)
    }
}

final class FakeStarter: ShortcutStarting, @unchecked Sendable {
    let lock = NSLock()
    private(set) var started: [(ShortcutIdentifier, ShortcutInput)] = []
    var runs: [ScriptedRun] = []
    var failLaunch = false
    var onStart: (@Sendable () -> Void)?

    func start(_ shortcut: ShortcutIdentifier, input: ShortcutInput) -> RunningShortcut? {
        guard !failLaunch else { return nil }
        let run = ScriptedRun()
        lock.withLock { started.append((shortcut, input)); runs.append(run) }
        onStart?()
        return RunningShortcut(process: run, directory: FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID())"))
    }
    var last: ScriptedRun? { lock.withLock { runs.last } }
    var startCount: Int { lock.withLock { started.count } }
}

/// Music 替身：依時間表回報；playOnce 讓目標曲在 0.3 s 後到達
actor ScriptedMusic: PlayTarget {
    private let clock: ManualControlClock
    /// (自何時起, 狀態)；後者覆蓋前者
    private var timeline: [(at: Double, snapshot: MusicSnapshot)]
    private(set) var playOnceCalls: [String] = []
    /// 讀狀態的次數（「回覆之後不再為這筆請求動 Music」的斷言用）
    private(set) var reads = 0
    var playOnceFinds = true

    init(clock: ManualControlClock, initial: MusicSnapshot) {
        self.clock = clock
        timeline = [(0, initial)]
    }

    func at(_ time: Double, _ snapshot: MusicSnapshot) { timeline.append((time, snapshot)); timeline.sort { $0.at < $1.at } }
    func set(playOnceFinds value: Bool) { playOnceFinds = value }
    /// 換掉起始狀態（點歌前 Music 正在播什麼）
    func set(initial: MusicSnapshot) { timeline[0] = (0, initial) }

    func snapshot() async throws(MusicLaneError) -> MusicSnapshot {
        reads += 1
        let now = await clock.now()
        var current = timeline[0].snapshot
        for entry in timeline where entry.at <= now {
            var snap = entry.snapshot
            // 播放中的位置隨時間前進
            if snap.state == .playing { snap = MusicSnapshot(state: .playing, trackID: snap.trackID, duration: snap.duration,
                                                             position: snap.position + (now - entry.at)) }
            current = snap
        }
        return current
    }

    func playOnce(trackID: String) async throws(MusicLaneError) -> Bool {
        playOnceCalls.append(trackID)
        guard playOnceFinds else { return false }
        let now = await clock.now()
        at(now + 0.3, MusicSnapshot(state: .playing, trackID: trackID, duration: 200, position: 0))
        return true
    }

    func next() async throws(MusicLaneError) {}
    func previous() async throws(MusicLaneError) {}
    func togglePlayPause() async throws(MusicLaneError) {}
    func seek(to seconds: Double) async throws(MusicLaneError) {}
}

/// Queue.dat 替身：依時間表回報 ID 序列
actor ScriptedQueue: QueueReading {
    private let clock: ManualControlClock
    private var timeline: [(at: Double, ids: [String]?)] = [(0, ["00000000000000a0"])]
    init(clock: ManualControlClock) { self.clock = clock }
    func at(_ time: Double, _ ids: [String]?) { timeline.append((time, ids)); timeline.sort { $0.at < $1.at } }
    func read() async -> [String]? {
        let now = await clock.now()
        return timeline.last { $0.at <= now }?.ids
    }
}

final class ArrivalLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []
    func append(_ v: String?) { lock.withLock { values.append(v) } }
    var all: [String?] { lock.withLock { values } }
}

private func snap(_ id: String?, _ state: PlaybackState = .playing, position: Double = 0) -> MusicSnapshot {
    MusicSnapshot(state: state, trackID: id, duration: 200, position: position)
}

@Suite(.serialized) struct PlayTrackMachineTests {
    let clock = ManualControlClock()
    let plans = FakePlans()
    let binding = FakeBindingStatus()
    let starter = FakeStarter()
    let music: ScriptedMusic
    let queue: ScriptedQueue
    let local = LocalOperationLog()
    let arrivals = ArrivalLog()
    let machine: PlayTrackMachine

    init() {
        music = ScriptedMusic(clock: clock, initial: snap(other, position: 30))
        queue = ScriptedQueue(clock: clock)
        let arrivals = self.arrivals
        machine = PlayTrackMachine(plans: plans, binding: binding, starter: starter, music: music, queue: queue, clock: clock,
                                   local: local, onArrival: { arrivals.append($0.trackID) })
    }

    private func run(until end: Double = 60) async -> PlayTrackOutcome {
        let machine = self.machine
        let task = Task { await machine.play(request) }
        await clock.settle()
        await clock.advance(to: end)
        return await task.value
    }

    /// 捷徑在 1.2 s 讓目標曲開播、1.3 s 結束，佇列 1.5 s 起＝期待序列
    private func scriptHappyShortcut(arrival: Double = 1.2, exitCode: Int32? = 0, exitAt: Double = 1.3) async {
        let starter = self.starter, clock = self.clock
        await music.at(arrival, snap(t2))
        await queue.at(1.5, [t2, t3])
        starter.onStart = {
            Task {
                while await clock.time < exitAt { try? await Task.sleep(for: .milliseconds(1)) }
                starter.last?.finish(exitCode)
            }
        }
    }

    @Test func happyPathIsVerifiedAndAnnouncesArrivalOnce() async {
        await scriptHappyShortcut()
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
        #expect(arrivals.all == [t2])
        let input = try? #require(starter.started.first?.1)
        #expect(input?.position == 2 && input?.expectedCount == 3)
        #expect(await music.playOnceCalls.isEmpty)
    }

    /// security review MEDIUM-1：還沒對 Music 做任何事之前連線就不在了（中繼關閉、iPad 被撤銷）——不啟捷徑、不降級點歌
    @Test func goneBeforeStartingShortcutTouchesNothing() async {
        let alive = Flag(true)
        await binding.set(onStatus: { alive.set(false) })
        let machine = self.machine
        let task = Task { await machine.play(request, shouldContinue: { alive.value }) }
        await clock.settle()
        await clock.advance(to: 60)
        #expect(await task.value == .abandoned)
        let plays = await music.playOnceCalls
        #expect(starter.startCount == 0 && plays.isEmpty)
    }

    @Test func goneBeforeDegradingNeverPlaysOnce() async {
        await plans.set(.success(.refused(.gateAmbiguousTitle)))
        #expect(await machine.play(request, shouldContinue: { false }) == .abandoned)
        #expect(await music.playOnceCalls.isEmpty)
    }

    @Test func gateRefusalDegradesWithoutRunningShortcut() async {
        await plans.set(.success(.refused(.gateAmbiguousTitle)))
        #expect(await run() == .result(PlayResult(outcome: .degraded, reason: .gateAmbiguousTitle)))
        #expect(starter.startCount == 0)
        #expect(await music.playOnceCalls == [t2])
    }

    @Test func missingShortcutDegrades() async {
        await binding.set(.missing)
        #expect(await run() == .result(PlayResult(outcome: .degraded, reason: .shortcutMissing)))
        #expect(starter.startCount == 0)
    }

    @Test func catalogErrorsAreReturnedAsErrors() async {
        await plans.set(.failure(.libraryUnavailable))
        #expect(await run() == .error(.libraryUnavailable))
    }

    @Test func failedShortcutWithMusicUntouchedDegrades() async {
        let starter = self.starter
        starter.onStart = { starter.last?.finish(1) }
        #expect(await run() == .result(PlayResult(outcome: .degraded, reason: .shortcutFailed)))
    }

    @Test func failedShortcutThatMovedMusicIsLateChange() async {
        let starter = self.starter
        await music.at(0.5, snap(t3))
        starter.onStart = { starter.last?.finish(1) }
        await clock.settle()
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .lateChange)))
        #expect(await music.playOnceCalls.isEmpty)
    }

    @Test func exitZeroWithoutArrivalIsTargetTimeout() async {
        let starter = self.starter
        starter.onStart = { starter.last?.finish(0) }
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .targetTimeout)))
    }

    @Test func hangingShortcutIsTerminatedAndQuarantined() async {
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(starter.last?.terminated == true)
        // 隔離期內的下一筆：不查捷徑、不啟動
        let callsBefore = await binding.calls
        #expect(await run(until: 62) == .result(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(starter.startCount == 1)
        let callsAfter = await binding.calls
        #expect(callsAfter == callsBefore)
    }

    @Test func quarantineEndsAfterMinimumAndQuietObservation() async {
        _ = await run()                                       // 無回應 → 隔離（約 t=6），跑到 t=60
        let base = await clock.time
        await machine.observeQuiet(snap(other), queue: ["00000000000000a0"])   // 輪詢回報（第一次）
        await clock.advance(to: base + 1)
        await machine.observeQuiet(snap(other), queue: ["00000000000000a0"])   // 未滿 3 s：仍隔離
        #expect(await machine.isQuarantined)
        await clock.advance(to: base + 3.5)
        await machine.observeQuiet(snap(other), queue: ["00000000000000a0"])   // 連續 3 s 相同＝解除
        #expect(await !machine.isQuarantined)
    }

    @Test func quarantineStaysWhileMusicKeepsChanging() async {
        _ = await run()
        let base = await clock.time
        await machine.observeQuiet(snap(other), queue: ["00000000000000a0"])
        await clock.advance(to: base + 2)
        await machine.observeQuiet(snap(t1), queue: ["00000000000000a0"])       // 遲到的捷徑換了歌：重新起算
        await clock.advance(to: base + 4)
        await machine.observeQuiet(snap(t1), queue: ["00000000000000a0"])
        #expect(await machine.isQuarantined)
    }

    @Test func arrivedButNeverExitingIsUnresponsive() async {
        await music.at(1.2, snap(t2))
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(starter.last?.terminated == true)
    }

    @Test func unstableQueueIsQueueTimeout() async {
        await scriptHappyShortcut()
        for step in 0..<40 { await queue.at(1.5 + Double(step) * 0.5, step.isMultiple(of: 2) ? [t2, t3] : [t2]) }
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .queueTimeout)))
    }

    @Test func stableButWrongQueueDegradesOnce() async {
        await scriptHappyShortcut()
        await queue.at(1.5, [t2, other])
        #expect(await run() == .result(PlayResult(outcome: .degraded, reason: .queueMismatch)))
        #expect(await music.playOnceCalls == [t2])
    }

    /// §4.9 #12：降級之後，遲到的捷徑才把佇列改掉——結果已回，之後不再讀 Music、不再點歌、不再啟捷徑（不對抗）
    @Test func lateShortcutAfterDegradeIsNotFought() async {
        await scriptHappyShortcut()
        await queue.at(1.5, [t2, other])
        await queue.at(25, [t2, t3])            // 遲到的改動
        await music.at(26, snap(t3))
        #expect(await run(until: 20) == .result(PlayResult(outcome: .degraded, reason: .queueMismatch)))
        let reads = await music.reads, plays = await music.playOnceCalls, starts = starter.startCount
        await clock.advance(to: 60)
        let readsAfter = await music.reads, playsAfter = await music.playOnceCalls
        #expect(readsAfter == reads && playsAfter == plays && starter.startCount == starts)
    }

    /// §4.9 #5：點歌途中曲庫換版（計畫來源改回另一個順序）——仍以開始時繫結的期待序列判定
    @Test func catalogChangeDuringPlayUsesBoundExpectation() async {
        await scriptHappyShortcut()
        let plans = self.plans
        starter.onStart = { [starter] in
            Task {
                await plans.set(.success(.admitted(ShortcutPlan(album: "Album", albumArtist: "", artist: "Someone", order: [t3, t2]))))
                while await self.clock.time < 1.3 { try? await Task.sleep(for: .milliseconds(1)) }
                starter.last?.finish(0)
            }
        }
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// Codex S4 R2 P2：§4.5「從捷徑發起到出結果之間」都要比對——到達前就在 Mac 上暫停基準曲＝手動操作
    @Test func macPauseBeforeArrivalIsManualChange() async {
        await scriptHappyShortcut()
        await music.at(0.5, snap(other, .paused, position: 30.5))
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
    }

    /// 到達前換到與這張專輯無關的曲目＝手動操作
    @Test func jumpToUnrelatedTrackBeforeArrivalIsManualChange() async {
        await scriptHappyShortcut()
        await music.at(0.5, snap("00000000000000ee"))
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
    }

    /// 到達前 iPad 自己按的暫停（本地操作紀錄可解釋）不算
    @Test func localPauseBeforeArrivalIsExplained() async {
        await scriptHappyShortcut()
        await music.at(0.5, snap(other, .paused, position: 30.5))
        await local.record(.toggle(stateAfter: .paused), at: 0.5)
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// Codex S4 R3 P1：到達後、捷徑還沒結束時偵測到手動操作——終止捷徑並隔離，免得它之後蓋掉使用者的操作
    @Test func manualChangeWhileShortcutStillRunsTerminatesAndQuarantines() async {
        await music.at(1.2, snap(t2))
        await music.at(1.6, snap(t2, .paused, position: 0.4))   // 到達後在 Mac 上暫停；捷徑一直沒結束
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
        #expect(starter.last?.terminated == true)
        #expect(await machine.isQuarantined)
        // F16：隔離中的下一次點歌直接被擋（不啟動捷徑）——iPad 依此 reason 顯示「暫停接受點歌」
        let launched = starter.startCount
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(starter.startCount == launched)
    }

    /// simcodex R2 security LOW-2（使用者 2026-10-19 同意改行為）：隔離中點到目錄閘門拒絕的曲目也要擋——
    /// 舊行為直接降級 playOnce 改動 Music，與 F16「暫停接受點歌」矛盾；隔離中連目錄都不查
    @Test(arguments: [PlayReason.gateAmbiguousTitle, .gateOrderUndefined])
    func quarantineAlsoBlocksPicksTheCatalogGateRefuses(reason: PlayReason) async {
        await music.at(1.2, snap(t2))
        await music.at(1.6, snap(t2, .paused, position: 0.4))
        _ = await run()
        #expect(await machine.isQuarantined)
        await plans.set(.success(.refused(reason)))
        let planned = await plans.calls
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)))
        #expect(await music.playOnceCalls.isEmpty)
        #expect(await plans.calls == planned)
    }

    /// #4-1 真機實測：捷徑換歌時 Music 先回報「目標曲、停止、位置 0」，0.1 s 後才變播放中——
    /// 這是開始播放的正常過程，不是 Mac 上的手動操作（曾讓點歌誤報 manualChange）
    @Test func targetArrivingStoppedThenPlayingIsVerified() async {
        await scriptHappyShortcut()
        await music.at(1.2, snap(t2, .stopped, position: 0))
        await music.at(1.3, snap(t2, .playing, position: 0))
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// #4-1 真機實測：捷徑下播放指令時，Music 先回報「舊曲目 ID、位置歸零、播放中」，之後才換成目標曲——
    /// 到達前的位置跳動是切歌本身，不是 Mac 上拖進度（曾讓點歌誤報 manualChange）
    @Test func baselinePositionResetBeforeArrivalIsNotManual() async {
        await scriptHappyShortcut()
        await music.at(1.0, snap(other, .playing, position: 0))
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    @Test func emptyTrackIDBeforeArrivalIsNotManual() async {
        await scriptHappyShortcut()
        await music.at(1.0, snap("", .playing, position: 0))
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// #4-1 N-01 真機（19:26:02）：等捷徑結束／驗證佇列期間，Music 換曲瞬間短暫回報空 ID——
    /// 曾被當成手動換歌，終止捷徑並隔離，連下一次點歌都被擋（shortcutUnresponsive）。短暫的空 ID 不判
    @Test func briefEmptyTrackIDAfterArrivalIsNotManual() async {
        await scriptHappyShortcut()
        await music.at(2.4, snap("", .playing, position: 1.2))      // 0.5 s 一次的驗證輪詢必定讀到一次
        await music.at(2.85, snap(t2, .playing, position: 1.65))
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// #4-1 N-01 真機（19:24:29）：驗證佇列期間短暫回報「停止」，下一次讀回又播放中——不判
    @Test func briefStopAfterArrivalIsNotManual() async {
        await scriptHappyShortcut()
        await music.at(2.4, snap(t2, .stopped, position: 1.2))
        await music.at(2.85, snap(t2, .playing, position: 1.65))
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// 持續超過 1 s 的停止＝真的在 Mac 上停了
    @Test func lastingStopAfterArrivalIsManual() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(t2, .stopped, position: 1.3))
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
    }

    /// 持續超過 1 s 沒有目前曲＝真的變了
    @Test func lastingEmptyTrackIDAfterArrivalIsManual() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap("", .stopped, position: 0))
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
    }

    /// #4-1 N-01 真機（19:42:38、19:51:21）：點的正是正在播的那首——舊判定一開始就算「到達」，
    /// 捷徑讓它從頭播時的位置歸零被當成 Mac 上拖進度，判 manualChange、終止捷徑並隔離（下一次點歌也被擋）。
    /// 起點已是目標曲時，要看到「從頭開始」（位置明顯倒回）才算到達
    @Test func pickingTheCurrentTrackWaitsForItToRestart() async {
        await music.set(initial: snap(t2, position: 30))
        await scriptHappyShortcut(arrival: 1.2)
        await music.at(1.2, snap(t2, position: 0))
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
        #expect(arrivals.all == [t2])
    }

    /// 起點已是目標曲、而且本來就在開頭附近（倒回看不出來）：捷徑正常結束時仍是目標曲＝到達
    @Test func pickingTheCurrentTrackNearItsStartArrivesWhenShortcutEnds() async {
        await music.set(initial: snap(t2, position: 0.2))
        await scriptHappyShortcut(arrival: 1.2)
        await music.at(1.2, snap(t2, position: 0))
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    @Test func manualJumpDuringVerificationIsManualChange() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(other))
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
        #expect(await music.playOnceCalls.isEmpty)
    }

    /// 驗證中目標曲自然播完進下一首：位置歸零不算跳動；佇列變成從目前曲起的後綴，仍算符合（§4.5 錨點規則）
    @Test func naturalAdvanceToNextExpectedTrackStaysVerified() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(t3))
        await queue.at(2.5, [t3])
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    @Test func macPauseDuringVerificationIsManualChange() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(t2, .paused, position: 1.3))
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
    }

    @Test func localTogglePauseIsExplained() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(t2, .paused, position: 1.3))
        await local.record(.toggle(stateAfter: .paused), at: 2.4)
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// simcodex R2 第 5 項：iPad 的暫停還在讀回（在途意圖、尚未確認）時狀態機就看到暫停——也算本地操作
    @Test func pendingLocalToggleIsExplained() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(t2, .paused, position: 1.3))
        _ = await local.begin(.toggle(stateAfter: .paused), at: 2.4)
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    /// 同上（Codex）：撤銷了的意圖（iPad 的暫停沒生效）不得替 Mac 上真的手動暫停背書
    @Test func revokedLocalToggleDoesNotExplainAManualPause() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(t2, .paused, position: 1.3))
        let intent = await local.begin(.toggle(stateAfter: .paused), at: 2.0)
        await local.revoke(intent)
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .manualChange)))
    }

    @Test func localSeekIsExplained() async {
        await scriptHappyShortcut()
        await music.at(2.5, snap(t2, position: 120))
        await local.record(.seek(positionAfter: 120), at: 2.4)
        #expect(await run() == .result(PlayResult(outcome: .verified, reason: nil)))
    }

    @Test func degradeThatCannotFindTrackIsFallbackFailed() async {
        await plans.set(.success(.refused(.gateOrderUndefined)))
        await music.set(playOnceFinds: false)
        #expect(await run() == .result(PlayResult(outcome: .indeterminate, reason: .fallbackFailed)))
    }

    @Test func launchFailureDegradesAsShortcutFailed() async {
        starter.failLaunch = true
        #expect(await run() == .result(PlayResult(outcome: .degraded, reason: .shortcutFailed)))
    }

    /// 期限圖最長路徑（到達 → 結束 → 穩定 → 不一致 → 降級）不超過 worst(play.track)
    @Test func longestPathFinishesWithinWorst() async {
        let starter = self.starter, clock = self.clock
        await music.at(5.9, snap(t2))
        await queue.at(9.9, [t2, other])
        starter.onStart = {
            Task {
                while await clock.time < 9.9 { try? await Task.sleep(for: .milliseconds(1)) }
                starter.last?.finish(0)
            }
        }
        let machine = self.machine
        let task = Task { () -> (PlayTrackOutcome, Double) in
            let outcome = await machine.play(request)
            return (outcome, await clock.time)
        }
        await clock.settle()
        await clock.advance(to: 60)
        let (outcome, finishedAt) = await task.value
        #expect(outcome == .result(PlayResult(outcome: .degraded, reason: .queueMismatch)))
        #expect(finishedAt <= PlaybackLimits.worstPlayTrack)
    }
}

#endif

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Bool
    init(_ value: Bool) { current = value }
    var value: Bool { lock.withLock { current } }
    func set(_ value: Bool) { lock.withLock { current = value } }
}

extension PlayTrackRunning {
    /// 測試用：連線一直都在
    func play(_ request: PlayTrackRequest) async -> PlayTrackOutcome { await play(request, shouldContinue: { true }) }
}
