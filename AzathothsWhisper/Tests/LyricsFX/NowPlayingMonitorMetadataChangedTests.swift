import Foundation
import Testing

@testable import AzathothsWhisper

// P2-1：同曲 metadata 補讀（A2 計劃 §1／§3.0）。歌詞為編造句
@Suite("NowPlayingMonitor metadataChanged")
struct NowPlayingMonitorMetadataChangedTests {
    private let track = TrackInfo.fixture()
    private let full = TrackMetadata(genre: "Black Metal", duration: 245)

    private func run(_ responses: [MockMusicClient.Response], forceRefreshAfter: Int? = nil) async -> [PlaybackEvent] {
        let music = MockMusicClient(script: responses, repeatLast: false)
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        for index in 0..<responses.count {
            if index == forceRefreshAfter {
                await monitor.forceRefresh()
            } else {
                await monitor.tick()
            }
        }
        await monitor.stop()
        var events: [PlaybackEvent] = []
        for await event in monitor.events {
            if case .albumChanged = event { continue }
            events.append(event)
        }
        return events
    }

    @Test func aDurationReadLaterOnTheSameTrackIsReportedOnce() async {
        let partial = TrackMetadata(genre: "Black Metal", duration: nil)
        let events = await run([
            .track(track, lyrics: "a", metadata: partial),
            .track(track, lyrics: "a", metadata: full),
            .track(track, lyrics: "a", metadata: full),
        ])
        #expect(events == [
            .trackChanged(track, existingLyrics: "a", metadata: partial),
            .metadataChanged(persistentID: track.persistentID, metadata: full),
        ])
    }

    /// 讀不到不是變更：不發事件，也不得抹掉已知值
    @Test func aFailedReadNeitherReportsNorForgets() async {
        let events = await run([
            .track(track, lyrics: "a", metadata: full),
            .track(track, lyrics: "a", metadata: .unknown),
            .track(track, lyrics: "a", metadata: full),
        ])
        #expect(events == [.trackChanged(track, existingLyrics: "a", metadata: full)])
    }

    @Test func aDifferentKnownValueIsAChange() async {
        let edited = TrackMetadata(genre: "Doom", duration: 245)
        let events = await run([
            .track(track, lyrics: "a", metadata: full),
            .track(track, lyrics: "a", metadata: TrackMetadata(genre: "Doom", duration: nil)),
        ])
        #expect(events == [
            .trackChanged(track, existingLyrics: "a", metadata: full),
            .metadataChanged(persistentID: track.persistentID, metadata: edited),
        ])
    }

    @Test func aNewTrackIsOnlyATrackChange() async {
        let other = TrackInfo.fixture(id: "PID2")
        let events = await run([.track(track, lyrics: "a", metadata: .unknown), .track(other, lyrics: "a", metadata: full)])
        #expect(events == [
            .trackChanged(track, existingLyrics: "a", metadata: .unknown),
            .trackChanged(other, existingLyrics: "a", metadata: full),
        ])
    }

    @Test func notPlayingResetsTheCache() async {
        let events = await run([
            .track(track, lyrics: "a", metadata: full),
            .notPlaying,
            .track(track, lyrics: "a", metadata: .unknown),
            .track(track, lyrics: "a", metadata: full),
        ])
        #expect(events == [
            .trackChanged(track, existingLyrics: "a", metadata: full),
            .notPlaying,
            .trackChanged(track, existingLyrics: "a", metadata: .unknown),
            .metadataChanged(persistentID: track.persistentID, metadata: full),
        ])
    }

    @Test func forceRefreshResetsTheCache() async {
        let events = await run([
            .track(track, lyrics: "a", metadata: full),
            .track(track, lyrics: "a", metadata: .unknown),
            .track(track, lyrics: "a", metadata: full),
        ], forceRefreshAfter: 1)
        #expect(events == [
            .trackChanged(track, existingLyrics: "a", metadata: full),
            .trackChanged(track, existingLyrics: "a", metadata: .unknown),
            .metadataChanged(persistentID: track.persistentID, metadata: full),
        ])
    }

    @Test func lyricsAndMetadataChangingTogetherReportLyricsFirst() async {
        let events = await run([
            .track(track, lyrics: "a", metadata: .unknown),
            .track(track, lyrics: "b", metadata: full),
        ])
        #expect(events == [
            .trackChanged(track, existingLyrics: "a", metadata: .unknown),
            .lyricsChanged(persistentID: track.persistentID, lyrics: "b"),
            .metadataChanged(persistentID: track.persistentID, metadata: full),
        ])
    }
}

@Suite("TrackMetadata mergingLatestKnown")
struct TrackMetadataMergeTests {
    @Test func nilKeepsTheKnownValue() {
        let known = TrackMetadata(genre: "Pop", duration: 100)
        #expect(known.mergingLatestKnown(with: .unknown) == known)
    }

    @Test func aKnownValueReplaces() {
        let merged = TrackMetadata(genre: "Pop", duration: nil).mergingLatestKnown(with: TrackMetadata(genre: nil, duration: 90))
        #expect(merged == TrackMetadata(genre: "Pop", duration: 90))
    }

    /// `""`／`0`＝Music 明確說沒有，是已知值（A1 計劃 §2）
    @Test func emptyAndZeroAreKnownValues() {
        let merged = TrackMetadata(genre: "Pop", duration: 100).mergingLatestKnown(with: TrackMetadata(genre: "", duration: 0))
        #expect(merged == TrackMetadata(genre: "", duration: 0))
    }

    @Test func aNonFiniteDurationCountsAsUnreadable() {
        let known = TrackMetadata(genre: nil, duration: 100)
        #expect(known.mergingLatestKnown(with: TrackMetadata(genre: nil, duration: .nan)) == known)
        #expect(known.mergingLatestKnown(with: TrackMetadata(genre: nil, duration: .infinity)) == known)
    }
}
