import Foundation
import SwiftUI

// 導航頁籤（py:135-136 兩個）。Cover Flow 已改為 Editor 頁內的一層（計劃 §2.1、Q3b）
enum AppTab: String, CaseIterable, Identifiable {
    case editor
    case batch

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .editor: return "nav_editor"
        case .batch: return "nav_batch"
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
