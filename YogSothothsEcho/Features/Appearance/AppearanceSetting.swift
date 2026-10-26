import SwiftUI

/// F-V-08：外殼「跟隨系統／亮色／暗色」
enum AppearanceSetting: String, CaseIterable, Sendable {
    case system, light, dark

    /// nil＝不覆寫，跟隨系統
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
