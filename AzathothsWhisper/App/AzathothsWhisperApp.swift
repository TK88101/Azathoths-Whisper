import SwiftUI

// 單窗 app（py:1863-1871：1200×800、可縮放、標題固定英文）。
// 菜單 1:1（py:1909-1923）：Settings → Token/Language Settings…；Help → About。
// 文案硬編碼英文、不隨語言變（ACCEPTANCE A-07）。
@main
struct AzathothsWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.live()

    var body: some Scene {
        Window(AppInfo.title, id: "main") {
            RootView(model: model)
        }
        .defaultSize(width: 1200, height: 800)
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
