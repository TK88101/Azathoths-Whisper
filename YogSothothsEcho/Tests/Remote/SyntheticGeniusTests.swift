import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// CR-031 G8-3：合成器在沒有目前曲時按 Genius＝從第 1 張合成專輯第 1 首起播（UI 測試走小膠囊路徑用）
struct SyntheticGeniusTests {
    @Test func geniusWithNoSongStartsTheFirstAlbum() async throws {
        let client = SyntheticPlaybackClient(arguments: [])
        let result = try await client.genius()
        #expect(result.outcome == .applied)
        #expect(result.playback.trackID == SyntheticPlaybackClient.trackID(album: String(format: "%016llx", UInt64(1)), number: 1))
        #expect(result.playback.state == .playing && result.playback.genius == .ready)
    }

    @Test func geniusWhilePlayingMovesToTheNextAlbum() async throws {
        let client = SyntheticPlaybackClient(arguments: [AccessibilityID.nowPlayingArgument])
        let result = try await client.genius()
        #expect(result.outcome == .applied && result.playback.albumID == String(format: "%016llx", UInt64(2)))
    }
}
