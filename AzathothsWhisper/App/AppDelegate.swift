import AppKit

// 退出矩陣的兩條（Plan §4.5）：
//   Dock 圖標點擊 → 重新顯示已隱藏的窗口（py:1877-1893 的 NSApplicationDidBecomeActive 觀察者等價）
//   最後窗口關閉 → 不退出（紅鈕＝隱藏，py:2052-2060）
// Cmd+Q／Dock Quit 走系統預設 terminate:，原版那整段包裝 NSApp delegate 的 hack 就此消失。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `CommandGroup(replacing: .help) {}` 只清空系統 Help 菜單的內容，菜單本身仍在，
    /// 且其標題由 AppKit 在地化（日文＝ヘルプ）——與 A-07「菜單文案硬編碼英文」相衝，
    /// 也會與我們自建的英文 "Help" 菜單重名。這裡移除所有空的頂層菜單即可去掉它。
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let mainMenu = NSApp.mainMenu else { return }
        for item in mainMenu.items where item.submenu?.numberOfItems == 0 {
            mainMenu.removeItem(item)
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
