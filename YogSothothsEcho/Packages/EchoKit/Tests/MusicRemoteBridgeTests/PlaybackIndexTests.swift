#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T3（sprint-4-detail.md §4.2、§4.5 步驟 1）：索引增補——曲目時長、每張專輯的曲序、trackID→albumID、許可閘門。
// 許可閘門自 S0 `ShortcutGate`／`AlbumSuffix`（Spike/Sources/SpikeCore/FP01.swift）移植，S0 的測試一併移植；名稱一律自編。

struct AlbumSuffixTests {
    private let album = [AlbumTrackRef(id: "a", disc: 1, number: 1), AlbumTrackRef(id: "b", disc: 1, number: 2),
                         AlbumTrackRef(id: "c", disc: 2, number: 1), AlbumTrackRef(id: "d", disc: 2, number: 2)]

    @Test func ordersByDiscThenNumberAndSlicesFromTarget() {
        #expect(AlbumSuffix.ordered(album.reversed()) == ["a", "b", "c", "d"])
        #expect(AlbumSuffix.expected(album, from: "b") == ["b", "c", "d"])
    }

    @Test func positionIsOneBased() {
        #expect(AlbumSuffix.position(of: "c", in: album) == 3)
        #expect(AlbumSuffix.position(of: "z", in: album) == nil)
    }

    @Test func missingDiscCountsAsDiscOne() {
        let tracks = [AlbumTrackRef(id: "x", disc: 0, number: 2), AlbumTrackRef(id: "y", disc: 1, number: 1)]
        #expect(AlbumSuffix.ordered(tracks) == ["y", "x"])
    }

    @Test func unknownTargetHasNoExpectation() {
        #expect(AlbumSuffix.expected(album, from: "z") == nil)
    }

    @Test func duplicatePositionsHaveNoDefinedOrder() {
        #expect(AlbumSuffix.ordered(album + [AlbumTrackRef(id: "e", disc: 1, number: 2)]) == nil)
    }

    @Test func zeroTrackNumberHasNoDefinedOrder() {
        #expect(AlbumSuffix.ordered([AlbumTrackRef(id: "a", disc: 1, number: 0)]) == nil)
    }
}

struct PlayAdmissionTests {
    private let songs = [AlbumTrackRef(id: "a", disc: 1, number: 1), AlbumTrackRef(id: "b", disc: 1, number: 2)]

    private func index(_ entries: [(String, String)]) -> [String: Set<String>] {
        PlayAdmission.titleIndex(entries.map { (title: $0.0, albumID: $0.1) })
    }

    @Test func uniqueConsistentTitleIsAllowed() {
        let titles = index([("Night Drive", "al1"), ("Night Drive", "al1"), ("Day Trip", "al2")])
        #expect(PlayAdmission.check(albumID: "al1", albumTitles: ["Night Drive", "Night Drive"], songs: songs, titleIndex: titles) == nil)
    }

    @Test func emptyTitleIsRefused() {
        #expect(PlayAdmission.check(albumID: "al1", albumTitles: ["", ""], songs: songs, titleIndex: [:]) == .gateEmptyTitle)
        #expect(PlayAdmission.check(albumID: "al1", albumTitles: [], songs: [], titleIndex: [:]) == .gateEmptyTitle)
    }

    @Test func inconsistentTitlesWithinAlbumAreRefused() {
        let titles = index([("Night Drive", "al1"), ("Night Drive (Deluxe)", "al1")])
        #expect(PlayAdmission.check(albumID: "al1", albumTitles: ["Night Drive", "Night Drive (Deluxe)"], songs: songs,
                                    titleIndex: titles) == .gateInconsistentTitle)
    }

    @Test func sameTitleOnAnotherAlbumIsRefused() {
        let titles = index([("Night Drive", "al1"), ("Night Drive", "al2")])
        #expect(PlayAdmission.check(albumID: "al1", albumTitles: ["Night Drive", "Night Drive"], songs: songs,
                                    titleIndex: titles) == .gateAmbiguousTitle)
    }

    @Test func titlesDifferingOnlyByCaseWidthAccentOrSpacesAreAmbiguous() {
        for variant in ["NIGHT DRIVE", "Ｎｉｇｈｔ Ｄｒｉｖｅ", "Night Dri\u{0301}ve", " Night Drive "] {
            let titles = index([("Night Drive", "al1"), (variant, "al2")])
            #expect(PlayAdmission.check(albumID: "al1", albumTitles: ["Night Drive", "Night Drive"], songs: songs,
                                        titleIndex: titles) == .gateAmbiguousTitle, "\(variant)")
        }
    }

    @Test func undefinedOrderIsRefused() {
        let duplicated = [AlbumTrackRef(id: "a", disc: 1, number: 1), AlbumTrackRef(id: "b", disc: 1, number: 1)]
        #expect(PlayAdmission.check(albumID: "al1", albumTitles: ["Night Drive", "Night Drive"], songs: duplicated,
                                    titleIndex: index([("Night Drive", "al1")])) == .gateOrderUndefined)
    }

    @Test func missingFromIndexIsRefused() {
        #expect(PlayAdmission.check(albumID: "al1", albumTitles: ["Night Drive", "Night Drive"], songs: songs,
                                    titleIndex: [:]) == .gateAmbiguousTitle)
    }
}

struct PlaybackIndexTests {
    private func build(_ songs: [RawTrack], others: [OtherAlbumTitle] = []) -> CatalogIndex {
        CatalogIndexBuilder.build(CatalogLoad(songs: songs, skipped: [:], otherAlbumTitles: others))
    }

    @Test func tracksPerAlbumAreOrderedWithDurations() throws {
        let index = build([rawTrack(2, album: 10, title: "Second", number: 2, duration: 200),
                           rawTrack(1, album: 10, title: "First", number: 1, duration: 100.5),
                           rawTrack(3, album: 10, title: "Disc two", disc: 2, number: 1)])
        let songs = try #require(index.songsByAlbum[CatalogIndexBuilder.hex(10)])
        #expect(songs.map(\.id) == [1, 2, 3].map { CatalogIndexBuilder.hex($0) })
        #expect(songs.map(\.title) == ["First", "Second", "Disc two"])
        #expect(songs.map(\.duration) == [100.5, 200, nil])
        #expect(songs.map(\.disc) == [1, 1, 2] && songs.map(\.number) == [1, 2, 1])
    }

    /// CR-017：逐曲歌手（合輯每首不同）；沒有歌手＝空字串；超長截斷
    @Test func tracksCarryPerSongArtist() throws {
        let long = String(repeating: "x", count: 5000)
        let index = build([rawTrack(1, album: 10, albumArtist: "Various", artist: "Singer One", number: 1),
                           rawTrack(2, album: 10, albumArtist: "Various", artist: "Singer Two", number: 2),
                           rawTrack(3, album: 10, albumArtist: "Various", artist: nil, number: 3),
                           rawTrack(4, album: 10, albumArtist: "Various", artist: long, number: 4)])
        let songs = try #require(index.songsByAlbum[CatalogIndexBuilder.hex(10)])
        #expect(songs.map(\.artist).prefix(3) == ["Singer One", "Singer Two", ""])
        #expect(songs[3].artist == TextClamp.clamp(long) && songs[3].artist.count < long.count)
    }

    @Test func trackToAlbumMapping() {
        let index = build([rawTrack(1, album: 10), rawTrack(2, album: 20, albumTitle: "Album B")])
        #expect(index.albumOfTrack[CatalogIndexBuilder.hex(2)] == CatalogIndexBuilder.hex(20))
        #expect(index.albumOfTrack[CatalogIndexBuilder.hex(9)] == nil)
    }

    @Test func admittedAlbumCarriesShortcutPlan() throws {
        let index = build([rawTrack(1, album: 10, albumTitle: "Album A", albumArtist: "", artist: "Solo", number: 1),
                           rawTrack(2, album: 10, albumTitle: "Album A", albumArtist: "", artist: "Solo", number: 2)])
        guard case .admitted(let plan) = try #require(index.admission[CatalogIndexBuilder.hex(10)]) else {
            Issue.record("expected admitted"); return
        }
        #expect(plan.album == "Album A" && plan.albumArtist == "" && plan.artist == "Solo")
        #expect(plan.order == [1, 2].map { CatalogIndexBuilder.hex($0) })
        let input = try #require(plan.input(startingAt: CatalogIndexBuilder.hex(2)))
        #expect(input.position == 2 && input.expectedCount == 2)
        #expect(plan.expected(from: CatalogIndexBuilder.hex(2)) == [CatalogIndexBuilder.hex(2)])
        #expect(plan.input(startingAt: CatalogIndexBuilder.hex(9)) == nil)
    }

    /// 合輯（曲目藝人不一）：artist 留空，避免捷徑以藝人篩掉曲目
    @Test func mixedArtistsLeaveArtistEmpty() throws {
        let index = build([rawTrack(1, album: 10, artist: "One", number: 1), rawTrack(2, album: 10, artist: "Two", number: 2)])
        guard case .admitted(let plan) = try #require(index.admission[CatalogIndexBuilder.hex(10)]) else {
            Issue.record("expected admitted"); return
        }
        #expect(plan.artist == "")
    }

    /// 同名判定涵蓋非歌曲項目（影片等，捷徑的名稱查找也可能撈到）
    @Test func nonSongItemWithSameTitleMakesAlbumAmbiguous() {
        let songs = [rawTrack(1, album: 10, albumTitle: "Shared", number: 1)]
        #expect(build(songs).admission[CatalogIndexBuilder.hex(10)] != .refused(.gateAmbiguousTitle))
        #expect(build(songs, others: [OtherAlbumTitle(title: "shared", albumID: 99)]).admission[CatalogIndexBuilder.hex(10)]
                == .refused(.gateAmbiguousTitle))
    }

    @Test func refusalReasonsComeFromTheGate() {
        let index = build([rawTrack(1, album: 10, albumTitle: "X", number: 1), rawTrack(2, album: 10, albumTitle: "Y", number: 2),
                           rawTrack(3, album: 20, albumTitle: "", number: 1),
                           rawTrack(4, album: 30, albumTitle: "Z", number: 1), rawTrack(5, album: 30, albumTitle: "Z", number: 1)])
        #expect(index.admission[CatalogIndexBuilder.hex(10)] == .refused(.gateInconsistentTitle))
        #expect(index.admission[CatalogIndexBuilder.hex(20)] == .refused(.gateEmptyTitle))
        #expect(index.admission[CatalogIndexBuilder.hex(30)] == .refused(.gateOrderUndefined))
    }

    @Test func versionChangesWithDurationAndOtherTitles() {
        let base = CatalogLoad(songs: [rawTrack(1, album: 10, duration: 100)], skipped: [:], otherAlbumTitles: [])
        let longer = CatalogLoad(songs: [rawTrack(1, album: 10, duration: 101)], skipped: [:], otherAlbumTitles: [])
        let withOther = CatalogLoad(songs: base.songs, skipped: [:], otherAlbumTitles: [OtherAlbumTitle(title: "Clip", albumID: 5)])
        let v = CatalogIndexBuilder.version(of: base)
        #expect(CatalogIndexBuilder.version(of: longer) != v)
        #expect(CatalogIndexBuilder.version(of: withOther) != v)
    }
}
#endif
