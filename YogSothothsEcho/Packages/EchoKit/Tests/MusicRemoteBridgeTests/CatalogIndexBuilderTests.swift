#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// T3（sprint-3-detail.md §4.5）：專輯索引純函式。名稱一律自編。

func rawTrack(_ trackID: UInt64, album: UInt64?, title: String? = "Track", albumTitle: String? = "Album A",
              albumArtist: String? = "Artist A", artist: String? = "Artist A", disc: Int = 1, number: Int = 1,
              modified: Date? = Date(timeIntervalSince1970: 1_700_000_000), artwork: Bool = true,
              sortAlbumTitle: String? = nil, sortAlbumArtist: String? = nil, duration: Double? = nil) -> RawTrack {
    RawTrack(trackID: trackID, albumID: album, albumTitle: albumTitle, sortAlbumTitle: sortAlbumTitle, albumArtist: albumArtist,
             sortAlbumArtist: sortAlbumArtist, artist: artist, title: title, discNumber: disc, trackNumber: number,
             modifiedAt: modified, hasArtwork: artwork, duration: duration)
}

struct CatalogIndexBuilderTests {
    private func build(_ songs: [RawTrack], skipped: [SkipReason: Int] = [:]) -> CatalogIndex {
        CatalogIndexBuilder.build(CatalogLoad(songs: songs, skipped: skipped))
    }

    @Test func groupsByAlbumIDAndCountsTracks() {
        let index = build([rawTrack(1, album: 10), rawTrack(2, album: 10, number: 2), rawTrack(3, album: 20, albumTitle: "Album B")])
        #expect(index.albums.count == 2)
        #expect(index.albums.first { $0.id == CatalogIndexBuilder.hex(10) }?.trackCount == 2)
    }

    @Test func idsAreSixteenLowercaseHex() {
        let index = build([rawTrack(1, album: 0xABC)])
        #expect(index.albums[0].id == "0000000000000abc")
    }

    @Test func titleIsModeAcrossTracks() {
        let index = build([rawTrack(1, album: 10, albumTitle: "Odd", number: 1), rawTrack(2, album: 10, albumTitle: "Even", number: 2),
                           rawTrack(3, album: 10, albumTitle: "Even", number: 3)])
        #expect(index.albums[0].title == "Even")
    }

    @Test func titleTieGoesToEarliestDiscAndTrack() {
        let index = build([rawTrack(1, album: 10, albumTitle: "Later", disc: 2, number: 1),
                           rawTrack(2, album: 10, albumTitle: "Earlier", disc: 1, number: 5)])
        #expect(index.albums[0].title == "Earlier")
    }

    @Test func artistFallsBackToTrackArtistMode() {
        let index = build([rawTrack(1, album: 10, albumArtist: nil, artist: "Solo"), rawTrack(2, album: 10, albumArtist: "", artist: "Solo", number: 2)])
        #expect(index.albums[0].artist == "Solo")
    }

    @Test func missingNamesBecomeEmptyStrings() {
        let index = build([rawTrack(1, album: 10, title: nil, albumTitle: nil, albumArtist: nil, artist: nil)])
        #expect(index.albums[0].title.isEmpty && index.albums[0].artist.isEmpty)
    }

    @Test func longNamesAreClamped() {
        let index = build([rawTrack(1, album: 10, albumTitle: String(repeating: "x", count: 1000))])
        #expect(index.albums[0].title.count == CatalogLimits.maxTextCharacters)
    }

    @Test func representativeIsEarliestTrackWithArtwork() {
        let index = build([rawTrack(1, album: 10, number: 1, artwork: false), rawTrack(2, album: 10, number: 2),
                           rawTrack(3, album: 10, number: 3)])
        #expect(index.representative[CatalogIndexBuilder.hex(10)] == 2)
        #expect(index.albums[0].artworkToken != nil)
    }

    @Test func noArtworkMeansNilToken() {
        let index = build([rawTrack(1, album: 10, artwork: false)])
        #expect(index.albums[0].artworkToken == nil)
        #expect(index.representative[CatalogIndexBuilder.hex(10)] == nil)
    }

    @Test func artworkTokenChangesWithModifiedDate() {
        let a = build([rawTrack(1, album: 10)]).albums[0].artworkToken
        let b = build([rawTrack(1, album: 10, modified: Date(timeIntervalSince1970: 1_800_000_000))]).albums[0].artworkToken
        #expect(a != nil && a != b)
    }

    @Test func sortsByAlbumArtistThenTitleThenID() {
        let index = build([rawTrack(1, album: 3, albumTitle: "Beta", albumArtist: "Zed"),
                           rawTrack(2, album: 2, albumTitle: "Beta", albumArtist: "Amy"),
                           rawTrack(3, album: 1, albumTitle: "Alpha", albumArtist: "Amy"),
                           rawTrack(4, album: 4, albumTitle: "Beta", albumArtist: "Amy")])
        #expect(index.albums.map(\.id) == [1, 2, 4, 3].map(CatalogIndexBuilder.hex))
    }

    @Test func sortKeysPreferSortFields() {
        let index = build([rawTrack(1, album: 1, albumArtist: "The Band", sortAlbumArtist: "Band"),
                           rawTrack(2, album: 2, albumArtist: "Arc")])
        #expect(index.albums.map(\.id) == [2, 1].map(CatalogIndexBuilder.hex))
    }

    @Test func positionsMatchOrder() {
        let index = build([rawTrack(1, album: 2, albumArtist: "B"), rawTrack(2, album: 1, albumArtist: "A")])
        for (i, album) in index.albums.enumerated() { #expect(index.position[album.id] == i) }
    }

    @Test func skippedCountsPassThrough() {
        let index = build([rawTrack(1, album: 10)], skipped: [.zeroAlbumID: 2, .noAlbum: 1])
        #expect(index.skipped == [.zeroAlbumID: 2, .noAlbum: 1])
    }

    @Test func versionIsStableAcrossInputOrder() {
        let songs = [rawTrack(1, album: 10), rawTrack(2, album: 10, number: 2), rawTrack(3, album: 20)]
        #expect(build(songs).version == build(songs.reversed()).version)
        #expect(build(songs).version.count == CatalogLimits.hexIDLength)
    }

    /// 每個欄位單獨改變都必須換版（Codex 第 1 輪 #2）
    @Test(arguments: [
        rawTrack(1, album: 11), rawTrack(1, album: 10, title: "Track2"), rawTrack(1, album: 10, albumTitle: "Album Z"),
        rawTrack(1, album: 10, albumArtist: "Other"), rawTrack(1, album: 10, artist: "Other"), rawTrack(1, album: 10, disc: 2),
        rawTrack(1, album: 10, number: 2), rawTrack(1, album: 10, modified: nil), rawTrack(1, album: 10, artwork: false),
        rawTrack(1, album: 10, sortAlbumTitle: "S"), rawTrack(1, album: 10, sortAlbumArtist: "S"), rawTrack(9, album: 10),
    ])
    func everyFieldChangesVersion(changed: RawTrack) {
        let base = build([rawTrack(1, album: 10), rawTrack(2, album: 30, albumTitle: "Other Album")]).version
        let other = build([changed, rawTrack(2, album: 30, albumTitle: "Other Album")]).version
        #expect(base != other)
    }

    /// 長度前綴：欄位邊界移動不得產生相同雜湊
    @Test func fieldBoundariesAreUnambiguous() {
        let a = build([rawTrack(1, album: 10, title: "ab", albumTitle: "c")]).version
        let b = build([rawTrack(1, album: 10, title: "a", albumTitle: "bc")]).version
        #expect(a != b)
    }

    @Test func nilAndEmptyAreDistinctInVersion() {
        #expect(build([rawTrack(1, album: 10, artist: nil)]).version != build([rawTrack(1, album: 10, artist: "")]).version)
    }

    @Test func searchCorpusIsFoldedAndIncludesTrackTitles() {
        let index = build([rawTrack(1, album: 10, title: "Ｈｉｄｄｅｎ Song", albumTitle: "Shown")])
        #expect(index.searchCorpus[0].contains("hidden song"))
        #expect(index.searchCorpus[0].contains("shown"))
    }

    @Test func emptyLoadHasNoAlbums() {
        let index = build([])
        #expect(index.albums.isEmpty && index.version.count == CatalogLimits.hexIDLength)
    }
}
#endif
