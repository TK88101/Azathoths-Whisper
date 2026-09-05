import Foundation
import Testing

@testable import AzathothsWhisper

// 真機冒煙（預設跳過，非門檻）。需 Music.app 正在播放或暫停於一首本機曲目。手動觸發：
//   AZW_MUSIC_TESTS=1 xcodebuild test -project AzathothsWhisper.xcodeproj \
//       -scheme AzathothsWhisper -destination 'platform=macOS,arch=arm64'
// 寫入測試一律「原值回寫」，不改動使用者曲庫。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AZW_MUSIC_TESTS"] == "1"), .serialized)
struct LiveMusicTests {
    private let client = MusicAppleEventsClient()

    @Test func readsCurrentTrackWithPersistentID() async throws {
        let state = try await client.playerState()
        #expect(state.hasCurrentTrack, "請先在 Music 播放或暫停一首本機曲目")

        let track = try #require(try await client.currentTrack())
        #expect(track.persistentID.isEmpty == false)
        #expect(track.title.isEmpty == false)
    }

    @Test func readsAlbumTracksWithDualPredicate() async throws {
        let track = try #require(try await client.currentTrack())
        let album = try await client.albumTracks(artist: track.artist, album: track.album)
        #expect(album.isEmpty == false)
        #expect(album.contains { $0.persistentID == track.persistentID }, "當前曲目應在其專輯清單內")
        #expect(album.sortedForDisplay().count == album.count)
    }

    @Test func writesLyricsByPersistentIDVerbatim() async throws {
        let track = try #require(try await client.currentTrack())
        let original = try await client.currentLyrics()

        let ok = try await client.setLyrics(persistentID: track.persistentID, lyrics: original)
        #expect(ok, "原值回寫應成功（驗證寫入通道，不改動資料）")

        let after = try await client.currentLyrics()
        #expect(after == original)
    }

    @Test func readsArtworkRawBytes() async throws {
        let track = try #require(try await client.currentTrack())
        guard let data = try await client.artworkData(persistentID: track.persistentID) else {
            // 無封面曲目不算失敗，占位路徑由 M7 覆蓋
            return
        }
        #expect(data.count > 1000)
        let magic = Array(data.prefix(2))
        #expect(magic == [0xFF, 0xD8] || magic == [0x89, 0x50], "應為 JPEG 或 PNG")
    }

    @Test func mapsPermissionDeniedCode() {
        let denied = NSError(domain: NSOSStatusErrorDomain, code: -1743)
        #expect(MusicAppleEventsClient.mapError(denied) == .permissionDenied)

        let other = NSError(domain: NSOSStatusErrorDomain, code: -600)
        #expect(MusicAppleEventsClient.mapError(other) == .scriptingFailure("AE error -600"))
    }
}
