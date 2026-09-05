import Foundation

// 現行配置的唯一真源：token → Keychain、language → UserDefaults（Plan §4.9）。
// 遷移完成後不再讀 legacy（.env / ~/.azathoths_whisper_config），以免舊檔覆蓋使用者新存的 token
// （原版 env 恆優先屬缺陷，見 ACCEPTANCE F-05）。
// @unchecked：UserDefaults 未標注 Sendable，但 Apple 文件明載其為 thread-safe。
struct ConfigStore: @unchecked Sendable {
    enum Key {
        static let token = "GENIUS_ACCESS_TOKEN"
        static let language = "AppLanguage"
        static let migrationVersion = "LegacyConfigMigratedVersion"
    }

    /// 遷移格式版本；日後若 legacy 讀取語義再變，遞增此值即可重跑遷移。
    static let currentMigrationVersion = 1

    let secrets: any SecretStore
    let defaults: UserDefaults

    init(secrets: any SecretStore, defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults
    }

    var token: String {
        ((try? secrets.read(Key.token)) ?? nil) ?? ""
    }

    func setToken(_ value: String) throws {
        if value.isEmpty {
            try secrets.delete(Key.token)
        } else {
            try secrets.write(value, for: Key.token)
        }
    }

    var language: AppLanguage {
        guard let raw = defaults.string(forKey: Key.language) else { return .system }
        return AppLanguage(rawValue: raw) ?? .system
    }

    func setLanguage(_ value: AppLanguage) {
        defaults.set(value.rawValue, forKey: Key.language)
        // Plan §4.6：語言覆寫寫 per-app AppleLanguages，重啟生效；system 表示刪鍵跟隨系統
        if let apple = value.appleLanguagesValue {
            defaults.set(apple, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    var hasMigratedLegacy: Bool {
        defaults.integer(forKey: Key.migrationVersion) >= Self.currentMigrationVersion
    }

    func markLegacyMigrated() {
        defaults.set(Self.currentMigrationVersion, forKey: Key.migrationVersion)
    }
}

// 一次性 legacy 遷移：讀 .env 三級路徑＋舊 config 檔 → 寫入 Keychain/UserDefaults → 置旗標。
// 舊檔一律保留不刪（Python 版並存期仍需使用）。
enum LegacyConfigMigrator {
    struct Outcome: Equatable {
        let didMigrate: Bool
        let token: String
        let language: AppLanguage
    }

    static func migrateIfNeeded(
        into store: ConfigStore,
        envPaths: [URL],
        legacyConfigPath: URL,
        fileManager: FileManager = .default
    ) -> Outcome {
        guard !store.hasMigratedLegacy else {
            return Outcome(didMigrate: false, token: store.token, language: store.language)
        }

        let env = DotEnv.loadFirstAvailable(paths: envPaths, fileManager: fileManager)
        let fileContents: String? = fileManager.fileExists(atPath: legacyConfigPath.path)
            ? try? String(contentsOf: legacyConfigPath, encoding: .utf8)
            : nil

        let legacy = LegacyConfigReader.resolve(
            fileContents: fileContents,
            envToken: env["GENIUS_ACCESS_TOKEN"],
            envLanguage: env["LANGUAGE"]
        )

        if !legacy.token.isEmpty {
            try? store.setToken(legacy.token)
        }
        let language = AppLanguage.fromLegacy(legacy.language)
        if language != .system {
            store.setLanguage(language)
        }
        store.markLegacyMigrated()
        return Outcome(didMigrate: true, token: legacy.token, language: language)
    }
}
