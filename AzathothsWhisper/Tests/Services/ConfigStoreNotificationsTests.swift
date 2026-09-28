import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 §4.4：通知開關存 UserDefaults，預設開（不能用 bool(forKey:)，它的預設是 false）
@Suite("ConfigStore 通知開關")
struct ConfigStoreNotificationsTests {
    private func withStore(_ body: (ConfigStore, String) throws -> Void) throws {
        let suiteName = "azw.notify.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        try body(ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults), suiteName)
    }

    @Test func defaultsToEnabled() throws {
        try withStore { store, _ in #expect(store.notificationsEnabled) }
    }

    @Test func disabledSurvivesANewStoreInstance() throws {
        try withStore { store, suiteName in
            store.setNotificationsEnabled(false)
            let reopened = ConfigStore(
                secrets: EphemeralSecretStore(), defaults: try #require(UserDefaults(suiteName: suiteName))
            )
            #expect(!reopened.notificationsEnabled)
        }
    }

    @Test func reEnablingIsPersisted() throws {
        try withStore { store, _ in
            store.setNotificationsEnabled(false)
            store.setNotificationsEnabled(true)
            #expect(store.notificationsEnabled)
        }
    }
}
