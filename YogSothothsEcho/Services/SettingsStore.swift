import Foundation

/// 設定的讀寫邊界（Bjork 慣例：外部邊界一律 protocol＋替身）
@MainActor
protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
}

@MainActor
final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func set(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    func removeValue(forKey key: String) { defaults.removeObject(forKey: key) }
}

/// 測試與 Preview 用
@MainActor
final class InMemorySettingsStore: SettingsStore {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func removeValue(forKey key: String) { values[key] = nil }
}
