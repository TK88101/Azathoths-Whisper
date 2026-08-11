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

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture(token: String = "fake-old") -> Fixture {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ConfigStore(secrets: InMemorySecretStore(), defaults: defaults)
        let music = MockMusicClient()
        let model = AppModel(
            configStore: store,
            httpClient: MockHTTPClient(),
            music: music,
            monitor: NowPlayingMonitor(music: music, clock: ImmediateClock()),
            validator: AlwaysValidValidator(),
            initialToken: token,
            initialLanguage: .system,
            splashDuration: .milliseconds(1)
        )
        return Fixture(model: model, store: store, defaults: defaults, suiteName: suiteName)
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
}
