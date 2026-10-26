import XCTest

// CR-024（s6-61-f8f9-shell.md §5.4、T3e）：底部左鍵切側封↔小圖；圖示（VoiceOver label）＝點了會變成的樣子；
// 小圖點封面開詳情、返回回小圖；重開保留；搜尋在兩種展示下一致
final class BrowseLayoutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func layoutButton(_ app: XCUIApplication) -> XCUIElement { app.buttons[AccessibilityID.browseLayoutButton] }
    private func album(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.libraryAlbum(String(format: "%016llx", UInt64(n)))]
    }

    func testToggleOpenDetailFromGridAndRelaunchKeepsLayout() {
        var app = XCUIApplication.launchConnected([AccessibilityID.resetSettingsArgument])
        let button = layoutButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(button.label, "Show as grid")
        button.tap()
        XCTAssertTrue(waitFor("label == %@", ["Show as spines"], on: button))
        XCTAssertTrue(album(app, 1).waitForExistence(timeout: 5))
        XCTAssertTrue(album(app, 6).exists, "小圖一屏看得到多張")

        album(app, 2).tap()
        let back = app.buttons[AccessibilityID.albumTracksClose]
        XCTAssertTrue(app.buttons[AccessibilityID.albumTracksRow(3)].waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(waitFor("exists == false", on: back, timeout: 5))
        XCTAssertEqual(button.label, "Show as spines", "返回後仍是小圖")
        app.terminate()

        app = XCUIApplication.launchConnected()
        XCTAssertTrue(waitFor("label == %@", ["Show as spines"], on: layoutButton(app), timeout: 10), "重開保留小圖")
        layoutButton(app).tap()
        XCTAssertTrue(waitFor("label == %@", ["Show as grid"], on: layoutButton(app)))
    }

    func testSearchWorksInBothLayouts() {
        let app = XCUIApplication.launchConnected([AccessibilityID.resetSettingsArgument])
        let search = app.textFields[AccessibilityID.librarySearch]
        search.tap()
        search.typeText("Album 012")
        XCTAssertTrue(album(app, 12).waitForExistence(timeout: 10))
        layoutButton(app).tap()
        XCTAssertTrue(album(app, 12).waitForExistence(timeout: 5))
        XCTAssertFalse(album(app, 1).exists, "小圖也只顯示搜尋結果")
    }
}
