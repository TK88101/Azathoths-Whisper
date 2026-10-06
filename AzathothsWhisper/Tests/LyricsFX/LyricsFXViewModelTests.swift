import Foundation
import Testing

@testable import AzathothsWhisper

// 項 2＋4：歌詞特效的狀態層（無 View，A1 計劃 §3.4）。歌詞為編造句
@MainActor
@Suite("LyricsFXViewModel")
struct LyricsFXViewModelTests {
    static let track = TrackInfo.fixture(id: "0123456789ABCDEF")
    static let lyrics = "[Verse]\nLanterns over the river\nAsh in the wind"
    static let metadata = TrackMetadata(genre: "Black Metal", duration: 200)

    struct Harness {
        let music: MockMusicClient
        let poll: GatedPollClock
        let model: LyricsFXViewModel
    }

    private func harness() async -> Harness {
        let music = MockMusicClient()
        await music.setPlaybackPositions([.success(PlaybackPosition(persistentID: Self.track.persistentID, seconds: 1, state: .playing, readAt: .now, roundTrip: .zero))])
        let poll = GatedPollClock()
        let model = LyricsFXViewModel(positionClock: PlaybackPositionClock(music: music, pollClock: poll))
        return Harness(music: music, poll: poll, model: model)
    }

    @Test func aNewTrackBuildsTheTimelineAndStyle() async throws {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        #expect(h.model.identity == .init(persistentID: Self.track.persistentID, revision: 1))
        #expect(h.model.status == .present)
        let timeline = try #require(h.model.timeline)
        #expect(timeline.source == .estimated)
        #expect(timeline.lines.map(\.text) == ["Lanterns over the river", "Ash in the wind"])
        #expect(h.model.genreStyle == GenreStyle(family: .frost))
        #expect(h.model.statusText == nil)
    }

    @Test func embeddedLRCWorksWithoutADuration() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: "[00:01.00]Lanterns\n[00:03.00]Ash"))
        #expect(h.model.timeline?.source == .embeddedLRC)
    }

    @Test func theSameTrackWithTheSameLyricsIsANoOp() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.handle(.trackChanged(Self.track, existingLyrics: "[Verse]\rLanterns over the river\rAsh in the wind", metadata: Self.metadata))
        #expect(h.model.identity?.revision == 1)
    }

    /// 同一首重發、詞沒變但 genre／曲長這次才讀到：要重建（codex review P2）
    @Test func sameTrackWithNewlyReadMetadataRebuilds() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: .unknown))
        #expect(h.model.timeline == nil, "沒有曲長估不出來")
        #expect(h.model.genreStyle?.family == .mono)
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        #expect(h.model.timeline != nil)
        #expect(h.model.genreStyle?.family == .frost)
        #expect(h.model.identity?.revision == 2)
    }

    /// 本 app 寫入後：onSaved 與 monitor 的 lyricsChanged 先後到，revision 只 +1（A1 計劃 §3.2）
    @Test func aWriteSeenTwiceBumpsTheRevisionOnce() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: "", metadata: Self.metadata))
        #expect(h.model.status == .missing)
        h.model.lyricsUpdated(persistentID: Self.track.persistentID, text: Self.lyrics)
        h.model.handle(.lyricsChanged(persistentID: Self.track.persistentID, lyrics: Self.lyrics))
        #expect(h.model.identity?.revision == 2)
        #expect(h.model.status == .present)
        #expect(h.model.timeline != nil)
    }

    @Test func updatesForAnotherTrackAreIgnored() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.lyricsUpdated(persistentID: "FFFFFFFFFFFFFFFF", text: "Quiet harbor")
        h.model.handle(.lyricsChanged(persistentID: "FFFFFFFFFFFFFFFF", lyrics: "Quiet harbor"))
        #expect(h.model.identity?.revision == 1)
        #expect(h.model.timeline?.lines.first?.text == "Lanterns over the river")
    }

    @Test func anOldIdentityIsNoLongerCurrent() async throws {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        let old = try #require(h.model.identity)
        #expect(h.model.isCurrent(old))
        h.model.lyricsUpdated(persistentID: Self.track.persistentID, text: "Quiet harbor")
        #expect(!h.model.isCurrent(old))
    }

    /// 未播放：清空、停讀、顯示既有狀態字；舊 identity 從此失效，同一首回來也是新 revision（Codex R2）
    @Test func notPlayingClearsEverythingAndInvalidatesTheIdentity() async throws {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.setVisible(true)
        await waitFor { await h.music.playbackPositionCalls == 1 }
        let old = try #require(h.model.identity)

        h.model.handle(.notPlaying)

        #expect(h.model.timeline == nil)
        #expect(h.model.identity == nil)
        #expect(!h.model.isCurrent(old))
        #expect(h.model.statusText == StatusText.noTrackPlaying)
        #expect(h.model.positionClock.anchor == nil)
        await h.poll.releaseAll()
        await settle()
        #expect(await h.music.playbackPositionCalls == 1, "未播放後不再讀位置")

        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        #expect(h.model.identity?.revision == 2)
        #expect(h.model.statusText == nil)
    }

    @Test func permissionDeniedClearsWithItsOwnStatusText() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.handle(.permissionDenied)
        #expect(h.model.timeline == nil)
        #expect(h.model.identity == nil)
        #expect(h.model.statusText == StatusText.accessDenied)
    }

    /// 升起 ≠ 有詞（母計劃 §2.1 R1-7①）：沒有詞就不建時間軸、可見也不讀位置
    @Test(arguments: [nil, "", "  "] as [String?])
    func withoutLyricsThereIsNoTimelineAndNoReading(lyrics: String?) async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: lyrics, metadata: Self.metadata))
        h.model.setVisible(true)
        await settle()
        #expect(h.model.status != .present)
        #expect(h.model.timeline == nil)
        #expect(await h.music.playbackPositionCalls == 0)
    }

    @Test func markedNoLyricsComesFromTheSharedMarks() async {
        let h = await harness()
        h.model.isMarkedNoLyrics = { $0 == Self.track.persistentID }
        h.model.handle(.trackChanged(Self.track, existingLyrics: "", metadata: Self.metadata))
        #expect(h.model.status == .markedNone)
    }

    /// 使用者在 Cover Flow 標記「這首沒有詞」：不發播放事件，要靠 refreshStatus 重判（simplify R2 altitude）
    @Test func refreshStatusPicksUpANewNoLyricsMark() async {
        let h = await harness()
        var marked = false
        h.model.isMarkedNoLyrics = { _ in marked }
        h.model.handle(.trackChanged(Self.track, existingLyrics: "", metadata: Self.metadata))
        #expect(h.model.status == .missing)
        marked = true
        h.model.refreshStatus()
        #expect(h.model.status == .markedNone)
        #expect(h.model.identity?.revision == 1, "詞沒變，不換 revision")
    }

    @Test func refreshStatusWithoutATrackDoesNothing() async {
        let h = await harness()
        h.model.handle(.notPlaying)
        h.model.refreshStatus()
        #expect(h.model.status == .unknown)
        #expect(h.model.statusText == StatusText.noTrackPlaying)
    }

    @Test func visibilityStartsAndStopsTheClock() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        await settle()
        #expect(await h.music.playbackPositionCalls == 0, "不可見不讀")
        h.model.setVisible(true)
        await waitFor { await h.music.playbackPositionCalls == 1 }
        h.model.setVisible(false)
        await h.poll.releaseAll()
        await settle()
        #expect(await h.music.playbackPositionCalls == 1)
    }

    @Test func albumChangesAreIgnored() async {
        let h = await harness()
        h.model.handle(.albumChanged("x"))
        #expect(h.model.identity == nil && h.model.statusText == nil)
    }

    // MARK: P2-1 同曲 metadata 補讀（A2 計劃 §3.0）

    @Test func metadataReadLaterBuildsTheMissingTimeline() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: TrackMetadata(genre: "Black Metal", duration: nil)))
        #expect(h.model.timeline == nil, "沒有曲長估不出來")
        h.model.handle(.metadataChanged(persistentID: Self.track.persistentID, metadata: Self.metadata))
        #expect(h.model.timeline != nil)
        #expect(h.model.identity?.revision == 2)
    }

    @Test func aGenreChangeUpdatesTheStyle() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.handle(.metadataChanged(persistentID: Self.track.persistentID, metadata: TrackMetadata(genre: "Death Metal", duration: 200)))
        #expect(h.model.genreStyle == GenreStyle(family: .slab))
        #expect(h.model.identity?.revision == 2)
    }

    @Test func metadataForAnotherTrackIsIgnored() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: .unknown))
        h.model.handle(.metadataChanged(persistentID: "FEDCBA9876543210", metadata: Self.metadata))
        #expect(h.model.timeline == nil)
        #expect(h.model.identity?.revision == 1)
    }

    @Test func identicalMetadataIsANoOp() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.handle(.metadataChanged(persistentID: Self.track.persistentID, metadata: Self.metadata))
        #expect(h.model.identity?.revision == 1)
    }

    /// 同一首重發（強制重讀）而這次曲長讀失敗：沿用已知值，歌詞不得消失（codex R3）
    @Test func aResentTrackWithUnreadableMetadataKeepsTheTimeline() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: .unknown))
        #expect(h.model.timeline != nil)
        #expect(h.model.genreStyle?.family == .frost)
        #expect(h.model.identity?.revision == 1)
    }

    /// 換了一首就不沿用上一首的曲長
    @Test func aDifferentTrackDoesNotInheritMetadata() async {
        let h = await harness()
        h.model.handle(.trackChanged(Self.track, existingLyrics: Self.lyrics, metadata: Self.metadata))
        h.model.handle(.trackChanged(TrackInfo.fixture(id: "FEDCBA9876543210"), existingLyrics: Self.lyrics, metadata: .unknown))
        #expect(h.model.timeline == nil)
    }
}
