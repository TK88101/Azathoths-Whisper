#if os(macOS)
import Foundation
import Testing
@testable import MusicRemoteBridge

// S4 T12（sprint-4-detail.md §5 T12、D8）：離線同定檢查。對每張放行專輯模擬捷徑的「以專輯名查找」：
// 撈到的候選（歌曲＋非歌曲，正規化同名）必須恰好是這張專輯自己的曲目，首數與順序＝捷徑計畫。名稱一律自編

private func song(_ id: UInt64, album: UInt64?, _ title: String?, disc: Int = 1, number: Int, artist: String = "Made-up Artist") -> RawTrack {
    RawTrack(trackID: id, albumID: album, albumTitle: title, sortAlbumTitle: nil, albumArtist: nil, sortAlbumArtist: nil,
             artist: artist, title: "Made-up Song \(id)", discNumber: disc, trackNumber: number, modifiedAt: nil, hasArtwork: false)
}

/// 刁鑽的夾具：多片、合輯、大小寫／全半形／平片假名同名、非歌曲同名、曲序缺漏、無專輯
private let fixture = CatalogLoad(songs: [
    // 放行：兩片、曲序交錯輸入
    song(0x11, album: 1, "Imaginary Shores", disc: 2, number: 1), song(0x12, album: 1, "Imaginary Shores", disc: 1, number: 2),
    song(0x13, album: 1, "Imaginary Shores", disc: 1, number: 1),
    // 放行：合輯（曲目藝人不一）
    song(0x21, album: 2, "Assorted Echoes", number: 1, artist: "Someone"), song(0x22, album: 2, "Assorted Echoes", number: 2, artist: "Another"),
    // 不放行：與 4 同名（大小寫與全形不同、正規化後相同）
    song(0x31, album: 3, "Twin Name", number: 1), song(0x41, album: 4, "ＴＷＩＮ name", number: 1),
    // 不放行：片假名／平假名同名
    song(0x51, album: 5, "かげぼうし", number: 1), song(0x61, album: 6, "カゲボウシ", number: 1),
    // 不放行：與非歌曲項目同名
    song(0x71, album: 7, "Shared With Video", number: 1),
    // 不放行：曲序缺漏
    song(0x81, album: 8, "No Order", number: 0),
    // 無專輯（略過）
    song(0x91, album: nil, nil, number: 1),
], skipped: [:], otherAlbumTitles: [OtherAlbumTitle(title: "shared with video", albumID: 99)])

struct AdmittedAlbumIdentityTests {
    @Test func everyAdmittedAlbumLooksUpExactlyItself() {
        let index = CatalogIndexBuilder.build(fixture)
        let admitted = index.admission.filter { if case .admitted = $0.value { true } else { false } }
        #expect(Set(admitted.keys) == ["0000000000000001", "0000000000000002"])
        #expect(AdmittedAlbumIdentity.violations(fixture, index: index).isEmpty)
    }

    /// 檢查本身會抓到：索引放行之後，曲庫多出一首同名但屬於別張的曲目（例如換版）→ 該專輯列為違反
    @Test func detectsAnotherAlbumSharingTheName() {
        let index = CatalogIndexBuilder.build(fixture)
        let changed = CatalogLoad(songs: fixture.songs + [song(0xA1, album: 10, "imaginary shores", number: 1)], skipped: [:],
                                  otherAlbumTitles: fixture.otherAlbumTitles)
        #expect(AdmittedAlbumIdentity.violations(changed, index: index) == ["0000000000000001"])
    }

    /// 首數不符也算違反（捷徑以首數防呆，查到的首數≠期待就停）
    @Test func detectsMissingTrack() {
        let index = CatalogIndexBuilder.build(fixture)
        let fewer = CatalogLoad(songs: fixture.songs.filter { $0.trackID != 0x22 }, skipped: [:], otherAlbumTitles: fixture.otherAlbumTitles)
        #expect(AdmittedAlbumIdentity.violations(fewer, index: index) == ["0000000000000002"])
    }

    /// #4-1 真曲庫發現（6／987 張）：同一張專輯裡的非歌曲項目（MV 等）同名——捷徑只以專輯名篩選、不分媒體種類，
    /// 首數會對不上，閘門必須拒絕（只播單曲）；同定檢查也應因此通過
    @Test func nonSongInsideTheSameAlbumIsRefused() {
        let withVideo = CatalogLoad(songs: fixture.songs, skipped: [:],
                                    otherAlbumTitles: fixture.otherAlbumTitles + [OtherAlbumTitle(title: "Assorted Echoes", albumID: 2)])
        let index = CatalogIndexBuilder.build(withVideo)
        #expect(index.admission["0000000000000002"] == .refused(.gateAmbiguousTitle))
        #expect(AdmittedAlbumIdentity.violations(withVideo, index: index).isEmpty)
    }

    @Test func detectsNonSongWithSameName() {
        let index = CatalogIndexBuilder.build(fixture)
        let withVideo = CatalogLoad(songs: fixture.songs, skipped: [:],
                                    otherAlbumTitles: fixture.otherAlbumTitles + [OtherAlbumTitle(title: "Assorted Echoes", albumID: 98)])
        #expect(AdmittedAlbumIdentity.violations(withVideo, index: index) == ["0000000000000002"])
    }
}
#endif
