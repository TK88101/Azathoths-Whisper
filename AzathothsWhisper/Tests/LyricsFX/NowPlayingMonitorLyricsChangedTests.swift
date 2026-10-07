import Foundation
import Testing

@testable import AzathothsWhisper

// 項 2：同曲改詞事件（母計劃 §2.8 Codex R1-7②；A1 計劃 §3.2）。歌詞為編造句
@Suite("NowPlayingMonitor lyricsChanged")
struct NowPlayingMonitorLyricsChangedTests {
    private let track = TrackInfo.fixture()

    private func run(_ responses: [MockMusicClient.Response], ticks: Int? = nil) async -> [PlaybackEvent] {
        let music = MockMusicClient(script: responses, repeatLast: false)
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        for _ in 0..<(ticks ?? responses.count) { await monitor.tick() }
        await monitor.stop()
        var events: [PlaybackEvent] = []
        for await event in monitor.events where !isAlbum(event) { events.append(event) }
        return events
    }

    private func isAlbum(_ event: PlaybackEvent) -> Bool {
        if case .albumChanged = event { return true }
        return false
    }

    @Test func editedLyricsOnTheSameTrackAreReportedOnce() async {
        let events = await run([.track(track, lyrics: "Lanterns"), .track(track, lyrics: "Lanterns over water"), .track(track, lyrics: "Lanterns over water")])
        #expect(events == [
            .trackChanged(track, existingLyrics: "Lanterns"),
            .lyricsChanged(persistentID: track.persistentID, lyrics: "Lanterns over water"),
        ])
    }

    @Test func onlyLineEndingsChangingIsNotAnEdit() async {
        let events = await run([.track(track, lyrics: "a\nb"), .track(track, lyrics: "a\rb")])
        #expect(events.count == 1)
    }

    /// 讀不到不是改詞：不發事件，也不得抹掉上次的指紋
    @Test func aFailedLyricsReadIsNotAnEditAndKeepsTheFingerprint() async {
        let events = await run([.track(track, lyrics: "a"), .track(track, lyrics: nil), .track(track, lyrics: "a")])
        #expect(events == [.trackChanged(track, existingLyrics: "a")])
    }

    /// 由讀不到變成讀得到：同一首的歌詞快照現在可用了（A1 計劃 §3.2，Q3）
    @Test func lyricsBecomingReadableAreReported() async {
        let events = await run([.track(track, lyrics: nil), .track(track, lyrics: "")])
        #expect(events == [
            .trackChanged(track, existingLyrics: nil),
            .lyricsChanged(persistentID: track.persistentID, lyrics: ""),
        ])
    }

    @Test func aNewTrackIsOnlyATrackChange() async {
        let other = TrackInfo.fixture(id: "PID2")
        let events = await run([.track(track, lyrics: "a"), .track(other, lyrics: "b")])
        #expect(events == [.trackChanged(track, existingLyrics: "a"), .trackChanged(other, existingLyrics: "b")])
    }

    @Test func notPlayingForgetsTheFingerprint() async {
        let events = await run([.track(track, lyrics: "a"), .notPlaying, .track(track, lyrics: "a")])
        #expect(events == [.trackChanged(track, existingLyrics: "a"), .notPlaying, .trackChanged(track, existingLyrics: "a")])
    }

    /// forceRefresh 重發 trackChanged（帶最新歌詞），不夾帶 lyricsChanged
    @Test func forceRefreshResendsTheTrackWithoutALyricsChange() async {
        let music = MockMusicClient(script: [.track(track, lyrics: "a"), .track(track, lyrics: "b")], repeatLast: false)
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        await monitor.tick()
        await monitor.forceRefresh()
        await monitor.stop()
        var events: [PlaybackEvent] = []
        for await event in monitor.events where !isAlbum(event) { events.append(event) }
        #expect(events == [.trackChanged(track, existingLyrics: "a"), .trackChanged(track, existingLyrics: "b")])
    }

    @Test func trackChangedCarriesTheMetadataOfTheSameRead() async {
        let metadata = TrackMetadata(genre: "Black Metal", duration: 245)
        let events = await run([.track(track, lyrics: "a", metadata: metadata)])
        #expect(events == [.trackChanged(track, existingLyrics: "a", metadata: metadata)])
    }
}
