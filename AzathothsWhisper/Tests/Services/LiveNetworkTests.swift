import Foundation
import Testing

@testable import AzathothsWhisper

// 線上驗證（預設跳過，非門檻）。手動觸發：
//   AZW_NETWORK_TESTS=1 xcodebuild test -project AzathothsWhisper.xcodeproj \
//       -scheme AzathothsWhisper -destination 'platform=macOS,arch=arm64'
// 跑在 app 宿主進程內，故同時驗證 Info.plist 的 ATS 例外（darklyrics.com 為純 HTTP）。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AZW_NETWORK_TESTS"] == "1"))
struct LiveNetworkTests {
    @Test func darkLyricsDirectPathReachesRealSite() async throws {
        let client = URLSessionHTTPClient()
        let url = try #require(DarkLyricsSource.directURL(artist: "Dark Tranquillity", album: "Damage Done"))
        #expect(url.scheme == "http", "該站 443 拒連，必須維持 http＋ATS 例外")

        let response = try await client.get(url, timeout: HTTPTimeout.darkLyricsDirect)
        #expect(response.statusCode == 200, "若此處失敗＝ATS 例外未生效或站點變更")
        #expect(response.body.contains("class=\"lyrics\""))
    }

    @Test func darkLyricsSourceReturnsLyricsEndToEnd() async throws {
        let source = DarkLyricsSource(client: URLSessionHTTPClient())
        let result = await source.fetchLyrics(
            for: LyricsQuery(artist: "Dark Tranquillity", title: "Monochromatic Stains", album: "Damage Done")
        )
        guard case .found(let text) = result else {
            Issue.record("expected .found, got \(result)")
            return
        }
        #expect(text.count > 100)
    }
}
