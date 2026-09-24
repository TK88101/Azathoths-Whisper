import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 Q3.5：UI 測試組裝（場景 env、假 Music、恆 404 的 HTTP、測試專屬設定 suite、假的 Queue.dat／History.dat）。
// 組裝是 E2E 的地基：場景錯了，UITests 的紅綠就沒有意義——故每個場景都在單元層先釘住。
@MainActor
@Suite("LyricsFlowUITestAssembly", .serialized)
struct LyricsFlowUITestAssemblyTests {
    private typealias Scenario = LyricsFlowUITestScenario

    private func make(_ scenario: Scenario, reset: Bool = true, seed: String? = nil) throws -> AppModel {
        var environment = Scenario.environment(scenario, resetDefaults: reset)
        if let seed { environment[Scenario.seedMarksVariable] = seed }
        return try #require(AppModel.makeLyricsFlowUITestModelIfRequested(environment: environment))
    }

    /// 經 Now Editing 卡片的強制重讀驅動一次輪詢（不啟動計時輪詢、不等開場畫面）
    private func pollOnce(_ model: AppModel) async {
        model.startEventLoop()
        model.editor.requestHydrate()
    }

    private func cleanUp() {
        UserDefaults().removePersistentDomain(forName: Scenario.defaultsSuiteName)
    }

    @Test func assemblyIsOffWithoutAKnownScenario() {
        #expect(AppModel.makeLyricsFlowUITestModelIfRequested(environment: [:]) == nil)
        #expect(AppModel.makeLyricsFlowUITestModelIfRequested(environment: [Scenario.variable: "bogus"]) == nil)
    }

    /// AC1 的場景：有詞 → Cover Flow；左＝履歴 2 張、中＝播放中、右＝待播 2 張
    @Test func presentScenarioShowsCoverFlowOverTheFixtureQueue() async throws {
        defer { cleanUp() }
        let model = try make(.present)
        await pollOnce(model)
        await waitUntil({ model.lyricsFlow.surface == .coverFlow }, iterations: 20_000)
        await model.lyricsFlow.settleForTesting()

        #expect(model.lyricsFlow.surface == .coverFlow)
        #expect(model.coverFlow.cards.map(\.side) == [.played, .played, .current, .upcoming, .upcoming])
        #expect(model.coverFlow.cards.map(\.persistentID) == (0..<Scenario.trackCount).map(Scenario.persistentID(at:)))
        #expect(model.lyricsFlow.upcoming == .available)
        #expect(model.token.isEmpty, "測試組裝不得讀到任何真實 token")
    }

    /// AC2 的場景：缺詞 → Editor，自動抓詞打到恆 404 的假 HTTP
    @Test func missingScenarioShowsTheEditorAndFetchesFromTheStub() async throws {
        defer { cleanUp() }
        let model = try make(.missing)
        await pollOnce(model)
        await waitUntil({ model.editor.statusText == StatusText.lyricsNotFound }, iterations: 20_000)

        #expect(model.lyricsFlow.surface == .editor)
        #expect(model.editor.statusText == StatusText.lyricsNotFound)
    }

    /// AC5 的場景：缺詞但已標記 → Cover Flow、不自動抓詞
    @Test func markedScenarioSeedsTheMarkAndSkipsAutoFetch() async throws {
        defer { cleanUp() }
        let model = try make(.marked)
        await pollOnce(model)
        await waitUntil({ model.lyricsFlow.status == .markedNone }, iterations: 20_000)

        #expect(model.lyricsFlow.surface == .coverFlow)
        #expect(model.editor.autoFetchTask == nil)
    }

    /// 外殼測試的場景：沒在播 → Editor 顯示 NO ARTIST／NO TRACK
    @Test func notPlayingScenarioKeepsTheEditorEmpty() async throws {
        defer { cleanUp() }
        let model = try make(.notPlaying)
        await pollOnce(model)
        await settle()

        #expect(model.lyricsFlow.surface == .editor)
        #expect(model.editor.titleLine == StatusText.noTrack)
    }

    /// D4：第一次啟動帶 reset、重啟不帶——標記跨重啟保留；reset 清空；預植標記可由 env 帶入
    @Test func resetAndSeedControlTheTestSuiteOnly() async throws {
        defer { cleanUp() }
        let first = try make(.missing, reset: true, seed: "AAAA000000000001,AAAA000000000002")
        #expect(first.lyricsFlow.marks == ["AAAA000000000001", "AAAA000000000002"])

        let relaunched = try make(.missing, reset: false)
        #expect(relaunched.lyricsFlow.marks == ["AAAA000000000001", "AAAA000000000002"])

        let reset = try make(.missing, reset: true)
        #expect(reset.lyricsFlow.marks.isEmpty)
        #expect(UserDefaults.standard.object(forKey: ConfigStore.NoLyricsMarksKey.markedTrackIDs) == nil,
                "從不碰使用者的 .standard")
    }

    @Test func fakeMusicWritesOnlyToMemory() async throws {
        let music = LyricsFlowUITestMusic(scenario: .missing)
        let playing = Scenario.persistentID(at: Scenario.playingIndex)
        #expect(try await music.nowPlaying()?.lyrics == "")
        #expect(try await music.setLyrics(persistentID: playing, lyrics: "new words"))
        #expect(try await music.nowPlaying()?.lyrics == "new words", "寫入後的補讀讀得到")
        #expect(try await music.setLyrics(persistentID: "FFFF000000000000", lyrics: "x") == false)
        #expect(try await music.trackDetails(persistentIDs: [Scenario.persistentID(at: 1)]).first?.lyrics == "")
    }

    @Test func stubHTTPClientAlwaysAnswersNotFound() async throws {
        let client = UITestStubHTTPClient()
        let url = try #require(URL(string: "https://genius.com/x"))
        #expect(try await client.get(url, headers: [:], timeout: 1).statusCode == 404)
        #expect(try await client.post(url, form: [:], headers: [:], timeout: 1).statusCode == 404)
    }

    /// 假檔必須能被真的解析器讀懂（同一份形狀，事實 20、25）
    @Test func fixtureFilesParseWithTheRealReaders() throws {
        let directory = try LyricsFlowUITestQueueFiles.write()
        let queue = try #require(QueueSnapshot.parse(Data(contentsOf: directory.appendingPathComponent(QueueFileSource.queueFileName))))
        let history = try #require(HistorySnapshot.parse(
            Data(contentsOf: directory.appendingPathComponent(QueueFileSource.historyFileName)), keepLast: 10
        ))

        #expect(queue.sequenceKind == .ordered)
        #expect(queue.entries.map(\.persistentID) == (0..<Scenario.trackCount).map(Scenario.persistentID(at:)))
        #expect(queue.entries.map(\.itemID) == (0..<Scenario.trackCount).map { Scenario.itemID(at: $0) })
        #expect(history.recent.map(\.persistentID) == (0..<Scenario.playingIndex).map(Scenario.persistentID(at:)))
    }
}
