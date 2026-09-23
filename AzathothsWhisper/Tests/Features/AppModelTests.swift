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
        let model = AppModel(
            configStore: store,
            httpClient: MockHTTPClient(),
            music: music,
            monitor: monitor,
            validator: AlwaysValidValidator(),
            initialToken: token,
            initialLanguage: .system,
            splashDuration: .milliseconds(1)
        )
        return Fixture(
            model: model, store: store, defaults: defaults,
            suiteName: suiteName, music: music, monitor: monitor
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

        fixture.model.select(.coverFlow)
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
}
