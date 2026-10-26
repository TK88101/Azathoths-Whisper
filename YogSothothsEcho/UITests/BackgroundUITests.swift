import XCTest

// F10 T2a／T2e（附錄 E.2、E.5）＋CR-023 D2：背景選單在左上設定鈕開的設定頁裡——選取狀態、重開後保留；
// 頂部浮層（設定鈕、搜尋框）不重疊；設定頁長 Mac 名稱不擠掉其他項。13 吋與 11 吋各跑一次（destination 決定）
final class BackgroundUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(reset: Bool, extra: [String] = []) -> XCUIApplication {
        XCUIApplication.launchConnected((reset ? [AccessibilityID.resetSettingsArgument] : []) + extra)
    }

    private func openSettings(_ app: XCUIApplication) {
        let button = app.buttons[AccessibilityID.settingsButton]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(button.label, "Settings")
        button.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.settingsDone].waitForExistence(timeout: 5))
    }

    /// 設定頁是可捲動的表單：列在可見範圍外時先往上滑
    private func row(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let element = app.buttons[label]
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), label)
        return element
    }

    func testBackgroundChoicesLiveInSettingsAndSurviveRelaunch() {
        var app = launch(reset: true)
        openSettings(app)
        XCTAssertTrue(row(app, "Silver Blue").isSelected, "預設霧銀藍")
        XCTAssertTrue(row(app, "Turntable Blur").isSelected, "詳情預設唱機式模糊")
        row(app, "Album Color").tap()
        app.swipeDown()
        row(app, "Forest Haze").tap()
        app.buttons[AccessibilityID.settingsDone].tap()
        app.terminate()

        app = launch(reset: false)
        openSettings(app)
        XCTAssertTrue(row(app, "Forest Haze").isSelected)
        XCTAssertFalse(row(app, "Silver Blue").isSelected)
        XCTAssertTrue(row(app, "Album Color").isSelected)
    }

    func testTopChromeDoesNotOverlapAndSettingsFitALongMacName() {
        let app = launch(reset: true, extra: [AccessibilityID.longMacNameArgument])
        let settings = app.buttons[AccessibilityID.settingsButton], search = app.textFields[AccessibilityID.librarySearch]
        XCTAssertTrue(settings.waitForExistence(timeout: 10) && search.exists)
        let window = app.windows.firstMatch.frame
        for item in [settings, search] { XCTAssertTrue(window.contains(item.frame), "\(item) 超出視窗：\(item.frame)") }
        XCTAssertFalse(settings.frame.intersects(search.frame))
        XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)

        openSettings(app)
        let name = app.staticTexts[String(repeating: "W", count: 40)]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let forget = app.buttons[AccessibilityID.settingsForget], appearance = app.segmentedControls[AccessibilityID.appearancePicker]
        XCTAssertTrue(forget.exists && appearance.exists)
        XCTAssertFalse(name.frame.intersects(forget.frame))
        XCTAssertFalse(name.frame.intersects(appearance.frame))
    }
}
