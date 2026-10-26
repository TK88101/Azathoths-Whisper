import Foundation
import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// S6 T7（sprint-6-detail.md §4.6）：詳情層的總長、碟片分組、逐曲歌手、逐列淡入延遲、Play 鈕
struct AlbumDetailPresentationTests {
    func song(_ id: Int, disc: Int = 1, number: Int, artist: String = "", duration: Double? = 180) -> TrackSummary {
        TrackSummary(id: String(format: "%016llx", UInt64(id)), title: "Made-up \(id)", artist: artist, disc: disc, number: number,
                     duration: duration)
    }

    @Test func totalDurationSkipsMissingValues() {
        #expect(AlbumDetailPresentation.totalDuration([song(1, number: 1), song(2, number: 2, duration: nil), song(3, number: 3, duration: 20)]) == 200)
        #expect(AlbumDetailPresentation.totalDuration([song(1, number: 1, duration: nil)]) == nil)
        #expect(AlbumDetailPresentation.totalDuration([]) == nil)
    }

    /// 依碟片、曲序排序；多碟才顯示碟片標題
    @Test func discTitlesAndOrdering() {
        let songs = [song(1, disc: 2, number: 2), song(2, disc: 1, number: 2), song(3, disc: 2, number: 1), song(4, disc: 1, number: 1)]
        #expect(AlbumDetailPresentation.showsDiscTitles(songs))
        #expect(!AlbumDetailPresentation.showsDiscTitles([song(1, number: 1), song(2, number: 2)]))
        #expect(AlbumDetailPresentation.ordered(songs).map(\.id) == [songs[3], songs[1], songs[2], songs[0]].map(\.id))
    }

    /// 逐曲歌手：空字串或與專輯藝人相同＝不顯示
    @Test func perTrackArtistShowsOnlyWhenDifferent() {
        #expect(!AlbumDetailPresentation.showsArtist(song(1, number: 1, artist: ""), albumArtist: "Band"))
        #expect(!AlbumDetailPresentation.showsArtist(song(1, number: 1, artist: "Band"), albumArtist: "Band"))
        #expect(AlbumDetailPresentation.showsArtist(song(1, number: 1, artist: "Band, Guest"), albumArtist: "Band"))
    }

    /// Play 鈕：0 首、載入中、未連線時停用
    @Test func playButtonEnablement() {
        #expect(AlbumDetailPresentation.playEnabled(songCount: 3, phase: .ready, canPlay: true))
        #expect(!AlbumDetailPresentation.playEnabled(songCount: 0, phase: .ready, canPlay: true))
        #expect(!AlbumDetailPresentation.playEnabled(songCount: 3, phase: .loading, canPlay: false))
        #expect(!AlbumDetailPresentation.playEnabled(songCount: 3, phase: .ready, canPlay: false))
    }

    /// 首數與總長文案在三語都有翻譯
    @Test func summaryStringIsLocalizedInThreeLanguages() throws {
        for language in ["en", "zh-Hant", "ja"] {
            let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
                ?? Bundle.main.path(forResource: "Localizable", ofType: "stringsdict", inDirectory: nil, forLocalization: language))
            let table = NSDictionary(contentsOfFile: path)
            let dict = Bundle.main.path(forResource: "Localizable", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
                .flatMap { NSDictionary(contentsOfFile: $0) }
            #expect(table?["%lld songs"] != nil || dict?["%lld songs"] != nil, "\(language)")
        }
    }
}

/// S6 T7：詳情層 Play 鈕＝排序後第一首、以本專輯脈絡送 play.track（AlbumTracksViewModel 邏輯不變，只加這個入口）
@MainActor
struct AlbumTracksPlayFirstTests {
    let client = FakePlaybackClient()
    let model = AlbumTracksViewModel(sleep: { _ in })

    @Test func playFirstSendsTheFirstSortedSong() async {
        client.lock.withLock {
            client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks([
                TrackSummary(id: PlaybackSamples.t2, title: "B", disc: 2, number: 1, duration: 1),
                TrackSummary(id: PlaybackSamples.t3, title: "C", disc: 1, number: 2, duration: 1),
                TrackSummary(id: PlaybackSamples.t1, title: "A", disc: 1, number: 1, duration: 1),
            ]))
        }
        model.attach(client)
        await model.open(PlaybackSamples.albumSummary)
        await model.playFirst()
        #expect(client.recorded.last == "play:\(PlaybackSamples.t1)")
    }

    @Test func playFirstOnEmptyAlbumSendsNothing() async {
        client.lock.withLock { client.tracks[PlaybackSamples.album] = .success(PlaybackSamples.tracks([])) }
        model.attach(client)
        await model.open(PlaybackSamples.albumSummary)
        await model.playFirst()
        #expect(!client.recorded.contains { $0.hasPrefix("play:") })
    }
}
