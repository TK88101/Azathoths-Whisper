#if DEBUG
import Foundation
import Observation

/// Debug 包的「Developer tools」單一開關（yse-dev-tools-cleanup.md）：量測面板與診斷鈕預設不顯示。
/// 存 UserDefaults；UI 測試以啟動參數 `-debug.developerTools YES`（argument domain，不寫入）打開。Release 沒有這個型別
@MainActor
@Observable
final class DeveloperTools {
    static let key = "debug.developerTools"
    static let shared = DeveloperTools(defaults: .standard)

    @ObservationIgnored private let defaults: UserDefaults
    var isOn: Bool {
        didSet { defaults.set(isOn, forKey: Self.key) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isOn = defaults.bool(forKey: Self.key)
    }
}
#endif
