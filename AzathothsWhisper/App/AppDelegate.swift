import AppKit

// 退出矩陣的兩條（Plan §4.5）：
//   Dock 圖標點擊 → 重新顯示已隱藏的窗口（py:1877-1893 的 NSApplicationDidBecomeActive 觀察者等價）
//   最後窗口關閉 → 不退出（紅鈕＝隱藏，py:2052-2060）
// Cmd+Q／Dock Quit 走系統預設 terminate:，原版那整段包裝 NSApp delegate 的 hack 就此消失。
//
// 也是 AppModel 的唯一擁有者（s6-61-login-launch.md §5）：登入時系統叫起 App 但不開視窗，
// 啟動工作若綁在畫面上，iPad 中繼就不會起來。App 與畫面一律經 `model` 取同一個實例。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel

    override init() {
        model = AppModel.live()
        super.init()
    }

    /// 測試注入
    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 先起中繼：與有沒有視窗、有沒有選單都無關
        model.startRelay()
        // `CommandGroup(replacing: .help) {}` 只清空系統 Help 菜單的內容，菜單本身仍在，
        // 且其標題由 AppKit 在地化（日文＝ヘルプ）——與 A-07「菜單文案硬編碼英文」相衝，
        // 也會與我們自建的英文 "Help" 菜單重名。這裡移除所有空的頂層菜單即可去掉它。
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items where item.submenu?.numberOfItems == 0 {
                mainMenu.removeItem(item)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
