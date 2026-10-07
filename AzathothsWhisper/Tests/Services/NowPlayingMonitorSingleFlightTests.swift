import Foundation
import Testing

@testable import AzathothsWhisper

// F1（計劃 2026-09-27-coverflow-f1-f2 §3.2）：換歌通知觸發讀取、busy 補讀、單飛合併
@Suite("NowPlayingMonitor single flight")
struct NowPlayingMonitorSingleFlightTests {
    private func trackEvents(_ monitor: NowPlayingMonitor, count: Int) async -> [TrackInfo] {
        var tracks: [TrackInfo] = []
        for await event in monitor.events {
            if case .trackChanged(let track, _, _) = event { tracks.append(track) }
            if tracks.count == count { break }
        }
        return tracks
    }

    /// 第一次讀取卡在閘門上：回傳閘門，呼叫端放行
    private func startBlockedRead(
        _ monitor: NowPlayingMonitor, _ music: MockMusicClient, gates: [LyricsGate], trigger: ReadTrigger = .poll
    ) async -> Task<Void, Never> {
        await music.setNowPlayingGateQueue(gates)
        let task = Task {
            switch trigger {
            case .poll: await monitor.tick()
            case .signal: await monitor.playerDidChange()
            }
        }
        await waitFor { await music.nowPlayingCalls == 1 }
        return task
    }

    enum ReadTrigger { case poll, signal }

    @Test func aPlayerChangeReadsAtOnce() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let tracks = trackEvents(monitor, count: 1)
        await monitor.playerDidChange()

        #expect(await tracks == [track])
        #expect(await music.nowPlayingCalls == 1)
    }

    @Test func aPlayerChangeWhileBusyIsReadOnceWhenIdle() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        await monitor.setBusy(true, source: .editor)
        await monitor.playerDidChange()
        await monitor.playerDidChange()
        await monitor.playerDidChange()
        #expect(await music.nowPlayingCalls == 0, "busy 期間不得查詢 Music（B-02）")

        await monitor.setBusy(false, source: .editor)
        #expect(await music.nowPlayingCalls == 1, "busy 期間的通知在空閒時補讀恰一次")
        await monitor.setBusy(false, source: .editor)
        #expect(await music.nowPlayingCalls == 1)
    }

    @Test func aPlayerChangeWaitsForEveryBusySource() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        await monitor.setBusy(true, source: .editor)
        await monitor.setBusy(true, source: .batch)
        await monitor.playerDidChange()
        await monitor.setBusy(false, source: .editor)
        #expect(await music.nowPlayingCalls == 0, "Batch 仍 busy")

        await monitor.setBusy(false, source: .batch)
        #expect(await music.nowPlayingCalls == 1)
    }

    @Test func pollTicksWhileBusyAreStillDropped() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        await monitor.setBusy(true, source: .editor)
        await monitor.tick()
        await monitor.setBusy(false, source: .editor)

        #expect(await music.nowPlayingCalls == 0, "輪詢在 busy 期間丟棄、不補讀")
    }

    @Test func pendingForceRefreshAndPlayerChangeReadOnlyOnce() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        await monitor.tick()

        await monitor.setBusy(true, source: .editor)
        await monitor.forceRefresh()
        await monitor.playerDidChange()
        async let tracks = trackEvents(monitor, count: 2)
        await monitor.setBusy(false, source: .editor)

        #expect(await tracks == [track, track], "forceRefresh 的重發當前曲不因合併而丟失")
        #expect(await music.nowPlayingCalls == 2, "兩個待補理由只讀一次")
    }

    @Test func overlappingTriggersCoalesceIntoOneFollowUpRead() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let first = LyricsGate()
        let read = await startBlockedRead(monitor, music, gates: [first])

        await monitor.tick()
        for _ in 0..<5 { await monitor.playerDidChange() }
        #expect(await music.nowPlayingCalls == 1, "讀取進行中不得再發第二個讀取")

        await first.open()
        await read.value
        #expect(await music.nowPlayingCalls == 2, "進行中收到的訊號合併成恰一次補讀")
        #expect(await music.maxNowPlayingInFlight == 1)
    }

    @Test func signalsDuringTheFollowUpReadGetOneMore() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let first = LyricsGate()
        let second = LyricsGate()
        let read = await startBlockedRead(monitor, music, gates: [first, second])

        await monitor.playerDidChange()
        await first.open()
        await waitFor { await music.nowPlayingCalls == 2 }
        for _ in 0..<3 { await monitor.playerDidChange() }
        await second.open()
        await read.value

        #expect(await music.nowPlayingCalls == 3, "補讀進行中的訊號再合併成一次，不多不少")
        #expect(await music.maxNowPlayingInFlight == 1)
    }

    @Test func forceRefreshDuringAnInFlightReadStillReemits() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        await monitor.tick()
        let first = LyricsGate()
        await music.setNowPlayingGateQueue([LyricsGate.opened(), first])
        let read = Task { await monitor.tick() }
        await waitFor { await music.nowPlayingCalls == 2 }

        async let tracks = trackEvents(monitor, count: 2)
        await monitor.forceRefresh()
        await first.open()
        await read.value

        #expect(await tracks == [track, track], "進行中的那次讀完寫回同一首，不得吃掉 forceRefresh 的重發")
    }

    @Test func aChangeArrivingMidReadIsSeenByTheFollowUpRead() async {
        let a = TrackInfo.fixture(id: "PIDA")
        let b = TrackInfo.fixture(id: "PIDB")
        let music = MockMusicClient(script: [.track(a, lyrics: "a"), .track(b, lyrics: "b")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let first = LyricsGate()
        async let tracks = trackEvents(monitor, count: 2)
        let read = await startBlockedRead(monitor, music, gates: [first])

        await monitor.playerDidChange()
        await first.open()
        await read.value

        #expect(await tracks == [a, b])
    }

    @Test func busyStartingMidReadDefersASignalFollowUp() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let first = LyricsGate()
        let read = await startBlockedRead(monitor, music, gates: [first])

        await monitor.playerDidChange()
        await monitor.setBusy(true, source: .editor)
        await first.open()
        await read.value
        #expect(await music.nowPlayingCalls == 1, "變 busy 之後不得再讀")

        await monitor.setBusy(false, source: .editor)
        #expect(await music.nowPlayingCalls == 2, "通知的補讀延到空閒時")
    }

    @Test func busyStartingMidReadDropsAPollFollowUp() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let first = LyricsGate()
        let read = await startBlockedRead(monitor, music, gates: [first], trigger: .signal)

        await monitor.tick()
        await monitor.setBusy(true, source: .editor)
        await first.open()
        await read.value
        await monitor.setBusy(false, source: .editor)

        #expect(await music.nowPlayingCalls == 1, "輪詢的補讀遇到 busy 就丟棄（B-02）")
    }

    @Test func stoppingMidReadDropsTheFollowUp() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let first = LyricsGate()
        let read = await startBlockedRead(monitor, music, gates: [first])

        await monitor.playerDidChange()
        await monitor.stop()
        await first.open()
        await read.value
        await monitor.setBusy(true, source: .editor)
        await monitor.setBusy(false, source: .editor)

        #expect(await music.nowPlayingCalls == 1, "stop 之後不得再補讀，也不得留下待補的理由")
    }

    @Test func noReadAfterStop() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        await monitor.stop()
        await monitor.playerDidChange()
        await monitor.tick()
        await monitor.forceRefresh()

        #expect(await music.nowPlayingCalls == 0, "stop 之後晚到的回呼不得再讀 Music")
    }
}
