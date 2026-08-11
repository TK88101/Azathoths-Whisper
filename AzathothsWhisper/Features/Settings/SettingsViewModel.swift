import Foundation

// Settings modal 狀態（py:776-872）。token 與 language 兩組互斥顯示。
@MainActor
@Observable
final class SettingsViewModel {
    enum Group: Equatable {
        case token
        case language
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

    /// modal 標題：繞過 i18n 的英文覆寫（py:788/793，ACCEPTANCE D-03）
    var title: String {
        group == .token ? StatusText.tokenSettingsTitle : StatusText.languageSettingsTitle
    }

    private let validator: any TokenValidating
    private let clock: any PollClock
    private let onTokenSaved: (String) -> Void
    private let onLanguageSaved: (AppLanguage) -> Void
    private let onClose: () -> Void

    init(
        validator: any TokenValidating,
        clock: any PollClock = SystemPollClock(),
        onTokenSaved: @escaping (String) -> Void,
        onLanguageSaved: @escaping (AppLanguage) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.validator = validator
        self.clock = clock
        self.onTokenSaved = onTokenSaved
        self.onLanguageSaved = onLanguageSaved
        self.onClose = onClose
    }

    /// py:776-796：開啟時清空狀態列，再顯示對應組
    func open(_ group: Group, token: String, language: AppLanguage) {
        self.group = group
        tokenInput = token
        self.language = language
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

    func close() {
        onClose()
    }
}
