import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.10：特效層角落 `~`（估算時才有）；Cover Flow「尚無時間軸」只在存檔是 notFound（全部來源明確說沒有）時出現。
// 歌詞為編造句
@MainActor
@Suite("Timing marks")
struct TimingMarksTests {
    static let lyrics = "Lanterns over the river\nAsh in the wind"
    static let pid = "0123456789ABCDEF"

    private func timeline(_ source: TimingSource) -> LyricsTimeline {
        LyricsTimeline(lines: [TimedLine(start: 1, end: 2, text: "Lanterns over the river", isChorus: false)], source: source, duration: 10)
    }

    @Test(arguments: [(TimingSource.estimated, true), (.lrclib, false), (.embeddedLRC, false), (.netease, false)])
    func theTildeShowsOnlyForEstimatedTiming(source: TimingSource, shown: Bool) {
        #expect(LyricsFXTimingMark.isShown(timeline: timeline(source), status: .present) == shown)
    }

    @Test func theTildeNeedsLyricsToShow() {
        #expect(!LyricsFXTimingMark.isShown(timeline: nil, status: .present))
        #expect(!LyricsFXTimingMark.isShown(timeline: timeline(.estimated), status: .missing))
    }

    private func details(_ lyrics: String?) -> [String: TrackDetails] {
        [Self.pid: TrackDetails(persistentID: Self.pid, artist: "A", title: "T", album: "B", discNumber: 1, trackNumber: 1, lyrics: lyrics, genre: nil, duration: 200)]
    }

    private func model(notFound: Bool) -> CoverFlowViewModel {
        let model = CoverFlowViewModel(artwork: StubArtworkProvider(), clock: GatedPollClock())
        let expected = LyricsFingerprint.of(Self.lyrics)
        model.timingNotFoundReader = { _, hash in notFound && hash == expected }
        return model
    }

    @Test func aStoredNotFoundMarksTheCard() async {
        let model = model(notFound: true)
        model.updateDetails(details(Self.lyrics))
        await waitUntil({ model.timingNotFound.contains(Self.pid) }, iterations: 2000)
        #expect(model.timingNotFound == [Self.pid])
    }

    @Test func noStoredNotFoundLeavesTheCardUnmarked() async {
        let model = model(notFound: false)
        model.updateDetails(details(Self.lyrics))
        await settle()
        #expect(model.timingNotFound.isEmpty)
    }

    @Test func aFreshResolutionUpdatesTheMark() {
        let model = model(notFound: false)
        model.updateDetails(details(Self.lyrics))
        model.timingResolved(TimingResolution(persistentID: Self.pid, lyricsHash: .of(Self.lyrics), outcome: .notFound))
        #expect(model.timingNotFound == [Self.pid])
        model.timingResolved(TimingResolution(persistentID: Self.pid, lyricsHash: .of(Self.lyrics), outcome: .unavailable))
        #expect(model.timingNotFound == [Self.pid])   // 一時失敗不改變已知狀態
        model.timingResolved(TimingResolution(persistentID: Self.pid, lyricsHash: .of(Self.lyrics), outcome: .found(.qq, [.init(index: 0, start: 1)])))
        #expect(model.timingNotFound.isEmpty)
    }

    /// 存檔讀取比查找結果早開始、晚回來：舊答案不得蓋掉新結果
    @Test func aStoreReadThatStartedBeforeAResolutionCannotOverrideIt() async {
        let model = CoverFlowViewModel(artwork: StubArtworkProvider(), clock: GatedPollClock())
        let gate = GatedPollClock()
        model.timingNotFoundReader = { _, _ in
            try? await gate.sleep(for: .seconds(1))
            return false
        }
        model.updateDetails(details(Self.lyrics))
        await gate.waitUntilPending(1)
        model.timingResolved(TimingResolution(persistentID: Self.pid, lyricsHash: .of(Self.lyrics), outcome: .notFound))
        await gate.releaseAll()
        await settle()
        #expect(model.timingNotFound == [Self.pid])
    }

    @Test func aResolutionForOtherLyricsIsIgnored() {
        let model = model(notFound: false)
        model.updateDetails(details(Self.lyrics))
        model.timingResolved(TimingResolution(persistentID: Self.pid, lyricsHash: .of("Something older"), outcome: .notFound))
        #expect(model.timingNotFound.isEmpty)
    }

    @Test func blankLyricsClearTheMark() {
        let model = model(notFound: false)
        model.updateDetails(details(Self.lyrics))
        model.timingResolved(TimingResolution(persistentID: Self.pid, lyricsHash: .of(Self.lyrics), outcome: .notFound))
        model.updateDetails(details("   "))
        #expect(model.timingNotFound.isEmpty)
    }

    @Test func theNewStringsExistInAllThreeLanguages() throws {
        for key in ["timing_estimated", "timing_not_found_yet"] {
            for language in ["en", "zh-Hant", "ja"] {
                let bundle = try #require(Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)))
                #expect(bundle.localizedString(forKey: key, value: "MISSING", table: nil) != "MISSING", "\(key) \(language)")
            }
        }
    }
}
