import Foundation
import Testing

@testable import AzathothsWhisper

// 升起層畫面偏好（A2 計劃 §3.1）
@Suite("ConfigStore raisedLayerStyle")
struct ConfigStoreRaisedLayerStyleTests {
    private func store() -> (ConfigStore, String) {
        let suiteName = "ConfigStoreRaisedLayerStyleTests-\(UUID().uuidString)"
        return (ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!), suiteName)
    }

    @Test func defaultsToCoverFlow() {
        let (store, suite) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        #expect(store.raisedLayerStyle == .coverFlow)
    }

    @Test func roundTrips() {
        let (store, suite) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.setRaisedLayerStyle(.lyricsFX)
        #expect(store.raisedLayerStyle == .lyricsFX)
        #expect(store.defaults.string(forKey: ConfigStore.Key.raisedLayerStyle) == "lyricsFX")
    }

    @Test func anUnknownValueFallsBackToCoverFlow() {
        let (store, suite) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.defaults.set("hologram", forKey: ConfigStore.Key.raisedLayerStyle)
        #expect(store.raisedLayerStyle == .coverFlow)
    }
}
