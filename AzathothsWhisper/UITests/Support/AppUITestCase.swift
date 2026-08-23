import XCTest

// 三個 UITest 類共用的啟動與收尾紀律。
//
// 這裡的 timeout 與終止輪詢不是隨手取的，各對應一個實測根因
// （docs/plans/2026-08-14-m6-batch.md §7.2／§7.3）：
//   - 45s：新構建的 app **首次**啟動時 XCUITest 的 "Wait for accessibility to load"
//     實測要 18.9s（後續啟動 0.4-0.6s），含 lsregister 註冊與代碼簽名驗證。全量測試中
//     UITests 緊接單元測試執行，正好落在該構建的首次啟動；用 15s 會 10/10 集體超時。
//   - 終止輪詢：terminate() 不保證同步完成，殘留實例會與下一個用例的 launch 競爭前台
//     焦點，表現為 "MenuBarItem is not foreground" 或 Quit 後 state 仍是 runningBackground
//     ——單跑必過、連跑偶發。
//
// 調參集中於此，否則散落三個檔案後只改到一半又會復發同一組 flakiness。
class AppUITestCase: XCTestCase {
    /// 首次啟動的 AX 就緒上限
    static let mainUITimeout: TimeInterval = 45
    /// 等前一個用例的行程真正消失
    static let terminationTimeout: TimeInterval = 10
    /// 等紅鈕隱藏的視窗從 AX 樹上消失
    static let windowHideTimeout: TimeInterval = 5

    private(set) var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        guard let app else { return }
        app.terminate()
        let deadline = Date().addingTimeInterval(Self.terminationTimeout)
        while app.state != .notRunning, Date() < deadline {
            usleep(100_000)
        }
        self.app = nil
    }

    /// 語言以 launchArguments 注入，只作用於該次啟動，不改使用者設定。
    @discardableResult
    func launch(language: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }
        // 用例間不繼承視窗狀態：任何以「視窗已隱藏」結束的用例（如 A-08 紅鈕、C-20）
        // 會把該狀態寫進 macOS saved state，令後續用例啟動後無視窗（實測會整批超時）
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        // UITests 要驗真實 Keychain 預填（A-05），故顯式聲明**不是**單元測試 host。
        // scheme 的 test action 為單元測試注入 AZW_UNIT_TEST_HOST=1（見 project.yml）；
        // 此處設回 "0" 阻斷任何環境傳播，讓 UITests 的取值與注入方式無關。
        app.launchEnvironment[AppModelTestFlags.unitTestHost] = "0"
        app.launch()
        self.app = app
        return app
    }

    /// 等紅鈕點下後視窗真的收起來。紅鈕＝隱藏而非退出（A-08），A-08 與 C-20 都要先
    /// 確認視窗消失，才能斷言 app 仍存活——斷言留在各用例，這裡只負責等待。
    func waitForWindowToHide(_ window: XCUIElement, timeout: TimeInterval = windowHideTimeout) {
        let deadline = Date().addingTimeInterval(timeout)
        while window.exists, Date() < deadline {
            usleep(200_000)
        }
    }

    /// splash 3.5 秒後在同一視窗切主 UI（A-02）。timeout 取值理由見類註解。
    func waitForMainUI(
        _ editorLabel: String = "EDITOR",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            app.buttons[editorLabel].waitForExistence(timeout: Self.mainUITimeout),
            "splash 後應出現主 UI 導航",
            file: file, line: line
        )
    }
}


/// UITests target 不能 `@testable import` 產品模組，故此處複寫旗標名。
/// 一致性由單元測試 `unitTestHostFlagNameMatchesUITestsCopy` 釘住，防兩邊漂移。
enum AppModelTestFlags {
    static let unitTestHost = "AZW_UNIT_TEST_HOST"
}
