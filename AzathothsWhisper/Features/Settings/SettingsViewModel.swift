import Foundation

// Settings modal 狀態（py:776-872）。token、language、notifications 三組互斥顯示
// （notifications 為 2.1 新增，計劃 2026-09-26-lyrics-notification §4.4）。
@MainActor
@Observable
final class SettingsViewModel {
    enum Group: Equatable {
        case token
        case language
        case notifications
        /// ⑨ iCloud 同步（計劃 2026-11-03-lyrics-icloud-sync §6.6）
        case cloudSync
    }

    enum FieldStatus: Equatable {
        case none
        case info(String)
        case success(String)
        case failure(String)

        var message: String? {
            switch self {
            case .none: return nil
            case .info(let text), .success(let text), .failure(let text): return text
            }
        }
    }

    private(set) var group: Group = .token
    var tokenInput = ""
    /// 原版下拉只有 en/zh_TW/ja 三項；儲存值為 system 時無選項匹配（顯示空白），此處保留同一語義
    var language: AppLanguage = .system
    private(set) var tokenStatus: FieldStatus = .none
    private(set) var languageAlert: String?
    private(set) var isValidating = false
    /// 歌詞寫入通知開關（D-14）：切換即存，不經 Save 鈕
    private(set) var notificationsEnabled = true
    /// ⑨：開關與狀態；開關切換即存
    private(set) var cloudSync = CloudSyncDisplay(enabled: false)
    private(set) var isConfirmingCloudSyncReset = false

    /// modal 標題：繞過 i18n 的英文覆寫（py:788/793，ACCEPTANCE D-03）
    var title: String {
        switch group {
        case .token: return StatusText.tokenSettingsTitle
        case .language: return StatusText.languageSettingsTitle
        case .notifications: return StatusText.notificationSettingsTitle
        case .cloudSync: return StatusText.cloudSyncSettingsTitle
        }
    }

    private let validator: any TokenValidating
    private let clock: any PollClock
    private let onTokenSaved: (String) -> Void
    private let onLanguageSaved: (AppLanguage) -> Void
    private let onNotificationsToggled: (Bool) -> Void
    private let onCloudSyncToggled: (Bool) -> Void
    private let onCloudSyncReset: () async -> Void
    private let onClose: () -> Void

    init(
        validator: any TokenValidating,
        clock: any PollClock = SystemPollClock(),
        onTokenSaved: @escaping (String) -> Void,
        onLanguageSaved: @escaping (AppLanguage) -> Void,
        onNotificationsToggled: @escaping (Bool) -> Void = { _ in },
        onCloudSyncToggled: @escaping (Bool) -> Void = { _ in },
        onCloudSyncReset: @escaping () async -> Void = {},
        onClose: @escaping () -> Void
    ) {
        self.onCloudSyncToggled = onCloudSyncToggled
        self.onCloudSyncReset = onCloudSyncReset
        self.validator = validator
        self.clock = clock
        self.onTokenSaved = onTokenSaved
        self.onLanguageSaved = onLanguageSaved
        self.onNotificationsToggled = onNotificationsToggled
        self.onClose = onClose
    }

    /// py:776-796：開啟時清空狀態列，再顯示對應組
    func open(
        _ group: Group, token: String, language: AppLanguage, notificationsEnabled: Bool = true,
        cloudSync: CloudSyncDisplay = CloudSyncDisplay(enabled: false)
    ) {
        self.group = group
        self.cloudSync = cloudSync
        isConfirmingCloudSyncReset = false
        tokenInput = token
        self.language = language
        self.notificationsEnabled = notificationsEnabled
        tokenStatus = .none
        languageAlert = nil
    }

    func saveToken() async {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            tokenStatus = .failure(StatusText.tokenCannotBeEmpty)   // py:839
            return
        }

        isValidating = true
        tokenStatus = .info(StatusText.validating)
        let result = await validator.validate(token: token)
        isValidating = false

        switch result {
        case .valid:
            onTokenSaved(token)
            tokenStatus = .success(StatusText.tokenValidAndSaved)
            try? await clock.sleep(for: .milliseconds(1500))        // py:852
            onClose()
        case .invalid(let message):
            tokenStatus = .failure(StatusText.invalidToken(message))
        }
    }

    func saveLanguage() {
        onLanguageSaved(language)
        languageAlert = StatusText.languageSaved                    // py:2215
    }

    func dismissLanguageAlert() {
        languageAlert = nil
        onClose()                                                   // py:868 alert 後關閉 modal
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        onNotificationsToggled(enabled)
    }

    // MARK: ⑨ iCloud 同步

    func setCloudSyncEnabled(_ enabled: Bool) {
        cloudSync.enabled = enabled
        onCloudSyncToggled(enabled)
    }

    /// AppModel 收到新狀態時更新（modal 開著也即時重繪）
    func updateCloudSync(_ display: CloudSyncDisplay) {
        cloudSync = display
    }

    /// 重設要先確認（刪除 iCloud 上這台的資料夾）
    func requestCloudSyncReset() {
        isConfirmingCloudSyncReset = true
    }

    func cancelCloudSyncReset() {
        isConfirmingCloudSyncReset = false
    }

    func confirmCloudSyncReset() async {
        isConfirmingCloudSyncReset = false
        await onCloudSyncReset()
    }

    func close() {
        onClose()
    }
}
