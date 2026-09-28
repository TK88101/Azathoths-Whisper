import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 2026-09-26-lyrics-notification §4.4–§4.6：AppModel 接線
//   - 通知：開關開才送；啟動時與「關→開」時請求授權
//   - Batch 成功後等彩紙撒完（riseDelay）自動切回 Editor 分頁；
//     使用者導覽、新工作、到期時有彈框 → 不切（使用者 2026-09-27 拍板⑦⑧）
@MainActor
@Suite("AppModel 通知與自動切頁")
struct AppModelNotificationTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    private struct Fixture {
        let model: AppModel
        let store: ConfigStore
        let notifier: SpyLyricsNotifier
        let music: MockMusicClient
        let monitor: NowPlayingMonitor
        /// LyricsFlow 的升回計時
        let riseClock: GatedPollClock
        /// Batch 成功後的切頁計時（與升回計時分開注入，R1-6）
        let switchClock: GatedPollClock
        let suiteName: String

        @MainActor
        func tearDown() {
            model.stop()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture(
        tracks: [AlbumTrack] = [.fixture(id: "PID1", artist: "Opeth", title: "Bleak", album: "Blackwater Park", lyrics: "words")],
        script: [MockMusicClient.Response] = [
            .track(.fixture(id: "PID1", artist: "Opeth", title: "Bleak", album: "Blackwater Park"), lyrics: "words"),
        ],
        notificationsEnabled: Bool = true
    ) async -> Fixture {
        let suiteName = "AppModelNotificationTests-\(UUID().uuidString)"
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        store.setNotificationsEnabled(notificationsEnabled)
        let music = MockMusicClient(script: script)
        await music.setAlbumTracks(tracks)
        let monitor = NowPlayingMonitor(music: music, clock: ImmediateClock())
        let notifier = SpyLyricsNotifier()
        let riseClock = GatedPollClock()
        let switchClock = GatedPollClock()
        let model = AppModel(
            configStore: store,
            httpClient: MockHTTPClient(),
            music: music,
            monitor: monitor,
            validator: AlwaysValidValidator(),
            notifier: notifier,
            playerSignal: SpyPlayerChangeSignal(),
            initialToken: "",
            initialLanguage: .system,
            splashDuration: .milliseconds(1),
            lyricsFlowClock: riseClock,
            batchSwitchClock: switchClock,
            isMusicRunning: { true }
        )
        model.editor.isEditorTabActive = false     // 不讓 Editor 自動抓詞攪進來
        return Fixture(
            model: model, store: store, notifier: notifier, music: music, monitor: monitor,
            riseClock: riseClock, switchClock: switchClock, suiteName: suiteName
        )
    }

    /// 切到 Batch 並等專輯載入完
    private func openBatch(_ model: AppModel) async {
        model.select(.batch)
        await model.batch.loadTask?.value
    }

    private func importAll(_ model: AppModel) async {
        model.batch.requestImportAll()
        await model.batch.confirmImportAll()
    }

    /// 到期放行後讓切頁 task 跑完
    private func releaseSwitch(_ fixture: Fixture) async {
        await fixture.switchClock.waitUntilPending(1)
        await fixture.switchClock.releaseAll()
        await settle()
    }

    // MARK: - 通知

    @Test func editorSavePostsASingleNotificationWhenEnabled() async {
        let fixture = await makeFixture()
        defer { fixture.tearDown() }
        let track = TrackInfo.fixture(id: "PID1", artist: "Opeth", title: "Bleak", album: "Blackwater Park")
        fixture.model.editor.handle(.trackChanged(track, existingLyrics: "words"))

        await fixture.model.editor.save()

        #expect(fixture.notifier.posted == [
            LyricsNotificationContent.single(artist: "Opeth", title: "Bleak", album: "Blackwater Park"),
        ])
    }

    @Test func nothingIsPostedWhenNotificationsAreOff() async {
        let fixture = await makeFixture(notificationsEnabled: false)
        defer { fixture.tearDown() }
        fixture.model.editor.handle(.trackChanged(.fixture(id: "PID1"), existingLyrics: "words"))
        await fixture.model.editor.save()
        await openBatch(fixture.model)
        await importAll(fixture.model)

        #expect(fixture.notifier.posted.isEmpty)
    }

    @Test func importAllPostsOneSummary() async {
        let fixture = await makeFixture(tracks: [
            .fixture(id: "PID1", artist: "Opeth", title: "Bleak", album: "Blackwater Park", lyrics: "a"),
            .fixture(id: "PID2", artist: "Opeth", title: "Harvest", album: "Blackwater Park", lyrics: "b"),
        ])
        defer { fixture.tearDown() }
        await openBatch(fixture.model)

        await importAll(fixture.model)

        let summary = BatchWriteSummary(
            artist: "Opeth", album: "Blackwater Park", albumTrackCount: 2, succeeded: ["Bleak", "Harvest"], failed: []
        )
        #expect(fixture.notifier.posted == [LyricsNotificationContent.batch(summary)].compactMap { $0 })
    }

    @Test func startRequestsAuthorizationOnlyWhenEnabled() async {
        let enabled = await makeFixture()
        defer { enabled.tearDown() }
        await enabled.model.start()
        #expect(enabled.notifier.authorizationRequests == 1)

        let disabled = await makeFixture(notificationsEnabled: false)
        defer { disabled.tearDown() }
        await disabled.model.start()
        #expect(disabled.notifier.authorizationRequests == 0, "開關為關時不要權限，等打開那一刻")
    }

    @Test func settingsToggleIsPersistedAndTurningOnRequestsAuthorization() async {
        let fixture = await makeFixture(notificationsEnabled: false)
        defer { fixture.tearDown() }

        fixture.model.openSettings(.notifications)
        #expect(!fixture.model.settings.notificationsEnabled, "開啟時帶入目前值")
        fixture.model.settings.setNotificationsEnabled(true)
        #expect(fixture.store.notificationsEnabled)
        #expect(fixture.notifier.authorizationRequests == 1)

        fixture.model.settings.setNotificationsEnabled(false)
        #expect(!fixture.store.notificationsEnabled)
        #expect(fixture.notifier.authorizationRequests == 1, "關閉不撤銷、也不再要權限")
    }

    // MARK: - 自動切回 Editor 分頁（觸發）

    @Test func importAllSuccessReturnsToEditorAfterTheConfetti() async {
        let fixture = await makeFixture()
        defer { fixture.tearDown() }
        await openBatch(fixture.model)

        await importAll(fixture.model)
        await fixture.switchClock.waitUntilPending(1)
        #expect(fixture.model.tab == .batch, "彩紙撒完才切")
        #expect(await fixture.switchClock.requested == [LyricsFlowModel.riseDelay])
        await releaseSwitch(fixture)

        #expect(fixture.model.tab == .editor)
    }

    @Test func importSelectedSuccessReturnsToEditor() async {
        let fixture = await makeFixture()
        defer { fixture.tearDown() }
        await openBatch(fixture.model)
        fixture.model.batch.select("PID1")

        await fixture.model.batch.importSelected()
        await releaseSwitch(fixture)

        #expect(fixture.model.tab == .editor)
    }

    @Test("失敗結果不排切頁", arguments: [
        Result<Bool, MusicError>.success(false), .failure(.permissionDenied),
    ])
    func failedImportAllDoesNotSchedule(outcome: Result<Bool, MusicError>) async {
        let fixture = await makeFixture(tracks: [
            .fixture(id: "PID1", title: "Bleak", lyrics: "a"),
            .fixture(id: "PID2", title: "Harvest", lyrics: "b"),
        ])
        defer { fixture.tearDown() }
        await fixture.music.setSetLyricsOutcome(outcome, for: "PID2")
        await openBatch(fixture.model)

        await importAll(fixture.model)                   // 部分失敗
        await fixture.music.setSetLyricsOutcome(outcome)
        await importAll(fixture.model)                   // 全部失敗
        await settle()

        #expect(await fixture.switchClock.requested.isEmpty)
        #expect(fixture.notifier.posted.count == 2, "失敗照樣通知")
    }

    @Test func staleImportAllDoesNotSchedule() async {
        let fixture = await makeFixture(tracks: [
            .fixture(id: "PID1", title: "Bleak", lyrics: "a"),
            .fixture(id: "PID2", title: "Harvest", lyrics: "b"),
        ])
        defer { fixture.tearDown() }
        let gate = LyricsGate()
        await fixture.music.setWriteGate(gate)
        await openBatch(fixture.model)
        let batch = fixture.model.batch

        let task = Task { await importAll(fixture.model) }
        await waitUntil { batch.statusText == StatusText.savingProgress(1, of: 2, title: "Bleak") }
        batch.handle(.albumChanged("Other\u{1}Album"))
        await gate.open()
        await task.value
        await settle()

        #expect(await fixture.switchClock.requested.isEmpty)
        #expect(fixture.notifier.posted.count == 1, "stale 照樣通知實際寫入的部分")
    }

    // MARK: - 自動切回 Editor 分頁（取消，⑦⑧）

    /// 契約（R1-4）：任何一次使用者導覽都取消，含選到目前的同一分頁
    @Test("手動導覽取消", arguments: [[AppTab.editor, .batch], [.batch]])
    func manualNavigationCancels(route: [AppTab]) async {
        let fixture = await makeFixture()
        defer { fixture.tearDown() }
        await openBatch(fixture.model)
        await importAll(fixture.model)
        await fixture.switchClock.waitUntilPending(1)

        route.forEach(fixture.model.select)
        await fixture.switchClock.releaseAll()
        await settle()

        #expect(fixture.model.tab == .batch)
    }

    @Test func startingNewWorkCancels() async {
        let fixture = await makeFixture(tracks: [
            .fixture(id: "PID1", title: "Bleak", lyrics: "a"),
            .fixture(id: "PID2", title: "Harvest", lyrics: ""),
        ])
        defer { fixture.tearDown() }
        await openBatch(fixture.model)
        await importAll(fixture.model)
        await fixture.switchClock.waitUntilPending(1)

        await fixture.model.batch.fetchMissing()
        await releaseSwitch(fixture)

        #expect(fixture.model.tab == .batch)
    }

    @Test func browsingTheListDoesNotCancel() async {
        let fixture = await makeFixture()
        defer { fixture.tearDown() }
        await openBatch(fixture.model)
        await importAll(fixture.model)

        fixture.model.batch.select("PID1")
        await releaseSwitch(fixture)

        #expect(fixture.model.tab == .editor)
    }

    @Test("到期時有彈框就不切", arguments: ["settings", "about", "confirm", "alert"])
    func anOpenDialogAtDueTimeCancels(dialog: String) async {
        let fixture = await makeFixture()
        defer { fixture.tearDown() }
        let model = fixture.model
        await openBatch(model)
        await importAll(model)
        await fixture.switchClock.waitUntilPending(1)

        switch dialog {
        case "settings": model.openSettings(.token)
        case "about": model.openAbout()
        case "confirm": model.batch.requestImportAll()
        default: model.batch.alertMessage = "x"
        }
        await releaseSwitch(fixture)

        #expect(model.tab == .batch)
    }

    /// 連續成功以最後一次為準：前一個計時被取消，只剩一個在等
    @Test func consecutiveSuccessesReschedule() async {
        let fixture = await makeFixture()
        defer { fixture.tearDown() }
        await openBatch(fixture.model)
        fixture.model.batch.select("PID1")

        await fixture.model.batch.importSelected()
        await fixture.switchClock.waitUntilPending(1)
        await fixture.model.batch.importSelected()
        await fixture.switchClock.waitUntilPending(1)
        await settle()

        #expect(await fixture.switchClock.pendingCount == 1)
        await releaseSwitch(fixture)
        #expect(fixture.model.tab == .editor)
    }

    // MARK: - 與 LyricsFlow 升回共存（R2 補）

    /// 當前缺詞曲被 Import All 寫入：LyricsFlow 先在 Editor 分頁內升回 Cover Flow，
    /// Batch 的切頁計時到期才切分頁，切過去看到的就是 Cover Flow
    @Test func lyricsFlowRisesFirstThenTheTabSwitchLands() async {
        let fixture = await makeFixture(
            tracks: [.fixture(id: "PID1", title: "A", lyrics: "batch words")],
            script: [
                .track(.fixture(id: "PID1", title: "A"), lyrics: ""),
                .track(.fixture(id: "PID1", title: "A"), lyrics: "batch words"),     // Batch 載入與寫入後的補讀
            ]
        )
        defer { fixture.tearDown() }
        let model = fixture.model
        model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil { model.lyricsFlow.status == .missing }

        await openBatch(model)
        await importAll(model)
        await fixture.riseClock.waitUntilPending(1)
        await fixture.riseClock.releaseAll()
        await waitUntil { model.lyricsFlow.surface == .coverFlow }
        #expect(model.tab == .batch, "升回只改 Editor 分頁內的畫面")

        await releaseSwitch(fixture)

        #expect(model.tab == .editor)
        #expect(model.coverFlow.isVisible)
    }
}
