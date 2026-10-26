import XCTest

// 使用者 2026-10-23 回報：搜尋時鍵盤在下方，側封盒子縮成約一半；此時點開專輯，詳情的封面變小、名稱與播放鍵上移。
// 期望：鍵盤不影響曲庫與詳情的版面（鍵盤疊在上面），詳情版面與沒有鍵盤時相同
final class KeyboardLayoutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func album(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.libraryAlbum(String(format: "%016llx", UInt64(n)))]
    }

    private func detailListFrame(_ app: XCUIApplication) -> CGRect {
        let list = app.descendants(matching: .any)[AccessibilityID.albumTracksList]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        sleep(1)   // 開合轉場落定
        return list.frame
    }

    func testDetailLayoutIsUnaffectedByKeyboard() {
        var app = XCUIApplication.launchConnected([AccessibilityID.resetSettingsArgument])
        XCTAssertTrue(album(app, 1).waitForExistence(timeout: 10))
        album(app, 1).tap()
        let normal = detailListFrame(app)
        app.terminate()

        app = XCUIApplication.launchConnected([AccessibilityID.resetSettingsArgument])
        let search = app.textFields[AccessibilityID.librarySearch]
        search.tap()
        search.typeText("Album 012")
        XCTAssertTrue(album(app, 12).waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.exists, "鍵盤仍在")
        album(app, 12).tap()
        let withKeyboard = detailListFrame(app)
        XCTAssertEqual(withKeyboard.minX, normal.minX, accuracy: 2, "曲目清單位置不因鍵盤改變")
        XCTAssertEqual(withKeyboard.minY, normal.minY, accuracy: 2)
    }
}
