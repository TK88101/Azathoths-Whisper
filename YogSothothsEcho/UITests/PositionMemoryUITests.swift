import XCTest

// S6 #6-1 g 版 T6／T7（s6-61-g-perf-wear.md §5.6、§5.7；CR-027）：重開回上次位置、清空搜尋回搜尋前位置、零結果提示
@MainActor
final class PositionMemoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func album(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.libraryAlbum(String(format: "%016llx", UInt64(n)))]
    }

    /// 1…240 中目前在無障礙樹裡（＝畫面上）的專輯編號
    private func visibleAlbums(_ app: XCUIApplication) -> Set<Int> {
        let ids = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.album."))
            .allElementsBoundByIndex.map { $0.identifier }
        return Set(ids.compactMap { Int($0.split(separator: ".").last ?? "", radix: 16) })
    }

    func testGridRelaunchReturnsToLastPosition() {
        var app = XCUIApplication.launchConnected([AccessibilityID.resetSettingsArgument])
        let button = app.buttons[AccessibilityID.browseLayoutButton]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(album(app, 1).waitForExistence(timeout: 5))
        let grid = app.scrollViews[AccessibilityID.libraryGrid]
        for _ in 0..<6 { grid.swipeUp(velocity: .fast) }
        sleep(2)
        let before = visibleAlbums(app)
        XCTAssertFalse(before.contains(1), "已捲離第一張")
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.terminate()

        app = XCUIApplication.launchConnected(keepsPosition: true)
        XCTAssertTrue(album(app, before.sorted()[before.count / 2]).waitForExistence(timeout: 10), "重開回到原位附近")
        XCTAssertFalse(album(app, 1).exists, "沒有重置回第一張")
    }

    func testClearingSearchReturnsToPreSearchAlbum() {
        let app = XCUIApplication.launchConnected([AccessibilityID.resetSettingsArgument])
        let browser = app.scrollViews[AccessibilityID.libraryGrid]
        XCTAssertTrue(album(app, 1).waitForExistence(timeout: 10))
        for _ in 0..<4 { browser.swipeLeft(velocity: .fast) }
        sleep(2)
        let before = visibleAlbums(app)
        XCTAssertFalse(before.contains(1))
        let search = app.textFields[AccessibilityID.librarySearch]
        search.tap()
        search.typeText("Album 012")
        XCTAssertTrue(album(app, 12).waitForExistence(timeout: 10))
        app.buttons["Clear"].tap()
        XCTAssertTrue(waitFor("exists == true", on: album(app, before.sorted()[before.count / 2]), timeout: 10), "清空後回到搜尋前那張")
        XCTAssertFalse(album(app, 1).exists, "沒有回到第一張")
    }

    func testZeroResultsShowsHintInBothLayouts() {
        let app = XCUIApplication.launchConnected([AccessibilityID.resetSettingsArgument])
        let search = app.textFields[AccessibilityID.librarySearch]
        let hint = app.staticTexts[AccessibilityID.libraryNoResults]
        search.tap()
        search.typeText("qqqzzz")
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertTrue(hint.label.contains("qqqzzz"))
        app.buttons[AccessibilityID.browseLayoutButton].tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "小圖也顯示")
        app.buttons["Clear"].tap()
        XCTAssertTrue(waitFor("exists == false", on: hint, timeout: 5))
    }
}
