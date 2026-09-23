import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE B-01…B-03、A-12：輪詢事件序列（可注入時鐘，零真實延時）
@Suite("NowPlayingMonitor")
struct NowPlayingMonitorTests {
    private func collect(_ monitor: NowPlayingMonitor, expecting count: Int) async -> [PlaybackEvent] {
        var events: [PlaybackEvent] = []
        for await event in monitor.events {
            events.append(event)
            if events.count == count { break }
        }
        return events
    }

    @Test func emitsAlbumAndTrackOnFirstTick() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: "existing")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 2)
        await monitor.tick()
        let events = await collected

        #expect(events == [.albumChanged(track.albumKey), .trackChanged(track, existingLyrics: "existing")])
    }

    @Test func doesNotRepeatEventsForSameTrack() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 2)
        await monitor.tick()
        await monitor.tick()
        await monitor.tick()
        let events = await collected

        #expect(events.count == 2, "同一首歌重複輪詢不得再發事件")
    }

    // 已批准的安全修正：同 artist/title 但不同 persistentID 必須視為換曲
    @Test func detectsTrackChangeByPersistentIDEvenWhenTitlesMatch() async {
        let first = TrackInfo.fixture(id: "PID1")
        let second = TrackInfo.fixture(id: "PID2")
        let music = MockMusicClient(
            script: [.track(first, lyrics: "a"), .track(second, lyrics: "b")],
            repeatLast: false
        )
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 3)
        await monitor.tick()
        await monitor.tick()
        let events = await collected

        let trackEvents = events.filter { if case .trackChanged = $0 { return true } else { return false } }
        #expect(trackEvents.count == 2)
    }

    /// 歌詞必須屬於同一輪送出的那首（計劃 §3 事實 11 的錯位鎖定：舊替身把 B 的歌詞配給 A）
    @Test func lyricsBelongToTheTrackServedInTheSameTick() async {
        let first = TrackInfo.fixture(id: "PID1")
        let second = TrackInfo.fixture(id: "PID2")
        let music = MockMusicClient(
            script: [.track(first, lyrics: "first lyrics"), .track(second, lyrics: "")],
            repeatLast: false
        )
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 2)
        await monitor.tick()
        let events = await collected

        #expect(events.last == .trackChanged(first, existingLyrics: "first lyrics"))
    }

    /// 計劃 D9／AC12：曲目欄位與歌詞只來自同一次讀取（不再先讀曲目、再另讀歌詞）
    @Test func trackAndLyricsComeFromASingleRead() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: "verse")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 2)
        await monitor.tick()
        let events = await collected

        #expect(events.last == .trackChanged(track, existingLyrics: "verse"))
        #expect(await music.nowPlayingCalls == 1, "一輪只讀一次（曲目與歌詞同一次讀取）")
    }

    /// 歌詞讀取失敗＝nil（unknown），不得折疊成空字串（那會被當成缺詞而降下 Editor）
    @Test func unreadableLyricsArriveAsNil() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: nil)])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 2)
        await monitor.tick()
        let events = await collected

        #expect(events.last == .trackChanged(track, existingLyrics: nil))
    }

    @Test func emitsAlbumChangedOnlyWhenArtistAlbumPairChanges() async {
        let first = TrackInfo.fixture(id: "PID1", title: "One", album: "Damage Done")
        let sameAlbum = TrackInfo.fixture(id: "PID2", title: "Two", album: "Damage Done")
        let otherAlbum = TrackInfo.fixture(id: "PID3", title: "Three", album: "Fiction")
        let music = MockMusicClient(
            script: [.track(first, lyrics: ""), .track(sameAlbum, lyrics: ""), .track(otherAlbum, lyrics: "")],
            repeatLast: false
        )
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 5)
        await monitor.tick()
        await monitor.tick()
        await monitor.tick()
        let events = await collected

        let albumEvents = events.filter { if case .albumChanged = $0 { return true } else { return false } }
        #expect(albumEvents.count == 2, "同專輯換曲不得重發 albumChanged")
    }

    // py:1108-1128：paused 仍有當前曲；只有 stopped/無曲才是 notPlaying
    @Test func pausedStateStillReportsCurrentTrack() {
        #expect(PlayerState.paused.hasCurrentTrack)
        #expect(PlayerState.playing.hasCurrentTrack)
        #expect(PlayerState.stopped.hasCurrentTrack == false)
        #expect(PlayerState.other("kPSF").hasCurrentTrack == false)
    }

    @Test func emitsNotPlayingOnceWhenStopped() async {
        let music = MockMusicClient(script: [.notPlaying])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 1)
        await monitor.tick()
        await monitor.tick()
        let events = await collected

        #expect(events == [.notPlaying])
    }

    @Test func skipsPollWhileBusy() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        await monitor.setBusy(true, source: .editor)
        await monitor.tick()
        #expect(await music.currentTrackCalls == 0, "busy 期間不得查詢 Music")

        await monitor.setBusy(false, source: .editor)
        await monitor.tick()
        #expect(await music.currentTrackCalls == 1)
    }

    @Test func emitsPermissionDeniedOnTCCFailure() async {
        let music = MockMusicClient(script: [.failure(.permissionDenied)])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 1)
        await monitor.tick()
        let events = await collected

        #expect(events == [.permissionDenied])
    }

    @Test func forceRefreshReemitsCurrentTrack() async {
        let track = TrackInfo.fixture()
        let music = MockMusicClient(script: [.track(track, lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        async let collected = collect(monitor, expecting: 3)
        await monitor.tick()          // albumChanged + trackChanged
        await monitor.forceRefresh()  // trackChanged 再一次
        let events = await collected

        #expect(events.last == .trackChanged(track, existingLyrics: "l"))
    }

    // ACCEPTANCE H-11：Cover Flow 穩定排序（disc → track → AE 返回序）
    @Test func albumTracksSortStably() {
        let unsorted = [
            AlbumTrack.fixture(id: "d2t1", disc: 2, track: 1),
            AlbumTrack.fixture(id: "d1t2", disc: 1, track: 2),
            AlbumTrack.fixture(id: "d1t1", disc: 1, track: 1),
            AlbumTrack.fixture(id: "unknownA", disc: 0, track: 0),
            AlbumTrack.fixture(id: "unknownB", disc: 0, track: 0),
        ]
        let sorted = unsorted.sortedForDisplay().map(\.persistentID)
        #expect(sorted == ["unknownA", "unknownB", "d1t1", "d1t2", "d2t1"])
    }
}
