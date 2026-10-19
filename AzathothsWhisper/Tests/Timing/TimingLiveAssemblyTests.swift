import Foundation
import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.5／§3.9：正式組裝的退路順序、停用開關的讀法、診斷字串（不含曲名、歌詞、URL）
@Suite("Timing live assembly")
struct TimingLiveAssemblyTests {
    @Test func theChainOrderIsFixed() {
        let providers = TimingResolver.liveProviders(client: MockHTTPClient())
        #expect(providers.map(\.source) == [.lrclib, .youtubeMusic, .deezer, .qq, .netease])
    }

    @Test func switchesAreReadFromDefaults() throws {
        let name = "TimingSwitchesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(TimingSwitches.read(from: defaults) == .allEnabled)
        defaults.set(true, forKey: TimingSwitches.lookupDisabledKey)
        defaults.set(["qq", "netease", "nonsense"], forKey: TimingSwitches.disabledSourcesKey)
        #expect(TimingSwitches.read(from: defaults) == TimingSwitches(lookupDisabled: true, disabledSources: [.qq, .netease]))
    }

    /// 正式組裝讀得到停用開關：全域停用時不連網、不讀 Music，直接回「已停用」
    @Test func theLiveAssemblyHonoursTheGlobalSwitch() async throws {
        let name = "TimingLiveTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: TimingSwitches.lookupDisabledKey)
        let music = MockMusicClient(script: [.notPlaying])
        let resolver = TimingResolver.live(music: music, defaults: defaults)
        let result = await resolver.resolve(TimingRequest(persistentID: "0123456789ABCDEF", lyrics: "Lanterns over the river", query: nil), priority: .visible)
        #expect(result.outcome == .skipped(.disabled))
        #expect(await music.trackDetailsRequests.isEmpty)
    }

    @Test func diagnosticLinesCarryOnlySourceOutcomeScoreAndTime() {
        let alignment = LRCAligner.Alignment(anchors: [1, nil, 3], musicRate: 0.666, lrcCoverage: 0.5)
        #expect(OSLogTimingDiagnostics.line(for: .answer(.youtubeMusic, alignment: alignment, elapsed: 0.4321))
            == "source=youtubeMusic result=alignFail music=0.67 lrc=0.50 anchors=2 ms=432")
        let accepted = LRCAligner.Alignment(anchors: [1, 2, 3], musicRate: 1, lrcCoverage: 0.75)
        #expect(OSLogTimingDiagnostics.line(for: .answer(.netease, alignment: accepted, elapsed: 1))
            == "source=netease result=answer music=1.00 lrc=0.75 anchors=3 ms=1000")
        #expect(OSLogTimingDiagnostics.line(for: .noTiming(.qq, .mismatch, elapsed: 0.2)) == "source=qq result=mismatch ms=200")
        #expect(OSLogTimingDiagnostics.line(for: .failure(.lrclib, .server(status: 503), elapsed: 0.05)) == "source=lrclib result=failure kind=server503 ms=50")
        #expect(OSLogTimingDiagnostics.line(for: .failure(.deezer, .rateLimited(retryAfter: 30), elapsed: 0)) == "source=deezer result=failure kind=rateLimited ms=0")
        #expect(OSLogTimingDiagnostics.line(for: .skipped(.missingMetadata)) == "result=skipped reason=missingMetadata")
    }

    static let accepted = LRCAligner.Alignment(anchors: [1, 2, 3], musicRate: 1, lrcCoverage: 1)

    @Test func aSummaryIsWrittenEveryTwentyQueries() {
        var tally = TimingTally()
        var summaries: [String] = []
        for index in 0..<40 {
            let event: TimingDiagnosticEvent = index.isMultiple(of: 4)
                ? .answer(.lrclib, alignment: Self.accepted, elapsed: 0) : .noTiming(.qq, .notFound, elapsed: 0)
            if let summary = tally.add(event) { summaries.append(summary) }
        }
        #expect(summaries.count == 2)
        #expect(summaries.first == "summary queries=20 answers lrclib=5 failures none")
    }
}
