import XCTest

// ⑧ 曲庫閘門計劃 §5 T8：Settings ▸ Library Check… 開獨立視窗 → 掃假曲庫 → 指定樣式後素面與身分未定的計數下降。
// 假 Music＋假曲庫（`LibraryCheckUITestFixture`）：不碰使用者曲庫與決定存檔。不模擬全域按鍵（AppUITestCase 紀律）
final class LibraryCheckUITests: AppUITestCase {
    private typealias ID = AccessibilityID
    private static let timeout: TimeInterval = 10

    func testChoosingAStyleClearsThePlainSongAndItsIdentityIssue() {
        var environment = LyricsFlowUITestScenario.environment(.notPlaying, resetDefaults: true)
        environment["AZW_LIBRARY_CHECK_FIXTURE"] = "1"
        launch(language: "en", environment: environment)
        waitForMainUI()

        app.menuBars.menuBarItems["Settings"].click()
        app.menuItems["Library Check..."].click()
        let rescan = app.buttons[ID.libraryCheckRescan]
        XCTAssertTrue(rescan.waitForExistence(timeout: Self.timeout), "曲庫檢查視窗應開啟")
        rescan.click()

        let composed = element(ID.libraryCheckComposedCount)
        XCTAssertTrue(composed.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue((composed.label as String).hasPrefix("1 "), "處理前：素面 1 首（\(composed.label)）")
        XCTAssertTrue((element(ID.libraryCheckIdentityCount).label as String).hasPrefix("2 "), "處理前：身分未定 2 首")

        let row = element(ID.libraryCheckArtistPrefix + "paper harbour")
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        row.menuButtons[ID.libraryCheckChooseStyle].click()
        app.menuItems["punk"].click()

        XCTAssertTrue(waitForLabelPrefix(composed, "0 "), "指定樣式後素面 0 首（\(composed.label)）")
        XCTAssertTrue((element(ID.libraryCheckIdentityCount).label as String).hasPrefix("1 "), "指定樣式也解除該歌手的身分未定")
    }

    private func waitForLabelPrefix(_ element: XCUIElement, _ prefix: String) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: Self.timeout) == .completed
    }
}
