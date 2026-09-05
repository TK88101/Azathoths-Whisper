import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE F-02…F-09：Keychain/UserDefaults 落位、一次性遷移旗標、冪等、不刪舊檔
@Suite("ConfigMigration")
struct ConfigMigrationTests {
    // 每個測試自帶獨立 UserDefaults suite 與臨時目錄，互不污染
    private func makeEnvironment() throws
        -> (store: ConfigStore, secrets: EphemeralSecretStore, defaults: UserDefaults, dir: URL, suiteName: String)
    {
        let suiteName = "AzathothsWhisperTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let secrets = EphemeralSecretStore()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("azw-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ConfigStore(secrets: secrets, defaults: defaults), secrets, defaults, dir, suiteName)
    }

    private func cleanUp(dir: URL, suiteName: String) {
        try? FileManager.default.removeItem(at: dir)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test func migratesTokenFromEnvIntoSecretStore() throws {
        let env = try makeEnvironment()
        defer { cleanUp(dir: env.dir, suiteName: env.suiteName) }

        let envFile = env.dir.appendingPathComponent(".env")
        try "GENIUS_ACCESS_TOKEN=fake-token-from-env\nLANGUAGE=ja\n".write(to: envFile, atomically: true, encoding: .utf8)

        let outcome = LegacyConfigMigrator.migrateIfNeeded(
            into: env.store,
            envPaths: [envFile],
            legacyConfigPath: env.dir.appendingPathComponent("no-such-config")
        )

        #expect(outcome.didMigrate)
        #expect(env.store.token == "fake-token-from-env")
        #expect(env.store.language == .ja)
        #expect(env.defaults.stringArray(forKey: "AppleLanguages") == ["ja"])
        #expect(env.store.hasMigratedLegacy)
    }

    @Test func migratesLegacyBareTokenFile() throws {
        let env = try makeEnvironment()
        defer { cleanUp(dir: env.dir, suiteName: env.suiteName) }

        let configFile = env.dir.appendingPathComponent("config")
        try "fake-legacy-raw-token".write(to: configFile, atomically: true, encoding: .utf8)

        let outcome = LegacyConfigMigrator.migrateIfNeeded(
            into: env.store,
            envPaths: [env.dir.appendingPathComponent(".env")],
            legacyConfigPath: configFile
        )

        #expect(outcome.token == "fake-legacy-raw-token")
        #expect(env.store.token == "fake-legacy-raw-token")
        #expect(env.store.language == .system, "裸 token 檔的語言回落 system")
    }

    @Test func migrationIsIdempotentAndKeepsLegacyFiles() throws {
        let env = try makeEnvironment()
        defer { cleanUp(dir: env.dir, suiteName: env.suiteName) }

        let envFile = env.dir.appendingPathComponent(".env")
        try "GENIUS_ACCESS_TOKEN=fake-token-one\n".write(to: envFile, atomically: true, encoding: .utf8)

        _ = LegacyConfigMigrator.migrateIfNeeded(
            into: env.store, envPaths: [envFile], legacyConfigPath: env.dir.appendingPathComponent("none")
        )
        // 使用者在新版改了 token
        try env.store.setToken("fake-token-updated")

        let second = LegacyConfigMigrator.migrateIfNeeded(
            into: env.store, envPaths: [envFile], legacyConfigPath: env.dir.appendingPathComponent("none")
        )

        #expect(second.didMigrate == false, "旗標已置位，第二次不重跑")
        #expect(env.store.token == "fake-token-updated", "舊 .env 不得覆蓋新 token（F-05）")
        #expect(FileManager.default.fileExists(atPath: envFile.path), "舊檔保留不刪（F-04）")
    }

    @Test func tokenRoundTripsAndClearsOnEmpty() throws {
        let env = try makeEnvironment()
        defer { cleanUp(dir: env.dir, suiteName: env.suiteName) }

        #expect(env.store.token == "")
        try env.store.setToken("fake-token-abc")
        #expect(env.store.token == "fake-token-abc")
        try env.store.setToken("")
        #expect(env.store.token == "")
    }

    @Test func systemLanguageRemovesAppleLanguagesOverride() throws {
        let env = try makeEnvironment()
        defer { cleanUp(dir: env.dir, suiteName: env.suiteName) }

        env.store.setLanguage(.zhTW)
        #expect(env.defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hant"])

        env.store.setLanguage(.system)
        // 斷言 app 域本身已無覆寫；不能用 object(forKey:)——它會沿域鏈回落到全局域的
        // 系統 AppleLanguages，而「回落到系統值」正是 .system 要的效果。
        let appDomain = env.defaults.persistentDomain(forName: env.suiteName)
        #expect(appDomain?["AppleLanguages"] == nil)
        #expect(env.store.language == .system)
    }

    @Test func dotEnvParsesCommentsQuotesAndBlankLines() {
        let parsed = DotEnv.parse("""
        # comment line
        GENIUS_ACCESS_TOKEN="fake-quoted"

        LANGUAGE = ja
        MALFORMED
        =novalue
        """)
        #expect(parsed["GENIUS_ACCESS_TOKEN"] == "fake-quoted")
        #expect(parsed["LANGUAGE"] == "ja")
        #expect(parsed["MALFORMED"] == nil)
        #expect(parsed.count == 2)
    }

    @Test func dotEnvUsesFirstExistingPath() throws {
        let env = try makeEnvironment()
        defer { cleanUp(dir: env.dir, suiteName: env.suiteName) }

        let missing = env.dir.appendingPathComponent("missing/.env")
        let present = env.dir.appendingPathComponent("present.env")
        try "GENIUS_ACCESS_TOKEN=fake-second-path\n".write(to: present, atomically: true, encoding: .utf8)

        let loaded = DotEnv.loadFirstAvailable(paths: [missing, present])
        #expect(loaded["GENIUS_ACCESS_TOKEN"] == "fake-second-path")
    }
}
