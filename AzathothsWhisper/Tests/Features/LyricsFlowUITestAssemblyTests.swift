import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 Q3.5：UI 測試組裝（場景 env、假 Music、恆 404 的 HTTP——batchImport 例外見替身專輯頁、測試專屬設定 suite、假的 Queue.dat／History.dat）。
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

    // MARK: 2026-09-25 batchImport 場景（計劃 T5a／T5c）

    /// 播放中那首有詞 → Cover Flow；1、4 缺詞、0、3 有詞；Batch 載入得到完整 5 首（順序＝軌序）
    @Test func batchImportScenarioShowsCoverFlowAndLoadsTheWholeAlbum() async throws {
        defer { cleanUp() }
        let model = try make(.batchImport)
        await pollOnce(model)
        await waitUntil({ model.lyricsFlow.surface == .coverFlow }, iterations: 20_000)
        await model.lyricsFlow.settleForTesting()

        let statuses = model.coverFlow.cards.map { model.coverFlow.status(for: $0) }
        #expect(statuses == [.present, .missing, .present, .present, .missing])

        await model.batch.loadAlbum()
        #expect(model.batch.tracks.map(\.persistentID) == (0..<Scenario.trackCount).map(Scenario.persistentID(at:)))
        #expect(model.batch.tracks.map(\.lyrics) == (0..<Scenario.trackCount).map(Scenario.batchImport.initialLyrics(at:)))
    }

    /// 經真實 LyricsService → DarkLyricsSource → 替身專輯頁：Fetch Missing 補上 1、4；Import All 後兩卡 ✓（E2E 的單元版）
    @Test func batchImportScenarioFetchesAndImportsTheMissingTracks() async throws {
        defer { cleanUp() }
        let model = try make(.batchImport)
        await pollOnce(model)
        await waitUntil({ model.lyricsFlow.surface == .coverFlow }, iterations: 20_000)
        await model.lyricsFlow.settleForTesting()
        await model.batch.loadAlbum()

        await model.batch.fetchMissing()
        #expect(model.batch.statusText == StatusText.fetchComplete)
        #expect(model.batch.missingTracks.isEmpty)
        for index in Scenario.batchFoundIndices {
            let track = try #require(model.batch.tracks.first { $0.persistentID == Scenario.persistentID(at: index) })
            #expect(track.lyrics == Scenario.batchLyrics(at: index))
        }

        model.batch.requestImportAll()
        await model.batch.confirmImportAll()
        await model.lyricsFlow.settleForTesting()
        let statuses = model.coverFlow.cards.map { model.coverFlow.status(for: $0) }
        #expect(statuses == Array(repeating: .present, count: Scenario.trackCount))
    }

    /// 替身專輯頁必須被真的解析器讀懂：找得到的歌給出預期歌詞，其餘是「頁上沒有這首」
    @Test func batchImportLyricsPageParsesWithTheRealParser() {
        for index in 0..<Scenario.trackCount {
            let outcome = DarkLyricsParser.parse(html: LyricsFlowUITestLyricsPage.html, targetTitle: Scenario.title(at: index))
            if Scenario.batchFoundIndices.contains(index) {
                #expect(outcome == .lyrics(Scenario.batchLyrics(at: index)), "index \(index)")
            } else {
                #expect(outcome == .titleNotFound, "index \(index)")
            }
        }
    }

    /// 替身只回應 DarkLyrics 直連頁；其他場景沿用恆 404（既有場景的自動抓詞結果不變）
    @Test func batchImportStubAnswersOnlyTheDirectAlbumPage() async throws {
        let client = UITestStubHTTPClient(pages: LyricsFlowUITestLyricsPage.pages)
        let direct = try #require(DarkLyricsSource.directURL(artist: Scenario.artist, album: Scenario.album))
        #expect(try await client.get(direct, headers: [:], timeout: 1).statusCode == 200)
        let other = try #require(URL(string: "http://www.darklyrics.com/lyrics/other/album.html"))
        #expect(try await client.get(other, headers: [:], timeout: 1).statusCode == 404)
        #expect(try await client.post(direct, form: [:], headers: [:], timeout: 1).statusCode == 404)
    }

    /// 其他場景的 Batch 列表維持空（不擾動既有 BatchUITests／ShellUITests）
    @Test func otherScenariosKeepAnEmptyAlbum() async throws {
        for scenario in [Scenario.present, .missing, .marked] {
            let music = LyricsFlowUITestMusic(scenario: scenario)
            #expect(try await music.albumTracks(artist: Scenario.artist, album: Scenario.album).isEmpty)
        }
    }
}
