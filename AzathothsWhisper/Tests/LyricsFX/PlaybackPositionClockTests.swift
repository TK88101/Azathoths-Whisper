import Foundation
import Testing

@testable import AzathothsWhisper

// 項 3：位置時鐘（母計劃 §2.3；A1 計劃 §3.3）。時間全部由測試給定（讀數的 readAt 與查詢時刻），
// 輪詢節奏用 GatedPollClock 放行，零真實延時
@MainActor
@Suite("PlaybackPositionClock")
struct PlaybackPositionClockTests {
    static let base = ContinuousClock.now
    static let id = "PID1"

    static func at(_ seconds: Double) -> ContinuousClock.Instant { base.advanced(by: .seconds(seconds)) }

    static func reading(_ seconds: Double, at time: Double, state: PlayerState = .playing, id: String = id) -> Result<PlaybackPosition?, MusicError> {
        .success(PlaybackPosition(persistentID: id, seconds: seconds, state: state, readAt: at(time), roundTrip: .milliseconds(10)))
    }

    struct Harness {
        let music: MockMusicClient
        let poll: GatedPollClock
        let clock: PlaybackPositionClock
    }

    private func harness(_ readings: [Result<PlaybackPosition?, MusicError>], offset: Double = 0) async -> Harness {
        let music = MockMusicClient()
        await music.setPlaybackPositions(readings)
        let poll = GatedPollClock()
        let clock = PlaybackPositionClock(music: music, pollClock: poll, offset: offset)
        return Harness(music: music, poll: poll, clock: clock)
    }

    /// 開始讀並等第 n 次讀數處理完
    private func start(_ h: Harness, reads: Int = 1) async {
        h.clock.setTrack(Self.id)
        h.clock.setActive(true)
        await processed(h, reads)
    }

    private func processed(_ h: Harness, _ count: Int) async {
        await waitUntil({ h.clock.readSerial >= count }, iterations: 20_000)
    }

    private func nextPoll(_ h: Harness, then count: Int) async {
        await h.poll.waitUntilPending(1)
        await h.poll.releaseNext()
        await processed(h, count)
    }

    @Test func doesNotReadUntilActiveWithATrack() async {
        let h = await harness([Self.reading(10, at: 0)])
        h.clock.setTrack(Self.id)
        await settle()
        h.clock.setTrack(nil)
        h.clock.setActive(true)
        await settle()
        #expect(await h.music.playbackPositionCalls == 0)
    }

    @Test func playingReadingAnchorsAndInterpolates() async {
        let h = await harness([Self.reading(10, at: 0)])
        await start(h)
        #expect(h.clock.position(at: Self.at(3)) == 13)
    }

    @Test func readingsWithinToleranceKeepTheAnchor() async {
        let h = await harness([Self.reading(10, at: 0), Self.reading(12.3, at: 2)])
        await start(h)
        let anchor = h.clock.anchor
        await nextPoll(h, then: 2)
        #expect(h.clock.anchor == anchor)
        #expect(h.clock.position(at: Self.at(2)) == 12)
    }

    @Test func aSeekBeyondToleranceReanchors() async {
        let h = await harness([Self.reading(10, at: 0), Self.reading(60, at: 2)])
        await start(h)
        await nextPoll(h, then: 2)
        #expect(h.clock.position(at: Self.at(2)) == 60)
    }

    @Test func playingPollsEveryTwoSecondsAndPausedEverySix() async {
        let h = await harness([Self.reading(10, at: 0), Self.reading(10, at: 2, state: .paused), Self.reading(10, at: 8, state: .paused)])
        await start(h)
        await nextPoll(h, then: 2)
        await h.poll.waitUntilPending(1)
        #expect(await h.poll.requested == [PlaybackPositionClock.playingInterval, PlaybackPositionClock.pausedInterval])
    }

    @Test func pausedFreezesTime() async {
        let h = await harness([Self.reading(42, at: 0, state: .paused)])
        await start(h)
        #expect(h.clock.anchor == .frozen(seconds: 42))
        #expect(h.clock.position(at: Self.at(100)) == 42)
    }

    /// 暫停→播放的通知漏了：6 秒低頻輪詢把它救回來（母計劃 §2.3 R2-Q3）
    @Test func resumingWithoutANotificationIsPickedUpByPolling() async {
        let h = await harness([Self.reading(42, at: 0, state: .paused), Self.reading(42, at: 6)])
        await start(h)
        await nextPoll(h, then: 2)
        #expect(h.clock.position(at: Self.at(8)) == 44)
    }

    /// offset 是顯示時間的固定平移：兩態都加，重錨判斷不含它（Codex R1／R2）
    @Test func offsetShiftsBothStatesButNotTheReanchorDecision() async {
        let h = await harness([Self.reading(10, at: 0), Self.reading(12, at: 2), Self.reading(20, at: 4, state: .paused)], offset: 1.0)
        await start(h)
        #expect(h.clock.position(at: Self.at(0)) == 11)
        let anchor = h.clock.anchor
        await nextPoll(h, then: 2)
        #expect(h.clock.anchor == anchor, "offset 大於容差時，一致的讀數不得觸發重錨")
        await nextPoll(h, then: 3)
        #expect(h.clock.position(at: Self.at(50)) == 21)
    }

    @Test func aReadingForAnotherTrackIsDiscarded() async {
        let h = await harness([Self.reading(10, at: 0, id: "PID2")])
        await start(h)
        #expect(h.clock.anchor == nil)
    }

    @Test func noCurrentTrackClearsTheAnchor() async {
        let h = await harness([Self.reading(10, at: 0), .success(nil)])
        await start(h)
        await nextPoll(h, then: 2)
        #expect(h.clock.anchor == nil)
    }

    @Test func musicQuittingClearsTheAnchorButOtherErrorsKeepIt() async {
        let h = await harness([Self.reading(10, at: 0), .failure(.scriptingFailure("AE error -1712")), .failure(.notRunning)])
        await start(h)
        await nextPoll(h, then: 2)
        #expect(h.clock.anchor != nil)
        await nextPoll(h, then: 3)
        #expect(h.clock.anchor == nil)
    }

    @Test func resyncReadsAtOnceAndCoalescesWithAReadInFlight() async {
        let gate = LyricsGate()
        let h = await harness([Self.reading(10, at: 0), Self.reading(10, at: 0.5)])
        await h.music.setPlaybackPositionGateQueue([gate])
        h.clock.setTrack(Self.id)
        h.clock.setActive(true)
        await waitFor { await h.music.playbackPositionCalls == 1 }
        h.clock.resync()
        h.clock.resync()
        await settle()
        #expect(await h.music.playbackPositionCalls == 1)
        await gate.open()
        await processed(h, 2)
        #expect(await h.music.playbackPositionCalls == 2)
        #expect(await h.music.maxPlaybackPositionInFlight == 1)
    }

    @Test func resyncWhileIdleBetweenPollsReadsWithoutWaitingForTheSleep() async {
        let h = await harness([Self.reading(10, at: 0), Self.reading(30, at: 1)])
        await start(h)
        await h.poll.waitUntilPending(1)
        h.clock.resync()
        await processed(h, 2)
        #expect(h.clock.position(at: Self.at(1)) == 30)
    }

    @Test func resyncWhileInactiveDoesNotRead() async {
        let h = await harness([Self.reading(10, at: 0)])
        h.clock.setTrack(Self.id)
        h.clock.resync()
        await settle()
        #expect(await h.music.playbackPositionCalls == 0)
    }

    /// busy 期間不送 AE（輪詢與 resync 都不讀），全部空閒時補讀恰一次（母計劃 §2.3 R2，Codex 勝）
    @Test func pausesReadsWhileBusyAndCatchesUpAfter() async {
        let h = await harness([Self.reading(10, at: 0), Self.reading(11, at: 1), Self.reading(12, at: 2)])
        await start(h)
        h.clock.setBusy(true, source: .editor)
        h.clock.setBusy(true, source: .batch)
        await h.poll.waitUntilPending(1)
        await h.poll.releaseNext()
        h.clock.resync()
        await settle()
        #expect(await h.music.playbackPositionCalls == 1)
        h.clock.setBusy(false, source: .editor)
        await settle()
        #expect(await h.music.playbackPositionCalls == 1, "還有一個來源在忙")
        h.clock.setBusy(false, source: .batch)
        await processed(h, 2)
        await settle()
        #expect(await h.music.playbackPositionCalls == 2)
    }

    /// 停讀後才回來的舊讀數不得把 anchor 復活（Codex R1：生命週期世代守衛）
    @Test func aReadingThatArrivesAfterDeactivationIsDiscarded() async {
        let gate = LyricsGate()
        let h = await harness([Self.reading(10, at: 0)])
        await h.music.setPlaybackPositionGateQueue([gate])
        h.clock.setTrack(Self.id)
        h.clock.setActive(true)
        await waitFor { await h.music.playbackPositionCalls == 1 }
        h.clock.setActive(false)
        await gate.open()
        await processed(h, 1)
        #expect(h.clock.anchor == nil)
        #expect(h.clock.position(at: Self.at(1)) == nil)
    }

    @Test func aReadingThatArrivesAfterATrackChangeIsDiscarded() async {
        let gate = LyricsGate()
        let h = await harness([Self.reading(10, at: 0)])
        await h.music.setPlaybackPositionGateQueue([gate])
        h.clock.setTrack(Self.id)
        h.clock.setActive(true)
        await waitFor { await h.music.playbackPositionCalls == 1 }
        h.clock.setTrack("PID2")
        await gate.open()
        await processed(h, 1)
        #expect(h.clock.anchor == nil)
    }

    @Test func clearingTheTrackStopsReading() async {
        let h = await harness([Self.reading(10, at: 0)])
        await start(h)
        h.clock.setTrack(nil)
        #expect(h.clock.anchor == nil)
        await h.poll.releaseAll()
        await settle()
        #expect(await h.music.playbackPositionCalls == 1)
    }

    /// 同一首重送：不清 anchor、不打斷（Codex R2）
    @Test func settingTheSameTrackAgainIsANoOp() async {
        let h = await harness([Self.reading(10, at: 0)])
        await start(h)
        h.clock.setTrack(Self.id)
        #expect(h.clock.position(at: Self.at(1)) == 11)
    }
}
