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
    private(set) var settings: SettingsViewModel!

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
        splashDuration: Duration = .milliseconds(3500)     // py:1896
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

        self.settings = SettingsViewModel(
            validator: validator,
            onTokenSaved: { [weak self] token in self?.saveToken(token) },
            onLanguageSaved: { [weak self] language in self?.saveLanguage(language) },
            onClose: { [weak self] in self?.closeModal() }
        )

        editor.onBusyChange = { [weak self] busy in
            guard let self else { return }
            Task { await self.monitor.setBusy(busy) }
        }
        editor.onRequestHydrate = { [weak self] in
            guard let self else { return }
            Task { await self.monitor.forceRefresh() }
        }
    }

    /// py:1563 的舊配置檔位置（遷移期唯讀，不刪除）
    static let legacyConfigPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".azathoths_whisper_config")

    /// 生產組裝：Keychain＋UserDefaults、legacy 一次性遷移、真實 Music/HTTP
    static func live() -> AppModel {
        let store = ConfigStore(secrets: KeychainStore())
        _ = LegacyConfigMigrator.migrateIfNeeded(
            into: store,
            envPaths: DotEnv.candidatePaths(),
            legacyConfigPath: legacyConfigPath
        )

        let client = URLSessionHTTPClient()
        let music = MusicAppleEventsClient()
        return AppModel(
            configStore: store,
            httpClient: client,
            music: music,
            monitor: NowPlayingMonitor(music: music),
            validator: GeniusTokenValidator(client: client),
            initialToken: store.token,
            initialLanguage: store.language
        )
    }

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

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.monitor.events {
                self.editor.handle(event)
            }
        }
        await monitor.start()

        try? await Task.sleep(for: splashDuration)
        isSplashVisible = false
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        Task { await monitor.stop() }
    }

    // MARK: 導航與 modal

    func select(_ tab: AppTab) {
        self.tab = tab
        editor.isEditorTabActive = (tab == .editor)   // py:481
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
        // D-08：保存後即時生效，無需重啟
        editor.lyricsService = Self.makeLyricsService(client: httpClient, token: newToken)
    }

    private func saveLanguage(_ newLanguage: AppLanguage) {
        configStore.setLanguage(newLanguage)
        language = newLanguage      // E-09：重啟後生效
    }
}
