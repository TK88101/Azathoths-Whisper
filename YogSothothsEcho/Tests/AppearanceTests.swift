import SwiftUI
import Testing
@testable import YogSothothsEcho

// F-V-08：外觀三選一，記在設定裡，重開後保留；儲存值無效時回到「跟隨系統」
struct AppearanceSettingTests {
    @Test func threeChoicesInDisplayOrder() {
        #expect(AppearanceSetting.allCases == [.system, .light, .dark])
    }

    @Test func colorSchemeMapping() {
        #expect(AppearanceSetting.system.colorScheme == nil)
        #expect(AppearanceSetting.light.colorScheme == .light)
        #expect(AppearanceSetting.dark.colorScheme == .dark)
    }
}

@MainActor
struct AppearanceViewModelTests {
    @Test func defaultsToSystemWhenNothingStored() {
        let model = AppearanceViewModel(store: InMemorySettingsStore())
        #expect(model.setting == .system)
    }

    @Test func choosingPersistsAndIsReadBack() {
        let store = InMemorySettingsStore()
        let model = AppearanceViewModel(store: store)
        model.setting = .dark
        #expect(store.string(forKey: AppearanceViewModel.storageKey) == "dark")
        #expect(AppearanceViewModel(store: store).setting == .dark)
    }

    @Test func invalidStoredValueFallsBackToSystem() {
        let store = InMemorySettingsStore()
        store.set("sepia", forKey: AppearanceViewModel.storageKey)
        #expect(AppearanceViewModel(store: store).setting == .system)
    }
}

@MainActor
struct UserDefaultsSettingsStoreTests {
    @Test func roundTripsThroughAnIsolatedSuite() throws {
        let suite = "yse-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        #expect(store.string(forKey: "k") == nil)
        store.set("v", forKey: "k")
        #expect(store.string(forKey: "k") == "v")
        store.removeValue(forKey: "k")
        #expect(store.string(forKey: "k") == nil)
    }
}
