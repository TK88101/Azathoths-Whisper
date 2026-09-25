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
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.1"
    /// 建置號（CFBundleVersion，只增不減的整數）：ad-hoc 簽名每次打包都不同，同一個版本號要能分辨是哪一次建置
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    /// 關於畫面的版本行；沒有建置號或與版本號相同（舊寫法）時只顯示版本
    static func aboutVersionLine(version: String, build: String) -> String {
        build.isEmpty || build == version ? "Version \(version)" : "Version \(version) (Build \(build))"
    }
    static let title = "Azathoth's Whisper"
    static let author = "iBridge Zhao"
    static let email = "toadeater731@gmail.com"
    static let repository = "TK88101/Azathoths-Whisper"
    static let repositoryURL = URL(string: "https://github.com/TK88101/Azathoths-Whisper")!
}
