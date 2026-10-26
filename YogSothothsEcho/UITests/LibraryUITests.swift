import XCTest

// S3 T11／T12（sprint-3-detail.md §7「X」）＋S6 T3（sprint-6-detail.md §4.3）：以 DEBUG 合成曲庫（名稱自編）走側封瀏覽。不截圖。
// 側封的專輯元素來自 UIKit 無障礙容器（每個可見盒一個按鈕、frame＝投影外接框），只有可見附近的盒子在樹上
final class LibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func album(_ app: XCUIApplication, _ number: Int) -> XCUIElement {
        app.buttons[AccessibilityID.libraryAlbum(String(format: "%016llx", UInt64(number)))]
    }

    func testShowsEveryAlbumAndScrollsToTheEnd() {
        let app = XCUIApplication.launchConnected()
        let count = app.staticTexts[AccessibilityID.libraryCount]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let all = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "albums 240"), object: count)
        XCTAssertEqual(XCTWaiter().wait(for: [all], timeout: 10), .completed)
        XCTAssertTrue(album(app, 1).waitForExistence(timeout: 5))
        XCTAssertTrue(album(app, 1).label.hasPrefix("Synthetic Album 001, "))
        XCTAssertFalse(album(app, 240).exists)
        let browser = app.scrollViews[AccessibilityID.libraryGrid]
        for _ in 0..<60 where !album(app, 240).exists { browser.swipeLeft(velocity: .fast) }
        XCTAssertTrue(album(app, 240).exists)
        XCTAssertFalse(album(app, 1).exists)
    }

    /// 元素框跟著投影：中央附近的盒子框在瀏覽區內、互不相同
    func testAlbumFramesFollowTheBoxes() {
        let app = XCUIApplication.launchConnected()
        XCTAssertTrue(album(app, 1).waitForExistence(timeout: 10))
        let browser = app.scrollViews[AccessibilityID.libraryGrid].frame
        let frames = (1...3).map { album(app, $0).frame }
        for frame in frames { XCTAssertTrue(browser.contains(CGPoint(x: frame.midX, y: frame.midY)), "\(frame) 不在 \(browser)") }
        XCTAssertLessThan(frames[0].midX, frames[1].midX)
        XCTAssertLessThan(frames[1].midX, frames[2].midX)
    }

    /// #6-1：捲到中段 → 回桌面 → 回到 App：停在原本那張附近，不跳回第一張
    func testBrowsePositionSurvivesBackgrounding() {
        let app = XCUIApplication.launchConnected()
        XCTAssertTrue(album(app, 1).waitForExistence(timeout: 10))
        let browser = app.scrollViews[AccessibilityID.libraryGrid]
        for _ in 0..<12 where !album(app, 40).exists { browser.swipeLeft() }
        // 等慣性停穩再記下停在中間的那張（甩動中途看到第 40 張就回桌面，最後可能停得更遠）
        sleep(2)
        let shown = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.album.'")).allElementsBoundByIndex
            .map { $0.identifier }.sorted()
        XCTAssertFalse(shown.isEmpty || shown.contains(AccessibilityID.libraryAlbum("0000000000000001")))
        let middle = shown[shown.count / 2]
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.textFields[AccessibilityID.librarySearch].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons[middle].waitForExistence(timeout: 10), "回來後應仍看得到 \(middle)")
        XCTAssertFalse(album(app, 1).exists)
    }

    func testSearchNarrowsTheList() {
        let app = XCUIApplication.launchConnected()
        let field = app.textFields[AccessibilityID.librarySearch]
        field.tap()
        field.typeText("Album 123")
        XCTAssertTrue(album(app, 123).waitForExistence(timeout: 5))
        XCTAssertFalse(album(app, 1).exists)
    }

    /// 輔助（只記錄、不當閘門）：固定的程式化手勢量捲動，作為回歸參考
    func testScrollPerformanceBaseline() {
        let app = XCUIApplication.launchConnected()
        let browser = app.scrollViews[AccessibilityID.libraryGrid]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
            browser.swipeLeft(velocity: .fast)
            browser.swipeRight(velocity: .fast)
        }
    }
}
