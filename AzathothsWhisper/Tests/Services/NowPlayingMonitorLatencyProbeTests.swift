#if DEBUG
import Foundation
import Testing

@testable import AzathothsWhisper

// I-68 L2：monitor 每次讀取都在新的請求 ID 底下呼叫 `nowPlaying`。
// 只證明 monitor 端設好 TaskLocal；真 client 的 `run`↔`np` 一對一由真機報表的 fail-closed 規則證明（替身不走 `run`）
@Suite("NowPlayingMonitor latency probe")
struct NowPlayingMonitorLatencyProbeTests {
    @Test func eachReadRunsUnderAFreshRequestID() async {
        let music = MockMusicClient(script: [.track(TrackInfo.fixture(), lyrics: "l"), .track(TrackInfo.fixture(), lyrics: "l")])
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())

        await monitor.tick()
        await monitor.playerDidChange()

        let ids = await music.nowPlayingRequestIDs
        #expect(ids.count == 2)
        #expect(ids.allSatisfy { $0 != nil })
        if let first = ids.first ?? nil, let second = ids.last ?? nil { #expect(second > first) }
    }

    @Test func nowPlayingOutsideAMonitorReadHasNoRequestID() async throws {
        let music = MockMusicClient(script: [.track(TrackInfo.fixture(), lyrics: "l")])
        _ = try await music.nowPlaying()
        #expect(await music.nowPlayingRequestIDs == [nil])
    }
}
#endif
