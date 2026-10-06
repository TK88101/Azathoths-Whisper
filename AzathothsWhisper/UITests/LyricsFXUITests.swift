import XCTest

// 歌詞特效 A2 的 E2E（A2 計劃 §5）：把手右端兩格切換、重啟保留、焦點、定格預覽。
// 全部走假 Music 組裝（場景 env，見 App/UITestSupport/LyricsFlowUITestScenario.swift）：不碰使用者曲庫與設定。
// 紀律同 AppUITestCase：不模擬全域按鍵——按鍵一律經 XCUIElement 送進被測 app
final class LyricsFXUITests: AppUITestCase {
    private typealias Scenario = LyricsFlowUITestScenario
    private typealias ID = AccessibilityID

    private static let timeout: TimeInterval = 10

    private func start(_ scenario: Scenario, resetDefaults: Bool = true, extra: [String: String] = [:]) {
        var environment = Scenario.environment(scenario, resetDefaults: resetDefaults)
        environment.merge(extra) { $1 }
        launch(environment: environment)
        waitForMainUI()
        waitForValue(element(ID.surfaceProbe), ID.raised, timeout: Self.timeout, "有詞應升起")
    }

    private func waitForStyle(_ rawValue: String, file: StaticString = #filePath, line: UInt = #line) {
        waitForValue(element(ID.raisedStyleProbe), rawValue, timeout: Self.timeout, "升起層畫面應為 \(rawValue)", file: file, line: line)
    }

    /// I-11：兩格按鈕只換內容、不升降；預設 Cover Flow
    func testStyleButtonsSwapTheRaisedLayerWithoutLowering() {
        start(.present)
        waitForStyle("coverFlow")
        let lyricsButton = app.buttons[ID.styleLyricsFX]
        let coverButton = app.buttons[ID.styleCoverFlow]
        XCTAssertTrue(lyricsButton.exists && coverButton.exists, "把手右端兩格按鈕")
        XCTAssertTrue(coverButton.isSelected)
        XCTAssertFalse(element(ID.lyricsFXLayer).exists)

        lyricsButton.click()
        waitForStyle("lyricsFX")
        XCTAssertTrue(element(ID.lyricsFXLayer).waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(lyricsButton.isSelected)
        XCTAssertEqual(element(ID.surfaceProbe).value as? String, ID.raised, "切換不升降")
        XCTAssertFalse(app.buttons[ID.playingCard].exists, "特效顯示時 Cover Flow 不在無障礙樹上")
        XCTAssertFalse(element(ID.centerLabel).exists, "特效顯示時 Cover Flow 不在無障礙樹上")

        coverButton.click()
        waitForStyle("coverFlow")
        XCTAssertFalse(element(ID.lyricsFXLayer).exists)
        XCTAssertTrue(app.buttons[ID.playingCard].waitForExistence(timeout: Self.timeout), "切回後 Cover Flow 可點")
    }

    /// I-11：重啟保留
    func testTheChosenStyleSurvivesARelaunch() {
        start(.present)
        app.buttons[ID.styleLyricsFX].click()
        waitForStyle("lyricsFX")
        app.terminate()

        start(.present, resetDefaults: false)
        waitForStyle("lyricsFX")
        XCTAssertTrue(element(ID.lyricsFXLayer).waitForExistence(timeout: Self.timeout))
    }

    /// Codex R1 #5：特效顯示時方向鍵不移動 Cover Flow；切回後恢復
    func testArrowKeysLeaveCoverFlowAloneWhileLyricsFXShows() {
        start(.present)
        let label = element(ID.centerLabel)
        XCTAssertTrue(label.waitForExistence(timeout: Self.timeout))
        let before = label.value as? String

        app.buttons[ID.styleLyricsFX].click()
        waitForStyle("lyricsFX")
        app.typeKey(.rightArrow, modifierFlags: [])
        app.buttons[ID.styleCoverFlow].click()
        waitForStyle("coverFlow")
        XCTAssertTrue(label.waitForExistence(timeout: Self.timeout))
        assertStaysFalse((label.value as? String) != before, for: 1, "特效顯示時的方向鍵不得移動 Cover Flow")

        app.typeKey(.rightArrow, modifierFlags: [])
        let moved = NSPredicate(format: "value != %@", before ?? "")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: moved, object: label)], timeout: 5),
            .completed, "切回後方向鍵恢復步進"
        )
    }

    /// I-12／I-16：定格在 3.5 秒，特效層的 a11y value＝那一刻的行（自編句子，見 LyricsFXPreviewFixture）
    func testAFrozenPreviewShowsTheLineAtThatSecond() {
        start(.lyricsFX, extra: [
            Scenario.raisedStyleVariable: "lyricsFX",
            LyricsFXPreviewFixture.previewAtVariable: "3.5",
        ])
        waitForStyle("lyricsFX")
        waitForValue(element(ID.lyricsFXLayer), "Paper boats drift past the harbor lights", timeout: Self.timeout, "應顯示 3.5 秒的行")
        attach("lyricsfx-frozen-3.5s")
    }
}
