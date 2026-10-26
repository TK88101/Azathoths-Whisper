import Observation

@MainActor
@Observable
final class AppearanceViewModel {
    static let storageKey = "appearance"

    @ObservationIgnored private let store: SettingsStore

    var setting: AppearanceSetting {
        didSet { store.set(setting.rawValue, forKey: Self.storageKey) }
    }

    init(store: SettingsStore) {
        self.store = store
        setting = store.string(forKey: Self.storageKey).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }
}
