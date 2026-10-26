import XCTest

// F-V-01 只橫屏、F-V-08 外觀選擇重開後保留（sprint-1-detail.md §4.6）。以英文介面跑，選項以文字點選
final class ShellUITests: XCTestCase {
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { app.launchArguments.append(AccessibilityID.resetSettingsArgument) }
        app.launch()
        return app
    }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testStaysLandscapeWhenDeviceTurnsPortrait() {
        let app = launch(reset: true)
        let orientation = app.staticTexts[AccessibilityID.shellOrientation]
        XCTAssertTrue(orientation.waitForExistence(timeout: 10))
        XCTAssertEqual(orientation.label, "landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertEqual(orientation.label, "landscape", "裝置轉直後畫面仍應為橫向")
    }

    func testAppearanceChoiceSurvivesRelaunch() {
        var app = launch(reset: true)
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 10))
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Dark"].isSelected)
        XCTAssertFalse(app.buttons["System"].isSelected)
    }
}
