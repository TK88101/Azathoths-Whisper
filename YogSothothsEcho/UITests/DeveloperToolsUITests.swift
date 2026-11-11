import XCTest

#if DEBUG
/// Debug 包開發者工具（yse-dev-tools-cleanup.md）：預設關＝曲庫右上量測面板、唱機的量測與序列圖診斷都不顯示；
/// 調色滑桿與 swirl seed 已刪除。帶啟動參數才出現量測工具
final class DeveloperToolsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openTurntableOverlay(_ app: XCUIApplication) {
        let open = app.buttons[AccessibilityID.nowPlayingOpenTurntable]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.turntableRecord].waitForExistence(timeout: 10))
        let close = app.buttons[AccessibilityID.turntableClose]
        for _ in 0..<5 where !close.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.5)).tap()
            _ = close.waitForExistence(timeout: 1.5)
        }
        XCTAssertTrue(close.exists)
    }

    func testToolsAreHiddenByDefault() {
        let app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument])
        XCTAssertFalse(app.staticTexts[AccessibilityID.libraryCount].waitForExistence(timeout: 3))
        openTurntableOverlay(app)
        XCTAssertFalse(app.buttons["measure spin 30 s"].exists)
        XCTAssertFalse(app.buttons["swirl seed +1"].exists)
        XCTAssertFalse(app.buttons["save trace"].exists)
        XCTAssertFalse(app.sliders.firstMatch.exists)
        XCTAssertFalse(app.buttons["measure live 5+30 s"].exists)
        // 液態小樣本身仍在（要給使用者看）
        XCTAssertTrue(app.buttons[AccessibilityID.liquidPreviewButton].exists)
    }

    func testLaunchArgumentShowsMeasurementTools() {
        let app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument, AccessibilityID.developerToolsArgument, "YES"])
        XCTAssertTrue(app.staticTexts[AccessibilityID.libraryCount].waitForExistence(timeout: 10))
        openTurntableOverlay(app)
        XCTAssertTrue(app.buttons["measure spin 30 s"].exists)
        XCTAssertFalse(app.buttons["swirl seed +1"].exists)
        XCTAssertFalse(app.sliders.firstMatch.exists)
    }
}
#endif
