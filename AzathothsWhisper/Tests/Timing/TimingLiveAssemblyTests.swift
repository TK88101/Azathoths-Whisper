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

    /// 候選排序計劃 §5 整合：真的 LRCLIB 解析＋resolver 排序挑選。兩筆都帶時間軸，第 2 筆對得較好 → 存第 2 筆的錨點（歌詞為編造句）
    @Test func lrclibWithTwoSyncedCandidatesStoresTheBetterAlignedOne() async throws {
        let lyrics = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn"
        let weaker = #"[00:11.00] Lanterns over the river\n[00:15.00] Ash in the wind\n[00:21.00] Count the silent bells\n[00:30.00] Something else entirely"#
        let better = #"[00:10.00] Lanterns over the river\n[00:14.00] Ash in the wind\n[00:20.00] Count the silent bells\n[00:24.00] Paper boats at dawn"#
        func record(_ id: Int, _ synced: String) -> String {
            #"{"id":\#(id),"trackName":"Lantern Song","artistName":"Some Band","duration":200,"syncedLyrics":"\#(synced)"}"#
        }
        let client = ScriptedHTTPClient([.respond(404, "{}"), .respond(200, "[\(record(1, weaker)),\(record(2, better))]")])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-ranking-\(UUID().uuidString)")
        let resolver = TimingResolver(
            providers: [LRCLIBProvider(gate: .testing(client))], store: TimingStore(directory: directory),
            metadata: { _ in TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200) }, switches: .allEnabled,
            deadlineSleeper: NeverSleeper(), clock: FakeTimingClock()
        )
        let result = await resolver.resolve(TimingRequest(persistentID: "0123456789ABCDEF", lyrics: lyrics, query: nil), priority: .background)
        #expect(result.outcome == .found(.lrclib, [.init(index: 0, start: 10), .init(index: 1, start: 14), .init(index: 2, start: 20), .init(index: 3, start: 24)]))
        #expect(client.requests.map(\.url.path) == ["/api/get", "/api/search"])
    }

    @Test func diagnosticLinesCarryOnlySourceOutcomeScoreAndTime() {
        let alignment = LRCAligner.Alignment(anchors: [1, nil, 3], musicRate: 0.666, lrcCoverage: 0.5)
        #expect(OSLogTimingDiagnostics.line(for: .answer(.youtubeMusic, rank: 0, alignment: alignment, elapsed: 0.4321))
            == "source=youtubeMusic result=alignFail rank=0 music=0.67 lrc=0.50 anchors=2 ms=432")
        let accepted = LRCAligner.Alignment(anchors: [1, 2, 3], musicRate: 1, lrcCoverage: 0.75)
        #expect(OSLogTimingDiagnostics.line(for: .answer(.netease, rank: 2, alignment: accepted, elapsed: 1))
            == "source=netease result=answer rank=2 music=1.00 lrc=0.75 anchors=3 ms=1000")
        #expect(OSLogTimingDiagnostics.line(for: .picked(.netease, rank: 1, tried: 3)) == "source=netease result=picked rank=1 tried=3")
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
                ? .answer(.lrclib, rank: 0, alignment: Self.accepted, elapsed: 0) : .noTiming(.qq, .notFound, elapsed: 0)
            if let summary = tally.add(event) { summaries.append(summary) }
            if index == 0 || index == 4 { _ = tally.add(.picked(.lrclib, rank: index == 0 ? 0 : 1, tried: 2)) }
        }
        #expect(summaries.count == 2)
        // picked 不算一次來源請求；累計勝出名次
        #expect(summaries.first == "summary queries=20 answers lrclib=5 failures none picked rank0=1 rank1=1")
    }
}
