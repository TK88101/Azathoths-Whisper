import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE F-01 / G-15：舊配置讀取語義與語言偵測映射，逐案對照 Python golden
@Suite("LegacyConfig")
struct LegacyConfigTests {
    private struct ConfigFile: Decodable {
        struct Expected: Decodable {
            let token: String
            let language: String
        }
        struct Case: Decodable {
            let desc: String
            let file: String?
            let envToken: String?
            let envLang: String?
            let expected: Expected

            private enum CodingKeys: String, CodingKey {
                case desc, file, expected
                case envToken = "env_token"
                case envLang = "env_lang"
            }
        }
        let cases: [Case]
    }

    private struct LanguageFile: Decodable {
        struct Case: Decodable {
            let appDefaults: String?
            let globalDefaults: String?
            let expected: String

            private enum CodingKeys: String, CodingKey {
                case expected
                case appDefaults = "app_defaults"
                case globalDefaults = "global_defaults"
            }
        }
        let cases: [Case]
    }

    private func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let url = try GoldenFixtures.fixturesRoot().appendingPathComponent("golden/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    @Test func legacyResolutionMatchesGolden() throws {
        let file = try decode(ConfigFile.self, from: "config_migration.json")
        #expect(file.cases.count == 7)
        for c in file.cases {
            let resolved = LegacyConfigReader.resolve(
                fileContents: c.file,
                envToken: c.envToken,
                envLanguage: c.envLang
            )
            #expect(resolved.token == c.expected.token, "case: \(c.desc)")
            #expect(resolved.language == c.expected.language, "case: \(c.desc)")
        }
    }

    @Test func systemLanguageDetectionMatchesGolden() throws {
        let file = try decode(LanguageFile.self, from: "language_mapping.json")
        #expect(file.cases.count == 10)
        for c in file.cases {
            let detected = SystemLanguageDetector.detect(
                appDomain: c.appDefaults,
                globalDomain: c.globalDefaults
            )
            #expect(detected == c.expected, "app: \(c.appDefaults ?? "nil") global: \(c.globalDefaults ?? "nil")")
        }
    }

    @Test func appleLanguagesMappingIsExplicit() {
        #expect(AppLanguage.system.appleLanguagesValue == nil)
        #expect(AppLanguage.en.appleLanguagesValue == ["en"])
        #expect(AppLanguage.zhTW.appleLanguagesValue == ["zh-Hant"])
        #expect(AppLanguage.ja.appleLanguagesValue == ["ja"])
    }

    @Test func legacyLanguageStringsRoundTrip() {
        #expect(AppLanguage.fromLegacy("zh_TW") == .zhTW)
        #expect(AppLanguage.fromLegacy("zh-TW") == .zhTW)
        #expect(AppLanguage.fromLegacy("zh-Hant") == .zhTW)
        #expect(AppLanguage.fromLegacy("ja") == .ja)
        #expect(AppLanguage.fromLegacy("en") == .en)
        #expect(AppLanguage.fromLegacy("system") == .system)
        #expect(AppLanguage.fromLegacy("fr") == .system)
    }
}
