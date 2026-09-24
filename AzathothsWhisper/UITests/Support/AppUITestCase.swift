import AppKit
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
    /// `environment` 追加到 launchEnvironment（H-02 UI 測試閘門的組裝旗標、軌跡路徑等）；預設為空，既有呼叫不受影響。
    @discardableResult
    func launch(language: String? = nil, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }
        // 用例間不繼承視窗狀態：任何以「視窗已隱藏」結束的用例（如 A-08 紅鈕、C-20）
        // 會把該狀態寫進 macOS saved state，令後續用例啟動後無視窗（實測會整批超時）
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        terminateStaleInstances()
        // UITests 要驗真實 Keychain 預填（A-05），故顯式聲明**不是**單元測試 host。
        // scheme 的 test action 為單元測試注入 AZW_UNIT_TEST_HOST=1（見 project.yml）；
        // 此處設回 "0" 阻斷任何環境傳播，讓 UITests 的取值與注入方式無關。
        app.launchEnvironment[AppModelTestFlags.unitTestHost] = "0"
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        self.app = app
        return app
    }

    /// 啟動前清掉同 bundle ID 的殘留實例。
    ///
    /// 為何需要（2026-08-23）：macOS 的 app 是單實例的，`XCUIApplication.launch()`
    /// 對已在執行的 app 會**激活舊實例**而非啟動新的。前一個用例若未乾淨退出，
    /// 後續用例就操作在舊實例上；A-10（Quit 必須真的終止）在連跑時會因此誤報——
    /// Quit 終止了其中一個，`app.state` 卻反映另一個仍在後台的實例（runningBackground）。
    ///
    /// 用 `NSRunningApplication` 以 **bundle ID 定界**終止，不模擬任何全域按鍵
    /// （全域 keystroke 會誤傷其他 app）。
    private func terminateStaleInstances() {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.ibridgezhao.azathothswhisper"
        )
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline,
              !NSRunningApplication.runningApplications(
                  withBundleIdentifier: "com.ibridgezhao.azathothswhisper"
              ).isEmpty {
            usleep(100_000)
        }
    }

    /// 等元素**存在且已啟用**再操作。
    ///
    /// 為何需要它（2026-08-23）：Batch 的按鈕在 `isLoadingAlbum` 期間是禁用的，
    /// 而載入時長取決於 Music.app 當下的專輯與 AE 回應速度。只 `waitForExistence`
    /// 就點擊，會在載入較慢時點到禁用的按鈕——XCUITest 不會報錯，只是靜默無效，
    /// 症狀表現為「後續的 sheet 沒出現」，很容易誤判成產品缺陷。
    @discardableResult
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
        let editor = navButton("editor")
        XCTAssertTrue(
            editor.waitForExistence(timeout: Self.mainUITimeout),
            "splash 後應出現主 UI 導航",
            file: file, line: line
        )
        assertNavLabel(editor, editorLabel, file: file, line: line)
    }

    /// 視窗截圖（只拍 app 視窗；呼叫端不得在 Token modal 開著時拍，見 memory no-credential-fields-in-ui-screenshots）
    func attach(_ name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["AZW_UI_SHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    /// 導航按鈕以 identifier 定位：按鈕帶 identifier 後，XCUITest 的 label 不再帶 `.textCase(.uppercase)`
    /// （2026-09-23 U#3：XCUI 讀到 "Editor"；同一版 app 的 AXDescription 仍是 "EDITOR"），以字樣定位會找不到
    func navButton(_ tab: String) -> XCUIElement {
        app.buttons[AccessibilityID.nav(tab)]
    }

    /// 導航字樣（含 i18n）不分大小寫比對；大寫的畫面呈現由截圖佐證
    func assertNavLabel(
        _ button: XCUIElement, _ expected: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard button.exists else {
            XCTFail("導航按鈕不存在（期待字樣 \(expected)）", file: file, line: line)
            return
        }
        XCTAssertEqual(button.label.uppercased(), expected.uppercased(), "導航字樣", file: file, line: line)
    }
}


/// UITests target 不能 `@testable import` 產品模組，故此處複寫旗標名。
/// 一致性由單元測試 `unitTestHostFlagNameMatchesUITestsCopy` 釘住，防兩邊漂移。
enum AppModelTestFlags {
    static let unitTestHost = "AZW_UNIT_TEST_HOST"
}
