import Foundation
import Testing

@testable import AzathothsWhisper

// 依賴容器的接線：token 保存後即時生效（D-08／F-07）、語言落位（E-08）、tab 切換影響自動抓詞（B-05）
@MainActor
@Suite("AppModel")
struct AppModelTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    private struct Fixture {
        let model: AppModel
        let store: ConfigStore
        let defaults: UserDefaults
        let suiteName: String
        /// 暴露給需要驅動輪詢／斷言 AE 調用次數的用例
        let music: MockMusicClient
        let monitor: NowPlayingMonitor
        /// 升回計時（寫入成功後等彩帶撒完）
        let clock: GatedPollClock

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture(
        token: String = "fake-old",
        music: MockMusicClient = MockMusicClient()
    ) -> Fixture {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults)
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let clock = GatedPollClock()
        let model = makeModel(store: store, music: music, monitor: monitor, clock: clock, token: token)
        return Fixture(
            model: model, store: store, defaults: defaults,
            suiteName: suiteName, music: music, monitor: monitor, clock: clock
        )
    }

    private func makeModel(
        store: ConfigStore,
        music: MockMusicClient,
        monitor: NowPlayingMonitor,
        clock: GatedPollClock = GatedPollClock(),
        token: String = ""
    ) -> AppModel {
        AppModel(
            configStore: store,
            httpClient: MockHTTPClient(),
            music: music,
            monitor: monitor,
            validator: AlwaysValidValidator(),
            initialToken: token,
            initialLanguage: .system,
            splashDuration: .milliseconds(1),
            lyricsFlowClock: clock,
            isMusicRunning: { true }
        )
    }

    // D-08／F-07：保存 token → 進 Keychain 抽象層，且抓詞管線立刻改用新 token（免重啟）
    @Test func savingTokenPersistsAndRebuildsGeniusSource() async {
        let fixture = makeFixture()
        defer { fixture.tearDown() }

        fixture.model.openSettings(.token)
        fixture.model.settings.tokenInput = "fake-new"
        await fixture.model.settings.saveToken()

        #expect(fixture.store.token == "fake-new")
        #expect(fixture.model.token == "fake-new")
        let genius = fixture.model.editor.lyricsService.genius as? GeniusSource
        #expect(genius?.token == "fake-new", "抓詞管線應以新 token 重建")
    }

    // E-08：語言寫入 per-app AppleLanguages
    @Test func savingLanguageWritesAppleLanguagesOverride() {
        let fixture = makeFixture()
        defer { fixture.tearDown() }

        fixture.model.openSettings(.language)
        fixture.model.settings.language = .ja
        fixture.model.settings.saveLanguage()

        #expect(fixture.store.language == .ja)
        #expect(fixture.defaults.array(forKey: "AppleLanguages") as? [String] == ["ja"])
    }

    // B-05：只有 Editor tab 在前景才自動抓詞
    @Test func switchingTabTogglesEditorAutoFetchFlag() {
        let fixture = makeFixture()
        defer { fixture.tearDown() }

        fixture.model.select(.batch)
        #expect(fixture.model.editor.isEditorTabActive == false)

        fixture.model.select(.batch)
        #expect(fixture.model.editor.isEditorTabActive == false)

        fixture.model.select(.editor)
        #expect(fixture.model.editor.isEditorTabActive)
    }

    // D-01／D-02：菜單開 modal 時預填現值，且兩組互斥
    @Test func openingSettingsPrefillsCurrentValues() {
        let fixture = makeFixture(token: "fake-existing")
        defer { fixture.tearDown() }

        fixture.model.openSettings(.token)
        #expect(fixture.model.activeModal == .settings)
        #expect(fixture.model.settings.group == .token)
        #expect(fixture.model.settings.tokenInput == "fake-existing")

        fixture.model.openSettings(.language)
        #expect(fixture.model.settings.group == .language)

        fixture.model.openAbout()
        #expect(fixture.model.activeModal == .about)

        fixture.model.closeModal()
        #expect(fixture.model.activeModal == nil)
    }

    // MARK: - 單元測試 host 旗標（A1 根因防護）

    /// 旗標名在 UITests target 有一份複寫（AppUITestCase.swift 的 AppModelTestFlags），
    /// 因為 UITests 不能 @testable import 產品模組。兩邊漂移會讓 UITests 的被測 app
    /// 意外跳過 Keychain，A-05 的 token 預填驗收會靜默失效——故在此釘住。
    @Test func unitTestHostFlagNameMatchesUITestsCopy() {
        #expect(AppModel.unitTestHostFlag == "AZW_UNIT_TEST_HOST")
    }

    /// 本測試自己就跑在單元測試 host 裡：scheme 注入了旗標，故必為真。
    /// 若這條紅了，代表 project.yml 的 test action 注入失效 → 下次重簽後
    /// 整個單元 target 會再次掛死在 Keychain 授權框上（2026-08-23 A1）。
    @Test func schemeInjectsUnitTestHostFlag() {
        #expect(AppModel.isUnitTestHost, "scheme test action 未注入 AZW_UNIT_TEST_HOST=1")
    }

    // MARK: - A3b：monitor 的 busy 只有單一來源（可達性驗證）

    /// 修復前：`AppModel` 讓 Editor 與 Batch 各自以裸布林覆寫 monitor 的**單一** `isBusy`，
    /// 一方送 false 會清掉另一方仍需維持的 busy。現由 `NowPlayingMonitor.busySources`
    /// 自己記錄「誰還忙著」（`setBusy(_:source:)`），本用例釘住該行為。
    ///
    /// 可達性：Editor 的 busy 區間橫跨 `await resolveAndFetch()`，而原版 `toggleBusy`
    /// 禁用的 5 個元素**不含 tab 導航**（py:407，上游 §8.2 已核實），故使用者可在抓詞中
    /// 切到 Batch → 觸發載入 → 載入完成送 false → Editor 仍在抓詞但輪詢已恢復，違反 B-02。
    /// 整合測試入口（計劃 Q0）：只接事件、不啟動輪詢，由測試逐次驅動 `monitor.tick()`
    @Test func eventLoopAppliesManuallyTickedTrackWithoutStartingPolling() async {
        let track = TrackInfo.fixture(title: "Punish My Heaven")
        let music = MockMusicClient(script: [.track(track, lyrics: "lyric")])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }

        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil { fixture.model.editor.lyricsText == "lyric" }

        #expect(fixture.model.editor.lyricsText == "lyric")
        #expect(await music.currentTrackCalls == 1, "未啟動輪詢：只有手動那一次 tick")
    }

    /// AC1（整合）：輪詢到有詞的歌 → Cover Flow 升起、可見、置中於它
    @Test func tickedTrackWithLyricsRaisesCoverFlow() async {
        let music = MockMusicClient(script: [.track(.fixture(id: "PID1"), lyrics: "words")])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        fixture.model.startEventLoop()

        await fixture.monitor.tick()
        await waitUntil { fixture.model.lyricsFlow.surface == .coverFlow }

        #expect(fixture.model.lyricsFlow.surface == .coverFlow)
        #expect(fixture.model.coverFlow.isVisible)
        #expect(fixture.model.coverFlow.centerID != nil)
    }

    /// AC2（整合）：缺詞 → Editor；Cover Flow 不可見
    @Test func tickedMissingTrackShowsTheEditor() async {
        let music = MockMusicClient(script: [.track(.fixture(id: "PID1"), lyrics: "")])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        fixture.model.startEventLoop()

        await fixture.monitor.tick()
        await waitUntil { fixture.model.lyricsFlow.status == .missing }

        #expect(fixture.model.lyricsFlow.surface == .editor)
        #expect(!fixture.model.coverFlow.isVisible)
    }

    /// Cover Flow 可見＝Editor 分頁在前 ∧ 畫面＝Cover Flow
    @Test func coverFlowIsHiddenOnTheBatchTab() async {
        let music = MockMusicClient(script: [.track(.fixture(id: "PID1"), lyrics: "words")])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil { fixture.model.coverFlow.isVisible }

        fixture.model.select(.batch)
        #expect(!fixture.model.coverFlow.isVisible)
        fixture.model.select(.editor)
        #expect(fixture.model.coverFlow.isVisible)
    }

    /// AC4（整合）：Editor 寫入成功 → 補讀確認有詞 → 彩帶撒完後升回
    @Test func savingLyricsRaisesCoverFlowAfterTheConfetti() async {
        let music = MockMusicClient(script: [
            .track(.fixture(id: "PID1"), lyrics: ""),
            .track(.fixture(id: "PID1"), lyrics: "new words"),     // 寫入後的補讀
        ])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        let model = fixture.model
        model.editor.isEditorTabActive = false     // 不讓自動抓詞與本測試搶 busy
        model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil { model.lyricsFlow.status == .missing }
        #expect(model.lyricsFlow.surface == .editor)

        model.editor.lyricsText = "new words"
        await model.editor.save()
        await fixture.clock.waitUntilPending(1)
        await waitFor { await music.currentTrackCalls == 2 }
        await waitUntil { model.coverFlow.details["PID1"]?.lyrics == "new words" }
        #expect(model.lyricsFlow.surface == .editor, "彩帶撒完才升回")
        #expect(model.lyricsFlow.status == .present, "補讀確認寫入生效")

        await fixture.clock.releaseAll()
        await waitUntil { model.lyricsFlow.surface == .coverFlow }
        #expect(model.lyricsFlow.surface == .coverFlow)
        #expect(model.coverFlow.isVisible)
    }

    /// AC5（整合）：標記「沒有歌詞」→ 升回、取消自動抓詞；標記存在設定裡，重啟後同曲不跳 Editor、不自動抓詞
    @Test func markingNoLyricsRaisesAndSurvivesRelaunch() async {
        let music = MockMusicClient(script: [.track(.fixture(id: "PID1"), lyrics: "")])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        let model = fixture.model
        model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil { model.lyricsFlow.status == .missing }
        #expect(model.editor.autoFetchTask != nil, "缺詞曲在 Editor 分頁自動抓詞")

        model.lyricsFlow.markNoLyrics(persistentID: "PID1")
        #expect(model.lyricsFlow.surface == .coverFlow)
        #expect(model.editor.autoFetchTask == nil, "標記取消了自動抓詞")

        let relaunchedMusic = MockMusicClient(script: [.track(.fixture(id: "PID1"), lyrics: "")])
        let relaunchedMonitor = NowPlayingMonitor(music: relaunchedMusic, clock: ImmediateClock())
        let relaunched = makeModel(store: fixture.store, music: relaunchedMusic, monitor: relaunchedMonitor)
        relaunched.startEventLoop()
        await relaunchedMonitor.tick()
        await waitUntil { relaunched.lyricsFlow.status == .markedNone }

        #expect(relaunched.lyricsFlow.surface == .coverFlow)
        #expect(relaunched.editor.autoFetchTask == nil, "標記過的曲不自動抓詞")
    }

    /// AC6（整合）：點中心卡進 Editor 後，同曲重發（forceRefresh）只更新狀態，不把使用者踢回 Cover Flow
    @Test func sameTrackRefreshKeepsTheEditorTheUserOpened() async {
        let music = MockMusicClient(script: [
            .track(.fixture(id: "PID1"), lyrics: "words"),
            .track(.fixture(id: "PID1"), lyrics: "words v2"),
        ])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        let model = fixture.model
        model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil { model.lyricsFlow.surface == .coverFlow }

        model.lyricsFlow.tapPlayingCard(isCentered: true)
        #expect(model.lyricsFlow.surface == .editor)
        #expect(!model.coverFlow.isVisible)

        await fixture.monitor.forceRefresh()
        await waitUntil { model.coverFlow.details["PID1"]?.lyrics == "words v2" }
        #expect(model.coverFlow.details["PID1"]?.lyrics == "words v2", "同曲重發已處理")
        #expect(model.lyricsFlow.surface == .editor)
    }

    /// H-05 × 畫面翻轉：使用者在 Cover Flow 滑走後換到缺詞曲（畫面降下）→ 接管解除，中心回到新的當前曲
    @Test func realChangeWhileTheSurfaceFlipsResetsTheUserOverride() async {
        let music = MockMusicClient(script: [
            .track(.fixture(id: "PID1"), lyrics: "words"),
            .track(.fixture(id: "PID2"), lyrics: "words"),
            .track(.fixture(id: "PID3"), lyrics: ""),
        ])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        let model = fixture.model
        model.editor.isEditorTabActive = false
        model.startEventLoop()
        await fixture.monitor.tick()
        await fixture.monitor.tick()
        await waitUntil { model.coverFlow.cards.count == 2 }
        let first = model.coverFlow.cards[0].id
        model.coverFlow.userDidScroll(to: first)
        #expect(model.coverFlow.centerID == first)

        await fixture.monitor.tick()
        await waitUntil { model.lyricsFlow.status == .missing }

        #expect(model.lyricsFlow.surface == .editor)
        #expect(model.coverFlow.centerID == model.coverFlow.deck.currentCardID, "真實換歌解除接管")
        #expect(model.coverFlow.deck.cards.last?.persistentID == "PID3")
    }

    /// D10：分頁只剩 Editor 與 Batch（Cover Flow 改為 Editor 內的一層）
    @Test func tabsAreEditorAndBatchOnly() {
        #expect(AppTab.allCases == [.editor, .batch])
    }

    /// D11：單元測試 host 不得輪詢使用者的 Music（以不回應的替身取代）
    @Test func unitTestHostUsesInertMusicClient() {
        #expect(AppModel.makeLiveMusic(isUnitTestHost: true) is InertMusicClient)
        #expect(AppModel.makeLiveMusic(isUnitTestHost: false) is MusicAppleEventsClient)
    }

    @Test func inertMusicClientReportsNothingPlayingAndNeverWrites() async throws {
        let music = InertMusicClient()
        #expect(try await music.currentTrack() == nil)
        #expect(try await music.playerState() == .stopped)
        #expect(try await music.nowPlaying() == nil)
        #expect(try await music.trackDetails(persistentIDs: ["PID1"]).isEmpty)
        #expect(try await music.albumTracks(artist: "a", album: "b").isEmpty)
        #expect(try await music.setLyrics(persistentID: "PID1", lyrics: "x") == false)
        #expect(try await music.artworkData(persistentID: "PID1") == nil)
    }

    @Test func batchLoadCompletionMustNotClearEditorBusy() async {
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks([.fixture(id: "T1", title: "Alpha", lyrics: "")])
        let fixture = makeFixture(music: music)
        defer { fixture.tearDown() }
        let model = fixture.model
        let monitor = fixture.monitor

        // Editor 卡在抓詞中
        let gate = LyricsGate()
        model.editor.lyricsService = LyricsService(
            genius: GatedLyricsSource(gate: gate, result: .found("body")),
            darkLyrics: StubLyricsSource(.notFound)
        )
        model.editor.handle(.trackChanged(.fixture(), existingLyrics: ""))
        let editorTask = Task { await model.editor.fetch() }
        await waitUntil { model.editor.isBusy }
        // 不再需要 settle()：onBusyChange 已是 async，busy 在同一條 await 鏈上抵達 monitor

        // 使用者切到 Batch → 載入整輪跑完 → 送出 false
        await model.batch.loadAlbum()

        // Editor 仍在抓詞：輪詢必須仍被擋住
        let before = await music.currentTrackCalls
        await monitor.tick()
        let after = await music.currentTrackCalls
        #expect(after == before, "Batch 載入完成不得清掉 Editor 仍需維持的 busy")

        await gate.open()
        await editorTask.value
    }

    // MARK: Batch 匯入 → Cover Flow（2026-09-25 回報；計劃 2026-09-25-batch-import-coverflow-refresh）
    // 全程經 `model.batch` 的公開操作驅動，不直接呼叫 `lyricsFlow.batchSaved`（Codex R1-9）

    private func batchFixture(_ music: MockMusicClient) -> Fixture {
        let fixture = makeFixture(music: music)
        fixture.model.editor.isEditorTabActive = false     // 不讓 Editor 自動抓詞攪進來
        fixture.model.startEventLoop()
        return fixture
    }

    private func importAll(_ model: AppModel) async {
        model.select(.batch)
        await model.batch.loadTask?.value
        model.batch.requestImportAll()
        await model.batch.confirmImportAll()
    }

    /// AC1／AC6：播過的缺詞曲 A 被 Import All 寫入 → 左側那張立即 ✓；非當前曲不補讀（不多問 Music）
    @Test func importAllRefreshesThePlayedCardWithoutReadingMusicAgain() async throws {
        let music = MockMusicClient(script: [
            .track(.fixture(id: "PID1", title: "A"), lyrics: ""),
            .track(.fixture(id: "PID2", title: "B"), lyrics: "words"),
        ])
        await music.setAlbumTracks([.fixture(id: "PID1", title: "A", lyrics: "batch words")])
        let fixture = batchFixture(music)
        defer { fixture.tearDown() }
        let coverFlow = fixture.model.coverFlow
        await fixture.monitor.tick()
        await fixture.monitor.tick()
        await waitUntil { coverFlow.cards.count == 2 }
        let played = try #require(coverFlow.cards.first { $0.persistentID == "PID1" })
        #expect(coverFlow.status(for: played) == .missing)

        let readsBefore = await music.nowPlayingCalls
        await importAll(fixture.model)
        await fixture.model.lyricsFlow.settleForTesting()
        await settle(300)

        #expect(coverFlow.status(for: played) == .present)
        #expect(await music.nowPlayingCalls == readsBefore, "非當前曲不補讀")
        #expect(fixture.model.lyricsFlow.surface == .coverFlow)
    }

    /// AC4：Batch 寫到當前缺詞曲 → 補讀確認 → 彩帶撒完升回（回 Editor 分頁即是 Cover Flow）
    @Test func importAllOfTheMissingCurrentTrackRaisesCoverFlow() async throws {
        let music = MockMusicClient(script: [
            .track(.fixture(id: "PID1", title: "A"), lyrics: ""),
            .track(.fixture(id: "PID1", title: "A"), lyrics: "batch words"),     // Batch 載入與寫入後的補讀
        ])
        await music.setAlbumTracks([.fixture(id: "PID1", title: "A", lyrics: "batch words")])
        let fixture = batchFixture(music)
        defer { fixture.tearDown() }
        let model = fixture.model
        await fixture.monitor.tick()
        await waitUntil { model.lyricsFlow.status == .missing }
        #expect(model.lyricsFlow.surface == .editor)

        await importAll(model)
        await fixture.clock.waitUntilPending(1)
        #expect(model.lyricsFlow.surface == .editor, "彩帶撒完才升回")
        await fixture.clock.releaseAll()
        await waitUntil { model.lyricsFlow.surface == .coverFlow }

        #expect(model.lyricsFlow.surface == .coverFlow)
        #expect(model.lyricsFlow.status == .present)
        model.select(.editor)
        #expect(model.coverFlow.isVisible)
    }

    /// AC9（評審 F2 的回歸）：當前曲已有詞、使用者親手降下 Editor → Import All 重寫它 → 仍是 Editor、無升回；恰讀回一次
    @Test func importAllKeepsTheEditorTheUserLoweredOverAPresentCurrentTrack() async throws {
        let music = MockMusicClient(script: [.track(.fixture(id: "PID1", title: "A"), lyrics: "words")])
        await music.setAlbumTracks([.fixture(id: "PID1", title: "A", lyrics: "words")])
        let fixture = batchFixture(music)
        defer { fixture.tearDown() }
        let model = fixture.model
        await fixture.monitor.tick()
        await waitUntil { model.lyricsFlow.surface == .coverFlow }
        model.lyricsFlow.toggleHandle()
        #expect(model.lyricsFlow.surface == .editor)

        let readsBefore = await music.nowPlayingCalls
        await importAll(model)
        await waitFor { await music.nowPlayingCalls == readsBefore + 1 }
        await model.lyricsFlow.settleForTesting()
        await settle(300)

        #expect(await music.writes["PID1"] == "words")
        #expect(model.lyricsFlow.surface == .editor, "Batch 不得覆寫使用者親手選的畫面")
        #expect(await fixture.clock.pendingCount == 0, "不排升回")
        #expect(await music.nowPlayingCalls == readsBefore + 1, "恰讀回一次")
    }
}
