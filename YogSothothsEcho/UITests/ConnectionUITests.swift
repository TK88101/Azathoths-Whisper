import XCTest

// S2 T10（sprint-2-detail.md §4.12、§7「X」）：模擬器無相機，以 DEBUG 假載荷與假連線器走配對畫面。
// 不截圖（QR 為一次性秘密；scheme 已關自動截圖）
final class ConnectionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ extra: [String], language: String = "en", locale: String = "en_US") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, AccessibilityID.fakeRemoteArgument] + extra
        app.launch()
        return app
    }

    func testPairingFlowWithFakePayload() {
        let app = launch([AccessibilityID.fakePayloadArgument])
        let suffix = app.staticTexts[AccessibilityID.pairingSuffix]
        XCTAssertTrue(suffix.waitForExistence(timeout: 10), "state=\(app.staticTexts[AccessibilityID.connectionState].label)")
        XCTAssertEqual(suffix.label, "0A0B")
        // CR-023：連線狀態與 Mac 名稱在左上設定鈕開的設定頁
        let settings = app.buttons[AccessibilityID.settingsButton]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Azathoth-TEST"].exists)
        app.buttons[AccessibilityID.settingsDone].tap()
    }

    func testCameraDeniedShowsSettingsLink() {
        let app = launch([AccessibilityID.cameraDeniedArgument])
        XCTAssertTrue(app.buttons[AccessibilityID.openSettingsButton].waitForExistence(timeout: 10))
    }

    /// S6.5 T6（s6-5-pairing-redesign.md §5）：日文＋最大輔助字級時，標題區、主要按鈕、外觀三選一都在視窗內且互不重疊
    func testPairingLayoutFitsLargestTextJapanese() {
        let app = launch([AccessibilityID.cameraDeniedArgument,
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
                         language: "ja", locale: "ja_JP")
        let header = app.descendants(matching: .any)[AccessibilityID.pairingHeader]
        let button = app.buttons[AccessibilityID.openSettingsButton]
        let picker = app.descendants(matching: .any)[AccessibilityID.appearancePicker]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "state=\(app.staticTexts[AccessibilityID.connectionState].label)")
        let window = app.windows.firstMatch.frame
        // 捲動前：標題區與外觀切換在視窗內
        XCTAssertTrue(header.exists && window.contains(header.frame), "header \(header.frame) 超出視窗 \(window)")
        XCTAssertTrue(picker.exists && window.contains(picker.frame), "picker \(picker.frame) 超出視窗 \(window)")
        // 左欄放不下時可捲動（§4.2）：把按鈕捲進畫面後，按鈕在視窗內、可按、不與外觀切換重疊
        if !button.isHittable { header.swipeUp() }
        XCTAssertTrue(window.contains(button.frame), "button \(button.frame) 超出視窗 \(window)")
        XCTAssertFalse(button.frame.intersects(picker.frame), "按鈕 \(button.frame) 與外觀切換 \(picker.frame) 重疊")
        XCTAssertTrue(button.isHittable)
        XCTAssertTrue(picker.isHittable)
    }
}
