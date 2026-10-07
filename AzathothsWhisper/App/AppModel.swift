import Foundation

// 根狀態與依賴容器：組裝服務、跑一次性遷移、訂閱輪詢事件、分發到各 ViewModel。
@MainActor
@Observable
final class AppModel {
    enum ModalKind: Equatable {
        case settings
        case about
    }

    private(set) var tab: AppTab = .editor
    private(set) var isSplashVisible = true
    private(set) var activeModal: ModalKind?
    private(set) var token: String
    private(set) var language: AppLanguage

    let editor: EditorViewModel
    let batch: BatchViewModel
    let coverFlow: CoverFlowViewModel
    /// Editor 頁內的 Cover Flow 升降（計劃 §6、Q3b）
    let lyricsFlow: LyricsFlowModel
    /// 歌詞特效（母計劃 §2.8）：狀態層與位置時鐘；畫面在 `LyricsFXView`
    let lyricsFX: LyricsFXViewModel
    private(set) var settings: SettingsViewModel!
    /// 升起層畫 Cover Flow 還是歌詞特效（A2 計劃 §3.1）；改它只換內容、不升降
    private(set) var raisedLayerStyle: RaisedLayerStyle

    /// Editor 與 Batch 任一存檔成功都要放紙花（py:545／701／737）
    var confettiTrigger: Int { editor.confettiTrigger + batch.confettiTrigger }

    private let configStore: ConfigStore
    private let httpClient: any HTTPClient
    private let monitor: NowPlayingMonitor
    private let splashDuration: Duration
    /// 歌詞寫入通知（計劃 2026-09-26-lyrics-notification §4.5）。**不給預設值**：漏注入＝編譯錯誤
    private let notifier: any LyricsNotifying
    /// Music 的換歌通知（F1，計劃 2026-09-27-coverflow-f1-f2 §3.1）。**不給預設值**：漏注入＝編譯錯誤
    private let playerSignal: any PlayerChangeSignaling
    /// Batch 成功後自動切回 Editor 分頁的計時（§4.6）。只與 LyricsFlow 升回共用時長常數，不共用排程（R1-6）
    private let batchSwitchClock: any PollClock
    @ObservationIgnored private var pendingReturnToEditor: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var didStart = false

    init(
        configStore: ConfigStore,
        httpClient: any HTTPClient,
        music: any MusicControlling,
        monitor: NowPlayingMonitor,
        validator: any TokenValidating,
        notifier: any LyricsNotifying,
        playerSignal: any PlayerChangeSignaling,
        initialToken: String,
        initialLanguage: AppLanguage,
        splashDuration: Duration = .milliseconds(3500),    // py:1896
        /// 封面磁碟快取的目錄。**nil＝純記憶體**——單元測試預設走這條，
        /// 絕不碰使用者真實的 Caches 目錄
        artworkDiskDirectory: URL? = nil,
        /// Music 的 Queue.dat／History.dat 所在目錄。**nil＝不讀**——單元測試預設走這條，
        /// 絕不讀使用者的曲庫
        queueDirectory: URL? = nil,
        /// 升回計時（寫入成功後等彩帶撒完）
        lyricsFlowClock: any PollClock = SystemPollClock(),
        /// 換歌後履歴短重讀的時鐘（F2）。不與升回共用：可控時鐘依請求序放行，混用會放錯等待者
        historyRecheckClock: any PollClock = SystemPollClock(),
        batchSwitchClock: any PollClock = SystemPollClock(),
        /// 歌詞特效位置時鐘的輪詢節奏（母計劃 §2.3）
        positionPollClock: any PollClock = SystemPollClock(),
        isMusicRunning: @escaping () -> Bool = MusicProcess.isRunning
    ) {
        self.configStore = configStore
        self.httpClient = httpClient
        self.monitor = monitor
        self.token = initialToken
        self.language = initialLanguage
        self.raisedLayerStyle = configStore.raisedLayerStyle
        self.splashDuration = splashDuration
        self.notifier = notifier
        self.playerSignal = playerSignal
        self.batchSwitchClock = batchSwitchClock
        self.editor = EditorViewModel(
            lyricsService: Self.makeLyricsService(client: httpClient, token: initialToken),
            music: music
        )
        self.batch = BatchViewModel(
            lyricsService: Self.makeLyricsService(client: httpClient, token: initialToken),
            music: music
        )
        // 封面快取隨 AppModel 生命週期存活：切 tab 不清空，冷啟後首次進入才付取圖成本
        let artworkService = ArtworkService(
            music: music,
            disk: artworkDiskDirectory.map { ArtworkDiskCache(directory: $0) }
        )
        self.coverFlow = CoverFlowViewModel(artwork: artworkService)
        // 退避到期後重取成功時，讓已顯示佔位的那一項重讀
        // （屬 H-07 的「損毀/失敗容錯」語義；H-06 是重建＋預取，勿混）
        self.coverFlow.observeArtworkStores(from: artworkService)

        let editor = self.editor
        self.lyricsFlow = LyricsFlowModel(
            configStore: configStore,
            detailsReader: CardDetailsReader(music: music),
            queueSource: QueueFileSource(directory: queueDirectory),
            clock: lyricsFlowClock,
            historyRecheckClock: historyRecheckClock,
            coverFlow: coverFlow,
            isMusicRunning: isMusicRunning,
            // 寫入期間 monitor 為 busy、換歌會漏掉：寫入後唯讀補讀一次（Codex R1-4）
            forceRefresh: { Task { await monitor.forceRefresh() } },
            cancelAutoFetch: { editor.cancelAutoFetch(for: $0) }
        )

        self.lyricsFX = LyricsFXViewModel(
            positionClock: PlaybackPositionClock(music: music, pollClock: positionPollClock),
            recipeHistory: StoredRecipeHistory(store: configStore)
        )

        self.settings = SettingsViewModel(
            validator: validator,
            onTokenSaved: { [weak self] token in self?.saveToken(token) },
            onLanguageSaved: { [weak self] language in self?.saveLanguage(language) },
            onNotificationsToggled: { [weak self] enabled in self?.saveNotificationsEnabled(enabled) },
            onClose: { [weak self] in self?.closeModal() }
        )

        // 同一組 busy 來源扇出到 monitor 與位置時鐘（母計劃 §2.3 R2）
        editor.onBusyChange = { [weak self] busy in
            guard let self else { return }
            self.lyricsFX.positionClock.setBusy(busy, source: .editor)
            await self.monitor.setBusy(busy, source: .editor)
        }
        editor.onRequestHydrate = { [weak self] in
            guard let self else { return }
            Task { await self.monitor.forceRefresh() }
        }
        // D8：Editor 只拿唯讀判斷式與回報出口，不持有標記 store 與狀態機
        editor.isMarkedNoLyrics = { [weak self] in self?.lyricsFlow.isMarkedNoLyrics($0) ?? false }
        lyricsFX.isMarkedNoLyrics = { [weak self] in self?.lyricsFlow.isMarkedNoLyrics($0) ?? false }
        editor.onSaved = { [weak self] persistentID, text in
            self?.lyricsFlow.saved(persistentID: persistentID, text: text)
            self?.lyricsFX.lyricsUpdated(persistentID: persistentID, text: text)
        }
        editor.onSavedTrack = { [weak self] track in
            self?.postIfEnabled(
                LyricsNotificationContent.single(artist: track.artist, title: track.title, album: track.album)
            )
        }
        editor.onSaveFailed = { [weak self] persistentID in
            self?.lyricsFlow.saveFailed(persistentID: persistentID)
        }
        editor.onUserEditedLyrics = { [weak self] in self?.lyricsFlow.userEditedLyrics() }
        lyricsFlow.onSurfaceChanged = { [weak self] _ in
            self?.updateRaisedLayerVisibility()
            self?.lyricsFX.refreshStatus()   // 標記「這首沒有詞」只會經由升降變更被看見
        }
        lyricsFlow.onWriteNotConfirmed = { [weak self] _ in
            self?.editor.setExternalStatus(StatusText.writeNotConfirmed)
        }

        // C-18：只有「載入專輯」會停輪詢，Fetch Missing／Import 期間輪詢照跑
        batch.onBusyChange = { [weak self] busy in
            guard let self else { return }
            self.lyricsFX.positionClock.setBusy(busy, source: .batch)
            await self.monitor.setBusy(busy, source: .batch)
        }
        // C-23：載入三態文案寫在 Editor 狀態欄
        batch.onEditorStatus = { [weak self] text in
            self?.editor.setExternalStatus(text)
        }
        // Batch 寫入成功 → Cover Flow 徽章（2026-09-25 回報：匯入後卡片仍顯示缺詞）
        batch.onLyricsWritten = { [weak self] persistentID, text in
            self?.lyricsFlow.batchSaved(persistentID: persistentID, text: text)
            self?.lyricsFX.lyricsUpdated(persistentID: persistentID, text: text)
        }
        batch.onImportFinished = { [weak self] result in self?.batchImportFinished(result) }
    }

    /// 封面磁碟快取的位置。放 Caches 是刻意的：內容可再生，系統空間吃緊時清掉不損失資料
    static let artworkCacheDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.ibridgezhao.azathothswhisper/Artwork")

    /// py:1563 的舊配置檔位置（遷移期唯讀，不刪除）
    static let legacyConfigPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".azathoths_whisper_config")

    /// 單元測試 host 模式旗標。
    ///
    /// 由來（2026-08-23 A1 根因）：單元測試的 `TEST_HOST` 是完整 app，啟動即走 `live()`
    /// 讀真實 Keychain。app 為 ad-hoc 簽名，**每次重建重簽後代碼簽名標識改變** →
    /// Keychain item 的 ACL 不再匹配 → 系統彈 SecurityAgent 授權框 → `SecItemCopyMatching`
    /// 阻塞 → app 啟動不完成 → `The test runner hung before establishing connection`，
    /// 0 條測試執行。這使無人值守跑測試不可行。
    ///
    /// 本旗標補上 Plan §4.9「測試禁讀真實 .env／真實 Keychain」的實現缺口：
    /// 由 scheme 的 test action 顯式注入（見 project.yml），**不**依賴 XCTest 內部環境變數推測。
    /// UITests 不注入，故仍走完整 Keychain 路徑，A-05 的 token 預填驗收不受影響。
    ///
    /// **僅 DEBUG 存在**：這是測試基礎設施，不得進入 Release 成品。否則只要成品 app 啟動時
    /// 讀到 `AZW_UNIT_TEST_HOST=1`（使用者 shell 誤帶入、外部工具注入），生產路徑就會靜默
    /// 跳過 Keychain 與遷移，退化成「token 存記憶體、退出即丟」且不落任何痕跡。
    /// 單元測試固定跑 Debug（scheme 的 TestAction buildConfiguration = "Debug"），故不受影響。
    #if DEBUG
    static let unitTestHostFlag = "AZW_UNIT_TEST_HOST"

    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment[unitTestHostFlag] == "1"
    }
    #endif

    /// 生產組裝：Keychain＋UserDefaults、legacy 一次性遷移、真實 Music/HTTP
    static func live() -> AppModel {
        // 單元測試 host：短路整個 secret 路徑——不建 KeychainStore（讀會彈授權框），
        // 也不跑 legacy 遷移（它讀 .env 並**寫回** Keychain，寫入同樣觸發授權框）
        // Release 恆定走 Keychain：測試短路的分支在 Release 下**編譯不到**，
        // 物理上不可能被任何環境變數觸發（見 unitTestHostFlag 的說明）。
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment   // 每次讀都會從 environ 重建整份字典，綁一次
        // Cover Flow × 找歌詞的 UI 測試：場景化的假 Music＋測試專屬設定（見 AppModel+LyricsFlowUITest.swift）
        if let lyricsFlowModel = makeLyricsFlowUITestModelIfRequested(environment: environment) {
            return lyricsFlowModel
        }
        // H-02 UI 測試閘門：只換 Music 的真實組裝（見 AppModel+CoverFlowUITest.swift）
        if let uiTestModel = makeCoverFlowUITestModelIfRequested(environment: environment) {
            return uiTestModel
        }
        // fixture OFF 也要能記軌跡：C.6 實體手滑輪用真實 Music、以 `open --env` 正常啟動（計劃 §5.6／§5.7 (3)）。
        // 安裝條件由 shouldInstall 一處決定（路徑非空 ∧ 非單元測試 host），fixture ON 的分支已在上面裝過
        CoverFlowUITestTrace.installIfRequested(environment: environment)
        let isTestHost = environment[unitTestHostFlag] == "1"
        // 自動化測試＝單元測試 host（"1"）或 UI 測試（AppUITestCase 顯式設 "0"，仍走真 Keychain 驗 A-05）。
        // 換歌通知同理：自動化測試不監聽使用者機上的 Music（F1）。
        // 兩者一律不碰真的通知中心，否則 start() 的授權請求會在 UI 測試期間彈系統權限提示（計劃 §4.5 R0-5）
        let isAutomatedTest = environment[unitTestHostFlag] != nil
        let notifier: any LyricsNotifying = isAutomatedTest
            ? NoopLyricsNotifier()
            : SystemLyricsNotifier(center: SystemNotificationCenter())
        let playerSignal: any PlayerChangeSignaling = isAutomatedTest
            ? NoopPlayerChangeSignal()
            : MusicPlayerInfoSignal()
        let store = isTestHost
            ? ConfigStore(secrets: EphemeralSecretStore())
            : ConfigStore(secrets: KeychainStore())
        let shouldMigrate = !isTestHost
        #else
        let store = ConfigStore(secrets: KeychainStore())
        let shouldMigrate = true
        let notifier: any LyricsNotifying = SystemLyricsNotifier(center: SystemNotificationCenter())
        let playerSignal: any PlayerChangeSignaling = MusicPlayerInfoSignal()
        #endif

        if shouldMigrate {
            _ = LegacyConfigMigrator.migrateIfNeeded(
                into: store,
                envPaths: DotEnv.candidatePaths(),
                legacyConfigPath: legacyConfigPath
            )
        }

        let client = URLSessionHTTPClient()
        #if DEBUG
        let music = makeLiveMusic(isUnitTestHost: isTestHost)
        #else
        let music = MusicAppleEventsClient()
        #endif
        #if DEBUG
        // D11：單元測試 host 不讀使用者的曲庫
        let queueDirectory: URL? = isTestHost ? nil : QueueFileSource.defaultDirectory
        #else
        let queueDirectory: URL? = QueueFileSource.defaultDirectory
        #endif
        return AppModel(
            configStore: store,
            httpClient: client,
            music: music,
            monitor: NowPlayingMonitor(music: music),
            validator: GeniusTokenValidator(client: client),
            notifier: notifier,
            playerSignal: playerSignal,
            initialToken: store.token,
            initialLanguage: store.language,
            artworkDiskDirectory: artworkCacheDirectory,
            queueDirectory: queueDirectory
        )
    }

    #if DEBUG
    /// D11：單元測試 host 不得輪詢使用者的 Music——換成不回應的替身。
    /// 測試 host 啟動即走 `live()`，否則整輪單元測試期間都在讀使用者正在聽的歌
    static func makeLiveMusic(isUnitTestHost: Bool) -> any MusicControlling {
        isUnitTestHost ? InertMusicClient() : MusicAppleEventsClient()
    }
    #endif

    static func makeLyricsService(client: any HTTPClient, token: String) -> LyricsService {
        LyricsService(
            genius: GeniusSource(client: client, token: token),
            darkLyrics: DarkLyricsSource(client: client)
        )
    }

    // MARK: 生命週期

    func start() async {
        guard !didStart else { return }
        didStart = true
        // 開關為關時不要權限，等使用者打開開關那一刻（§4.5）
        if configStore.notificationsEnabled {
            notifier.requestAuthorization()
        }

        startEventLoop()
        await monitor.start()
        // 換歌當下就讀，不等下一次 3 秒輪詢（F1）；輪詢保留作通知漏送時的保底
        playerSignal.start { [monitor, weak self] in
            Task { await monitor.playerDidChange() }
            self?.lyricsFX.positionClock.resync()
        }
        lyricsFlow.startPolling()

        try? await Task.sleep(for: splashDuration)
        isSplashVisible = false
    }

    /// 只接上事件分發、不啟動輪詢。整合測試以 `monitor.tick()` 逐次驅動（計劃 Q0）；
    /// `start()` 也經由這裡接線，兩條路徑的分發順序因此只有一份定義
    func startEventLoop() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            guard let self else { return }
            // D7：editor → lyricsFlow（同步）→ lyricsFX（同步）→ batch；迴圈內不 await 任何 AE
            for await event in self.monitor.events {
                self.editor.handle(event)
                self.lyricsFlow.handle(event)
                self.lyricsFX.handle(event)
                self.batch.handle(event)      // C-17：albumChanged 由 Batch 消費
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        lyricsFlow.stopPolling()
        lyricsFX.setVisible(false)
        playerSignal.stop()
        Task { await monitor.stop() }
    }

    // MARK: 導航與 modal

    /// 使用者導覽。**任何一次呼叫都取消待執行的自動切頁，含選到目前的同一分頁**
    /// （契約，防 Batch→Editor→Batch 的 ABA，R1-4；有測試釘住，勿優化成同分頁 no-op）
    func select(_ tab: AppTab) {
        cancelPendingReturnToEditor()
        applySelection(tab)
    }

    /// 分頁切換本體。自動切頁走這裡而不經 `select`，避免計時 task 取消自己（R2-4）
    private func applySelection(_ tab: AppTab) {
        self.tab = tab
        editor.isEditorTabActive = (tab == .editor)   // py:481
        // C-01：切入 Batch 且列表為空時自動載入當前專輯（py:396）
        if tab == .batch {
            batch.tabActivated()
        } else {
            batch.tabDeactivated()
        }
        updateRaisedLayerVisibility()
    }

    /// 可見性的唯一定義（A2 計劃 §2／§3.1）：升起層可見＝Editor 分頁在前 ∧ 升起；
    /// 兩個畫面依偏好二選一，不可見的那個不預取、不讀 Music、不繪製。
    /// 由分頁切換、升降變更、選風格三處呼叫
    private func updateRaisedLayerVisibility() {
        let raised = tab == .editor && lyricsFlow.surface == .coverFlow
        coverFlow.setVisible(raised && raisedLayerStyle == .coverFlow)
        lyricsFX.setVisible(raised && raisedLayerStyle == .lyricsFX)
    }

    /// 把手右端的兩格按鈕（A2 計劃 §3.2）。存檔後重算兩個畫面的可見性
    func selectRaisedLayerStyle(_ style: RaisedLayerStyle) {
        guard style != raisedLayerStyle else { return }
        raisedLayerStyle = style
        configStore.setRaisedLayerStyle(style)
        updateRaisedLayerVisibility()
    }

    func openSettings(_ group: SettingsViewModel.Group) {
        settings.open(group, token: token, language: language, notificationsEnabled: configStore.notificationsEnabled)
        activeModal = .settings
    }

    func openAbout() {
        activeModal = .about
    }

    func closeModal() {
        activeModal = nil
    }

    // MARK: 設定寫入

    private func saveToken(_ newToken: String) {
        try? configStore.setToken(newToken)
        token = newToken
        // D-08：保存後即時生效，無需重啟（Batch 抓詞同樣走 Genius，一併重建）
        editor.lyricsService = Self.makeLyricsService(client: httpClient, token: newToken)
        batch.lyricsService = Self.makeLyricsService(client: httpClient, token: newToken)
    }

    private func saveLanguage(_ newLanguage: AppLanguage) {
        configStore.setLanguage(newLanguage)
        language = newLanguage      // E-09：重啟後生效
    }

    /// D-14：切換即存。關→開時請求授權（系統冪等，只在第一次詢問）；關閉不撤銷系統權限
    private func saveNotificationsEnabled(_ enabled: Bool) {
        configStore.setNotificationsEnabled(enabled)
        if enabled {
            notifier.requestAuthorization()
        }
    }

    // MARK: 歌詞寫入通知與 Batch 成功後切回 Editor（計劃 2026-09-26-lyrics-notification §4.5／§4.6）

    /// 每次讀開關：Settings 切換即時生效
    private func postIfEnabled(_ payload: NotificationPayload?) {
        guard let payload, configStore.notificationsEnabled else { return }
        notifier.post(payload)
    }

    private func batchImportFinished(_ result: BatchImportResult) {
        switch result {
        case .single(let artist, let title, let album, _):
            postIfEnabled(LyricsNotificationContent.single(artist: artist, title: title, album: album))
        case .batch(let summary, _):
            postIfEnabled(LyricsNotificationContent.batch(summary))
        }
        if result.returnsToEditor {
            scheduleReturnToEditor()
        }
    }

    /// 彩紙撒完（`riseDelay`）再切；新的成功事件重排，以最後一次為準
    private func scheduleReturnToEditor() {
        cancelPendingReturnToEditor()
        let generation = batch.operationGeneration
        pendingReturnToEditor = batchSwitchClock.schedule(after: LyricsFlowModel.riseDelay) { [weak self] in
            self?.returnToEditorIfUndisturbed(since: generation)
        }
    }

    /// 到期時仍在 Batch、期間沒開始新工作（⑧）、沒有任何彈框開著（⑦）才切
    private func returnToEditorIfUndisturbed(since generation: Int) {
        pendingReturnToEditor = nil
        guard tab == .batch, batch.operationGeneration == generation, !isShowingDialog else { return }
        applySelection(.editor)
    }

    /// Settings／About modal，或 Batch 自己的彈框
    private var isShowingDialog: Bool {
        activeModal != nil || batch.isShowingDialog
    }

    private func cancelPendingReturnToEditor() {
        pendingReturnToEditor?.cancel()
        pendingReturnToEditor = nil
    }
}
