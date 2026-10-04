import Foundation
import Testing

@testable import AzathothsWhisper

// 實機量測（A1 計劃 T12，使用者在場）。預設跳過；**只讀不寫**，不送任何播控。需 Music 正在播放一首本機曲目、量測期間不要動它：
//   AZW_MUSIC_TESTS=1 xcodebuild test … -only-testing:AzathothsWhisperTests/LiveLyricsFXMeasurementTests
// 結果以 `[A1-MEASURE]` 開頭印到 log，回填計劃 §8
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AZW_MUSIC_TESTS"] == "1"), .serialized)
struct LiveLyricsFXMeasurementTests {
    private let client = MusicAppleEventsClient()
    static let samples = 30
    static let spacing: Duration = .milliseconds(500)

    /// genre／duration 讀得到（mock 模擬不了 per-selector lastError，Codex R1）
    @Test func nowPlayingReadsGenreAndDuration() async throws {
        let read = try #require(try await client.nowPlaying())
        #expect(read.metadata.genre != nil)
        let duration = try #require(read.metadata.duration)
        #expect(duration > 0)
        print("[A1-MEASURE] metadata genreRead=\(read.metadata.genre != nil) durationSeconds=\(Int(duration))")
    }

    /// roundTrip 分布、相鄰讀數與錨點外推的殘差分布（→ tolerance 依據）
    @Test func playbackPositionLatencyAndJitter() async throws {
        var readings: [PlaybackPosition] = []
        for _ in 0..<Self.samples {
            if let reading = try await client.playbackPosition() { readings.append(reading) }
            try await Task.sleep(for: Self.spacing)
        }
        #expect(readings.count >= Self.samples - 2, "請先在 Music 播放一首曲目")
        #expect(Set(readings.map(\.persistentID)).count == 1, "量測期間不要換歌")
        let playing = readings.filter { $0.state == .playing }
        #expect(playing.count == readings.count, "量測期間保持播放")

        let roundTrips = readings.map { Self.ms($0.roundTrip) }.sorted()
        let first = try #require(playing.first)
        let origin = first.readAt - .seconds(first.seconds)
        let residuals = playing.dropFirst().map { abs(Self.ms($0.readAt - origin) - $0.seconds * 1000) }.sorted()
        print("[A1-MEASURE] roundTripMs p50=\(Self.pct(roundTrips, 0.5)) p90=\(Self.pct(roundTrips, 0.9)) max=\(roundTrips.last ?? 0) n=\(roundTrips.count)")
        print("[A1-MEASURE] residualMs p50=\(Self.pct(residuals, 0.5)) p90=\(Self.pct(residuals, 0.9)) max=\(residuals.last ?? 0) n=\(residuals.count)")
    }

    /// 卡片詳情改成 9 欄後一批的耗時（→ detailsBudget 依據，S6 原為 7 欄 p50 51ms）
    @Test func trackDetailsNineColumnLatency() async throws {
        let track = try #require(try await client.currentTrack())
        let ids = try await client.albumTracks(artist: track.artist, album: track.album).map(\.persistentID).prefix(21)
        var elapsed: [Double] = []
        for _ in 0..<10 {
            let start = ContinuousClock.now
            let details = try await client.trackDetails(persistentIDs: Array(ids))
            elapsed.append(Self.ms(ContinuousClock.now - start))
            #expect(!details.isEmpty)
        }
        elapsed.sort()
        print("[A1-MEASURE] trackDetails9ColMs ids=\(ids.count) p50=\(Self.pct(elapsed, 0.5)) p90=\(Self.pct(elapsed, 0.9)) max=\(elapsed.last ?? 0)")
    }

    private static func ms(_ duration: Duration) -> Double {
        duration.inSeconds * 1000
    }

    private static func pct(_ sorted: [Double], _ p: Double) -> Int {
        guard !sorted.isEmpty else { return -1 }
        return Int(sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))].rounded())
    }
}
