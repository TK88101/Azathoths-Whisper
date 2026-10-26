import XCTest

/// 播放 UI 測試共用（S4）：以合成連線器配對並連上、開第一張合成專輯、等標籤或元素消失
extension XCUIApplication {
    /// `keepsPosition`＝保留上次的位置記憶（測「重開回原位」用）；其餘測試一律從第一張開始，不受前一條測試停下的位置影響
    static func launchConnected(_ extra: [String] = [], keepsPosition: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", AccessibilityID.fakeRemoteArgument,
                               AccessibilityID.fakePayloadArgument] + (keepsPosition ? [] : [AccessibilityID.resetPositionArgument]) + extra
        app.launch()
        XCTAssertTrue(app.textFields[AccessibilityID.librarySearch].waitForExistence(timeout: 20))
        return app
    }

    /// 點第一張合成專輯 → 曲目清單出現（等到第 `row` 列）
    func openFirstAlbum(waitingFor row: Int = 3) {
        let cell = buttons[AccessibilityID.libraryAlbum("0000000000000001")]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        XCTAssertTrue(buttons[AccessibilityID.albumTracksRow(row)].waitForExistence(timeout: 10))
    }
}

func waitFor(_ predicate: String, _ args: [Any] = [], on element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate, argumentArray: args), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
}
