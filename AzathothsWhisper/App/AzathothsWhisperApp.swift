import SwiftUI

// 單窗 app（py:1863-1871：1200×800、可縮放、標題固定英文）。
// 菜單 1:1（py:1909-1923）：Settings → Token/Language Settings…；Help → About。
// 2.1 新增 Settings → Notification Settings…（計劃 2026-09-26-lyrics-notification §4.4）。
// 文案硬編碼英文、不隨語言變（ACCEPTANCE A-07）。
@main
struct AzathothsWhisperApp: App {
    // AppModel 由 AppDelegate 持有（登入時無視窗也要起中繼，s6-61-login-launch.md §5）
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        Window(AppInfo.title, id: "main") {
            RootView(model: model)
        }
        .defaultSize(width: 1200, height: 800)

        // ⑧ 曲庫檢查視窗：標題同選單寫死英文（A-07 的同一慣例）
        Window(Text(verbatim: LibraryCheckMenuButton.title), id: LibraryCheckMenuButton.windowID) {
            LibraryCheckView(model: model.libraryCheck)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            // 原版無「新增窗口」概念，移除 File ▸ New
            CommandGroup(replacing: .newItem) {}

            CommandMenu(Text(verbatim: "Settings")) {
                Button { model.openSettings(.token) } label: {
                    Text(verbatim: "Token Settings...")
                }
                Button { model.openSettings(.language) } label: {
                    Text(verbatim: "Language Settings...")
                }
                Button { model.openSettings(.notifications) } label: {
                    Text(verbatim: "Notification Settings...")
                }
                // Yog-Sothoth's Echo 中繼（S2 詳設 v1.1；A-07：選單寫死英文）
                Button { model.openRemoteSettings() } label: {
                    Text(verbatim: "Remote Settings...")
                }
                // ⑧ 曲庫檢查（曲庫閘門計劃 §4.5）：獨立視窗，主視窗照常運作
                LibraryCheckMenuButton()
            }

            // 系統 Help 菜單的標題由 AppKit 提供且會被在地化（日文＝ヘルプ），
            // 與 A-07「菜單文案硬編碼英文」相衝，故清空系統組再自建同名英文菜單。
            CommandGroup(replacing: .help) {}

            CommandMenu(Text(verbatim: "Help")) {
                Button { model.openAbout() } label: {
                    Text(verbatim: "About")
                }
            }
        }
    }
}

/// 選單項目要拿 `openWindow`：環境值只在 View 內讀得到
struct LibraryCheckMenuButton: View {
    static let title = "Library Check"
    static let windowID = "library-check"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { openWindow(id: Self.windowID) } label: {
            Text(verbatim: "Library Check...")
        }
    }
}
