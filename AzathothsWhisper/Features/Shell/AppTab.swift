import Foundation
import SwiftUI

// 導航頁籤（py:135-136 兩個，Cover Flow 為 Plan §4.8 新增第三個）
enum AppTab: String, CaseIterable, Identifiable {
    case editor
    case batch
    case coverFlow

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .editor: return "nav_editor"
        case .batch: return "nav_batch"
        case .coverFlow: return "nav_coverflow"
        }
    }
}

enum AppInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
    static let title = "Azathoth's Whisper"
    static let author = "iBridge Zhao"
    static let email = "toadeater731@gmail.com"
    static let repository = "TK88101/Azathoths-Whisper"
    static let repositoryURL = URL(string: "https://github.com/TK88101/Azathoths-Whisper")!
}
