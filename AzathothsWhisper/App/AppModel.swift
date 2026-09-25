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
    private(set) var settings: SettingsViewModel!

    /// Editor 與 Batch 任一存檔成功都要放紙花（py:545／701／737）
    var confettiTrigger: Int { editor.confettiTrigger + batch.confettiTrigger }

    private let configStore: ConfigStore
    private let httpClient: any HTTPClient
    private let monitor: NowPlayingMonitor
    private let splashDuration: Duration
    private var eventTask: Task<Void, Never>?
    private var didStart = false

    init(
        configStore: ConfigStore,
        httpClient: any HTTPClient,
        music: any MusicControlling,
        monitor: NowPlayingMonitor,
        validator: any TokenValidating,
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
        isMusicRunning: @escaping () -> Bool = MusicProcess.isRunning
    ) {
        self.configStore = configStore
        self.httpClient = httpClient
        self.monitor = monitor
        self.token = initialToken
        self.language = initialLanguage
        self.splashDuration = splashDuration
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
            coverFlow: coverFlow,
            isMusicRunning: isMusicRunning,
            // 寫入期間 monitor 為 busy、換歌會漏掉：寫入後唯讀補讀一次（Codex R1-4）
            forceRefresh: { Task { await monitor.forceRefresh() } },
            cancelAutoFetch: { editor.cancelAutoFetch(for: $0) }
        )

        self.settings = SettingsViewModel(
            validator: validator,
            onTokenSaved: { [weak self] token in self?.saveToken(token) },
            onLanguageSaved: { [weak self] language in self?.saveLanguage(language) },
            onClose: { [weak self] in self?.closeModal() }
        )

        editor.onBusyChange = { [weak self] busy in
            guard let self else { return }
            await self.monitor.setBusy(busy, source: .editor)
        }
        editor.onRequestHydrate = { [weak self] in
            guard let self else { return }
            Task { await self.monitor.forceRefresh() }
        }
        // D8：Editor 只拿唯讀判斷式與回報出口，不持有標記 store 與狀態機
        editor.isMarkedNoLyrics = { [weak self] in self?.lyricsFlow.isMarkedNoLyrics($0) ?? false }
        editor.onSaved = { [weak self] persistentID, text in
            self?.lyricsFlow.saved(persistentID: persistentID, text: text)
        }
        editor.onSaveFailed = { [weak self] persistentID in
            self?.lyricsFlow.saveFailed(persistentID: persistentID)
        }
        editor.onUserEditedLyrics = { [weak self] in self?.lyricsFlow.userEditedLyrics() }
        lyricsFlow.onSurfaceChanged = { [weak self] _ in self?.updateCoverFlowVisibility() }
        lyricsFlow.onWriteNotConfirmed = { [weak self] _ in
            self?.editor.setExternalStatus(StatusText.writeNotConfirmed)
        }

        // C-18：只有「載入專輯」會停輪詢，Fetch Missing／Import 期間輪詢照跑
        batch.onBusyChange = { [weak self] busy in
            guard let self else { return }
            await self.monitor.setBusy(busy, source: .batch)
        }
        // C-23：載入三態文案寫在 Editor 狀態欄
        batch.onEditorStatus = { [weak self] text in
            self?.editor.setExternalStatus(text)
        }
        // Batch 寫入成功 → Cover Flow 徽章（2026-09-25 回報：匯入後卡片仍顯示缺詞）
        batch.onLyricsWritten = { [weak self] persistentID, text in
            self?.lyricsFlow.batchSaved(persistentID: persistentID, text: text)
        }
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
        let store = isTestHost
            ? ConfigStore(secrets: EphemeralSecretStore())
            : ConfigStore(secrets: KeychainStore())
        let shouldMigrate = !isTestHost
        #else
        let store = ConfigStore(secrets: KeychainStore())
        let shouldMigrate = true
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

        startEventLoop()
        await monitor.start()
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
            // D7：editor → lyricsFlow（同步）→ batch；迴圈內不 await 任何 AE
            for await event in self.monitor.events {
                self.editor.handle(event)
                self.lyricsFlow.handle(event)
                self.batch.handle(event)      // C-17：albumChanged 由 Batch 消費
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        lyricsFlow.stopPolling()
        Task { await monitor.stop() }
    }

    // MARK: 導航與 modal

    func select(_ tab: AppTab) {
        self.tab = tab
        editor.isEditorTabActive = (tab == .editor)   // py:481
        // C-01：切入 Batch 且列表為空時自動載入當前專輯（py:396）
        if tab == .batch {
            batch.tabActivated()
        } else {
            batch.tabDeactivated()
        }
        updateCoverFlowVisibility()
    }

    /// Cover Flow 可見＝Editor 分頁在前 ∧ 畫面＝Cover Flow（不可見時不預取、不佔 AE）。
    /// 由 `select` 與畫面變更兩處呼叫
    private func updateCoverFlowVisibility() {
        coverFlow.setVisible(tab == .editor && lyricsFlow.surface == .coverFlow)
    }

    func openSettings(_ group: SettingsViewModel.Group) {
        settings.open(group, token: token, language: language)
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
}
