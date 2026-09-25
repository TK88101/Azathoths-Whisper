import XCTest

// 2026-09-25 使用者回報的 E2E：Batch「Fetch Missing → Import All」成功後回 Editor 分頁，
// Cover Flow 上被寫入的卡片徽章應已是 ✓（計劃 2026-09-25-batch-import-coverflow-refresh T5）。
// 走假 Music＋替身專輯頁（場景 batchImport）：不碰使用者曲庫、不上網。紀律同 AppUITestCase。
final class BatchImportCoverFlowUITests: AppUITestCase {
    private typealias Scenario = LyricsFlowUITestScenario
    private typealias ID = AccessibilityID

    private static let timeout: TimeInterval = 15

    private func waitForBadge(_ card: XCUIElement, _ value: String, _ message: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        waitForValue(card, value, timeout: Self.timeout, message, file: file, line: line)   // 徽章以 DEBUG 探針判定
    }

    private func waitForStatus(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(staticText(containing: text).waitForExistence(timeout: Self.timeout),
                      "狀態欄應出現「\(text)」", file: file, line: line)
    }

    private func clickWhenHittable(_ button: XCUIElement, _ name: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntilHittable(button, timeout: Self.timeout), "\(name) 應可點", file: file, line: line)
        button.click()
    }

    func testImportAllRefreshesTheCoverFlowBadges() {
        launch(environment: Scenario.environment(.batchImport, resetDefaults: true))
        waitForMainUI()
        waitForValue(element(ID.surfaceProbe), ID.raised, timeout: Self.timeout, "播放中有詞 → Cover Flow 升起")

        // 1＝左側（履歴）、4＝右側（待播）：兩首初始缺詞；0、3 有詞
        let played = element(ID.cardPrefix + "h:" + Scenario.persistentID(at: 1) + "#0")
        let upcoming = element(ID.cardPrefix + "q:0:" + String(Scenario.itemID(at: 4)))
        waitForBadge(played, ID.badgeMissing, "匯入前：左側缺詞卡 ✗")
        waitForBadge(upcoming, ID.badgeMissing, "匯入前：右側缺詞卡 ✗")
        attach("batch-import-before")

        navButton("batch").click()
        clickWhenHittable(app.buttons["batch-fetch-missing"], "Fetch Missing")
        waitForStatus("Fetch complete.")
        clickWhenHittable(app.buttons["batch-import-all"], "Import All")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "C-15：Import All 前先出確認框")
        sheet.buttons["OK"].click()
        waitForStatus("All saved.")

        navButton("editor").click()
        waitForBadge(played, ID.badgePresent, "匯入後：左側那張應已 ✓（2026-09-25 回報的症狀）")
        waitForBadge(upcoming, ID.badgePresent, "匯入後：右側那張應已 ✓")
        let kept = element(ID.cardPrefix + "h:" + Scenario.persistentID(at: 0) + "#0")
        waitForBadge(kept, ID.badgePresent, "原本有詞的卡不變")
        attach("batch-import-after")
    }
}
