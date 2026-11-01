#if DEBUG
import Foundation
import Testing

@testable import YogSothothsEcho

// Debug 包開發者工具開關（yse-dev-tools-cleanup.md）：預設關；UI 測試以啟動參數（argument domain）打開；切換寫入 UserDefaults
@MainActor
struct DeveloperToolsTests {
    private func suite() -> (UserDefaults, String) {
        let name = "DeveloperToolsTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func offByDefault() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!DeveloperTools(defaults: defaults).isOn)
    }

    @Test func toggleIsPersisted() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let tools = DeveloperTools(defaults: defaults)
        tools.isOn = true
        #expect(defaults.bool(forKey: DeveloperTools.key))
        #expect(DeveloperTools(defaults: defaults).isOn)
        tools.isOn = false
        #expect(!DeveloperTools(defaults: defaults).isOn)
    }

    /// 啟動參數 `-debug.developerTools YES` 由 argument domain 讀到（UI 測試用；不寫入持久值）
    @Test func launchArgumentNameMatchesKey() {
        #expect(AccessibilityID.developerToolsArgument == "-" + DeveloperTools.key)
        #expect(DeveloperTools.key == "debug.developerTools")
    }
}
#endif
