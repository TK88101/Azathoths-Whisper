#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T8（sprint-4-detail.md §4.7；F-P-05、D2）：狀態輪詢與推送

private func event(_ track: String?, _ state: PlaybackState = .playing, position: Double = 0, duration: Double? = 200,
                   availability: PlaybackAvailability = .ok, at: Double = 0) -> PlaybackEvent {
    PlaybackEvent(availability: availability, trackID: track, albumID: nil, state: state, position: position,
                  duration: duration, sampledAt: at)
}

struct PushPolicyTests {
    @Test func firstEventAlwaysPushes() {
        #expect(PushPolicy.shouldPush(last: nil, current: event("a")))
    }

    @Test func identityAndStateChangesPush() {
        let last = event("a", at: 0)
        #expect(PushPolicy.shouldPush(last: last, current: event("b", at: 1)))
        #expect(PushPolicy.shouldPush(last: last, current: event("a", .paused, at: 1)))
        #expect(PushPolicy.shouldPush(last: last, current: event("a", duration: 100, at: 1)))
        #expect(PushPolicy.shouldPush(last: last, current: event("a", availability: .musicNotRunning, at: 1)))
    }

    @Test func positionFollowingExtrapolationDoesNotPushButJumpsDo() {
        let last = event("a", position: 10, at: 0)
        #expect(!PushPolicy.shouldPush(last: last, current: event("a", position: 13, at: 3)))
        #expect(PushPolicy.shouldPush(last: last, current: event("a", position: 60, at: 3)))
        let paused = event("a", .paused, position: 10, at: 0)
        #expect(!PushPolicy.shouldPush(last: paused, current: event("a", .paused, position: 10, at: 3)))
        #expect(PushPolicy.shouldPush(last: paused, current: event("a", .paused, position: 12, at: 3)))
    }

    @Test func refreshEveryTenSeconds() {
        let last = event("a", .paused, position: 10, at: 0)
        #expect(!PushPolicy.shouldPush(last: last, current: event("a", .paused, position: 10, at: 9.9)))
        #expect(PushPolicy.shouldPush(last: last, current: event("a", .paused, position: 10, at: 10)))
    }
}

/// 輪詢替身：依序回報設定好的狀態或錯誤
actor PollTarget: ControlTarget {
    var result: Result<MusicSnapshot, MusicLaneError> = .success(MusicSnapshot(state: .playing, trackID: "0000000000000001",
                                                                                duration: 200, position: 0))
    private(set) var reads = 0
    /// true＝讀取停住直到 release（模擬 Music 卡住）
    var hold = false
    private var held: [CheckedContinuation<Void, Never>] = []
    func set(_ value: Result<MusicSnapshot, MusicLaneError>) { result = value }
    func set(hold value: Bool) { hold = value }
    func release() { held.forEach { $0.resume() }; held = [] }
    var waiting: Int { held.count }
    func snapshot() async throws(MusicLaneError) -> MusicSnapshot {
        reads += 1
        if hold { await withCheckedContinuation { held.append($0) } }
        return try result.get()
    }
    func next() async throws(MusicLaneError) {}
    func previous() async throws(MusicLaneError) {}
    func togglePlayPause() async throws(MusicLaneError) {}
    func seek(to seconds: Double) async throws(MusicLaneError) {}
}

/// Genius 可用性替身（輔助使用權限隨時可被使用者改）
final class GeniusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: GeniusAvailability
    init(_ value: GeniusAvailability = .needsAccessibility) { current = value }
    var value: GeniusAvailability {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

final class PushLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [PlaybackEvent] = []
    func append(_ e: PlaybackEvent) { lock.withLock { events.append(e) } }
    var all: [PlaybackEvent] { lock.withLock { events } }
}

@Suite(.serialized) struct PlaybackStatePollerTests {
    let clock = ManualControlClock()
    let target = PollTarget()
    let pushes = PushLog()
    let genius = GeniusBox()
    let poller: PlaybackStatePoller

    init() {
        let pushes = self.pushes, genius = self.genius
        poller = PlaybackStatePoller(music: target, clock: clock, albumOf: { $0 == "0000000000000001" ? "00000000000000bb" : nil },
                                     genius: { genius.value }, push: { pushes.append($0) })
    }

    /// CR-030 G2：每筆事件都帶 Genius 可用性（含 Music 未開時）；權限一變，下一次輪詢就推
    @Test func geniusAvailabilityRidesEveryEventAndChangePushesNextPoll() async {
        await target.set(.success(MusicSnapshot(state: .paused, trackID: "0000000000000001", duration: 200, position: 5)))
        await poller.start()
        await clock.settle()
        #expect(pushes.all.count == 1 && pushes.all.last?.genius == .needsAccessibility)
        genius.value = .ready
        await clock.advance(to: PlaybackLimits.pollInterval + 0.01)
        #expect(pushes.all.count == 2 && pushes.all.last?.genius == .ready)
        await target.set(.failure(.notRunning))
        await clock.advance(to: 2 * PlaybackLimits.pollInterval + 0.02)
        #expect(pushes.all.last?.availability == .musicNotRunning && pushes.all.last?.genius == .ready)
        await poller.stop()
    }

    /// 替身的位置不隨時間前進，所以從暫停起步（「播放中位置照外推不推」由 PushPolicyTests 驗）
    @Test func startPushesCurrentStateWithAlbumThenOnlyOnChange() async {
        await target.set(.success(MusicSnapshot(state: .paused, trackID: "0000000000000001", duration: 200, position: 5)))
        await poller.start()
        await clock.settle()
        #expect(pushes.all.count == 1 && pushes.all.first?.albumID == "00000000000000bb")
        await clock.advance(to: 2)   // 沒變：不推
        #expect(pushes.all.count == 1)
        await target.set(.success(MusicSnapshot(state: .playing, trackID: "0000000000000001", duration: 200, position: 5)))
        await clock.advance(to: 2.6)
        #expect(pushes.all.count == 2 && pushes.all.last?.state == .playing)
        await poller.stop()
    }

    @Test func musicNotRunningIsPushedAsAvailability() async {
        await target.set(.failure(.notRunning))
        await poller.start()
        await clock.settle()
        #expect(pushes.all.last?.availability == .musicNotRunning && pushes.all.last?.trackID == nil)
        await target.set(.success(MusicSnapshot(state: .playing, trackID: "0000000000000001", duration: 200, position: 0)))
        await clock.advance(to: 0.6)
        #expect(pushes.all.last?.availability == .ok)
        await poller.stop()
    }

    @Test func automationDeniedBacksOffToTenSeconds() async {
        await target.set(.failure(.notAuthorized))
        await poller.start()
        await clock.settle()
        #expect(pushes.all.last?.availability == .automationDenied)
        let readsAfterFirst = await target.reads
        await clock.advance(to: 9)
        #expect(await target.reads == readsAfterFirst)    // 不連續撞權限
        await clock.advance(to: 10.5)
        #expect(await target.reads == readsAfterFirst + 1)
        await poller.stop()
    }

    @Test func transientFailureIsNotPushed() async {
        await poller.start()
        await clock.settle()
        await target.set(.failure(.failed(code: -1712)))
        await clock.advance(to: 1.1)
        #expect(pushes.all.count == 1)
        await poller.stop()
    }

    @Test func stopHaltsPollingAndStartIsIdempotent() async {
        await poller.start()
        await poller.start()
        await clock.settle()
        #expect(await clock.sleeperCount == 1)
        await poller.stop()
        await clock.settle()
        let reads = await target.reads
        await clock.advance(to: 5)
        #expect(await target.reads == reads)
    }

    @Test func notificationTriggersImmediatePoll() async {
        await poller.start()
        await clock.settle()
        let reads = await target.reads
        await poller.playerInfoChanged()
        #expect(await target.reads == reads + 1)
        await poller.stop()
    }

    /// security review MEDIUM-3：playerInfo 是任何本機程序都能發的分散式通知——讀取進行中再來的通知只合併成一次補讀
    @Test func playerInfoStormIsCoalesced() async {
        await poller.start()
        await clock.settle()
        let before = await target.reads
        await target.set(hold: true)
        let poller = self.poller
        let storm = (0..<50).map { _ in Task { await poller.playerInfoChanged() } }
        while await target.waiting == 0 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        await target.set(hold: false)
        await target.release()
        await clock.settle()
        await clock.advance(by: PlaybackStatePoller.kickMinimumGap)
        for task in storm { await task.value }
        #expect(await target.reads - before <= 2)
        await poller.stop()
    }

    /// 合併之外還要限速：讀完後若又有通知，至少隔 kickMinimumGap 才補讀（持續灌通知也不會連續打 AE）
    @Test func coalescedKickWaitsMinimumGapBeforeRereading() async {
        await poller.start()
        await clock.settle()
        let before = await target.reads
        await target.set(hold: true)
        let poller = self.poller
        let first = Task { await poller.playerInfoChanged() }
        while await target.waiting == 0 { await Task.yield() }
        let second = Task { await poller.playerInfoChanged() }
        for _ in 0..<20 { await Task.yield() }
        await target.set(hold: false)
        await target.release()
        await second.value
        await clock.settle()
        #expect(await target.reads == before + 1)        // 補讀還在等最小間隔
        await clock.advance(by: PlaybackStatePoller.kickMinimumGap)
        await first.value
        #expect(await target.reads == before + 2)
        await poller.stop()
    }

    /// #4-1 真機：iPad 暫停後進度條還走幾秒——控制回覆帶著「還在播」的舊讀回，較早時間戳的「已暫停」被 iPad 當亂序丟掉，
    /// 之後狀態不再變就不推。控制之後的下一次輪詢一律推送（新時間戳），iPad 必收下
    @Test func pollAfterControlAlwaysPushes() async {
        await target.set(.success(MusicSnapshot(state: .paused, trackID: "0000000000000001", duration: 200, position: 5)))
        await poller.start()
        await clock.settle()
        let before = pushes.all.count
        await poller.controlApplied()
        await clock.advance(by: PlaybackLimits.pollInterval + 0.01)
        #expect(pushes.all.count == before + 1)          // 狀態沒變也推
        await clock.advance(by: PlaybackLimits.pollInterval + 0.01)
        #expect(pushes.all.count == before + 1)          // 只推一次
        await poller.stop()
    }

    @Test func resendPushesLastEventEvenIfUnchanged() async {
        await poller.start()
        await clock.settle()
        await poller.resendCurrent()
        #expect(pushes.all.count == 2 && pushes.all[0].trackID == pushes.all[1].trackID)
        await poller.stop()
    }

    /// 新連線要拿到「現在」的狀態，不是上一次推過的值（兩次輪詢之間 Mac 上剛暫停）
    @Test func resendReadsFreshStateNotTheLastPushed() async {
        await poller.start()
        await clock.settle()
        await target.set(.success(MusicSnapshot(state: .paused, trackID: "0000000000000001", duration: 200, position: 0)))
        await poller.resendCurrent()
        #expect(pushes.all.last?.state == .paused)
        await poller.stop()
    }

    /// 讀取暫時失敗：仍把上一次的值推給新連線，不讓它空等到下一次變化
    @Test func resendFallsBackToLastPushedWhenReadFails() async {
        await poller.start()
        await clock.settle()
        await target.set(.failure(.failed(code: -1712)))
        await poller.resendCurrent()
        #expect(pushes.all.count == 2 && pushes.all.last?.state == .playing)
        await poller.stop()
    }

    /// 沒在輪詢（無連線）時不讀 Music（D13）
    @Test func resendWithoutWatchingNeverReads() async {
        await poller.resendCurrent()
        #expect(await target.reads == 0 && pushes.all.isEmpty)
    }
}
/// #4-1 D2 診斷：每次推送記下原因（Mac 上暫停一次 iPad 收到兩筆「已暫停」，要知道第二筆為何被推）
struct PushReasonTests {
    private func event(_ state: PlaybackState, position: Double, at time: Double, duration: Double? = 200) -> PlaybackEvent {
        PlaybackEvent(availability: .ok, trackID: "0000000000000001", albumID: nil, state: state, position: position,
                      duration: duration, sampledAt: time)
    }

    @Test func reasonNamesTheFirstDifference() {
        #expect(PushPolicy.reason(last: nil, current: event(.playing, position: 1, at: 1))?.rawValue == "first")
        #expect(PushPolicy.reason(last: event(.playing, position: 1, at: 1), current: event(.paused, position: 1.4, at: 1.4))?.rawValue == "state")
        #expect(PushPolicy.reason(last: event(.paused, position: 1, at: 1), current: event(.paused, position: 3, at: 1.5))?.rawValue == "jump")
        #expect(PushPolicy.reason(last: event(.paused, position: 1, at: 1), current: event(.paused, position: 1, at: 1.5, duration: 201))?.rawValue == "duration")
        #expect(PushPolicy.reason(last: event(.paused, position: 1, at: 1), current: event(.paused, position: 1, at: 1.5)) == nil)
    }

    /// 同時有多項不同時的優先順序（重構前的特性測試；Codex 2026-10-19：順序一變就可能漏推）：
    /// availability → track → state → duration → refresh → jump。以字面比對，原因的型別改變也照樣適用
    @Test func simultaneousDifferencesKeepTheirPriority() {
        func name(_ last: PlaybackEvent?, _ current: PlaybackEvent) -> String {
            PushPolicy.reason(last: last, current: current).map { String(describing: $0) } ?? "nil"
        }
        let base = PlaybackEvent(availability: .ok, trackID: "0000000000000001", albumID: nil, state: .playing, position: 1,
                                 duration: 200, sampledAt: 0)
        func changed(availability: PlaybackAvailability = .ok, track: String? = "0000000000000001", state: PlaybackState = .playing,
                     position: Double = 1, duration: Double? = 200, at: Double = 0) -> PlaybackEvent {
            PlaybackEvent(availability: availability, trackID: track, albumID: nil, state: state, position: position,
                          duration: duration, sampledAt: at)
        }
        #expect(name(base, changed(availability: .musicNotRunning, track: "0000000000000002", state: .paused, position: 50,
                                   duration: 100, at: 20)) == "availability")
        #expect(name(base, changed(track: "0000000000000002", state: .paused, position: 50, duration: 100, at: 20)) == "track")
        #expect(name(base, changed(state: .paused, position: 50, duration: 100, at: 20)) == "state")
        #expect(name(base, changed(position: 50, duration: 100, at: 20)) == "duration")
        #expect(name(base, changed(position: 50, at: 20)) == "refresh")
        #expect(name(base, changed(position: 50, at: 1)) == "jump")
        #expect(name(base, changed(position: 2, at: 1)) == "nil")
    }
}

/// CR-030 G2：Genius 可用性改變也推；排在 duration 之後、refresh 之前
struct GeniusPushReasonTests {
    private func event(genius: GeniusAvailability?, duration: Double? = 200, at time: Double = 0) -> PlaybackEvent {
        PlaybackEvent(availability: .ok, trackID: "0000000000000001", albumID: nil, state: .paused, position: 1, duration: duration,
                      sampledAt: time, genius: genius)
    }

    @Test func geniusChangePushesWithItsOwnReasonAfterDurationBeforeRefresh() {
        let base = event(genius: .needsAccessibility)
        #expect(PushPolicy.reason(last: base, current: event(genius: .ready, at: 1)) == .genius)
        #expect(PushPolicy.reason(last: base, current: event(genius: .needsAccessibility, at: 1)) == nil)
        #expect(PushPolicy.reason(last: base, current: event(genius: .ready, duration: 100, at: 1)) == .duration)
        #expect(PushPolicy.reason(last: base, current: event(genius: .ready, at: 20)) == .genius)
    }
}
#endif

