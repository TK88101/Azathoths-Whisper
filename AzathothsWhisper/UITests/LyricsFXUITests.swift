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

    // MARK: B1（B1 計劃 §5）：風格依曲風自動選

    private func waitForRecipe(_ predicate: @escaping (String) -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let probe = element(ID.lyricsFXRecipeProbe)
        XCTAssertTrue(probe.waitForExistence(timeout: Self.timeout), "配方探針", file: file, line: line)
        let deadline = Date().addingTimeInterval(Self.timeout)
        while Date() < deadline, !predicate(probe.value as? String ?? "") {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(predicate(probe.value as? String ?? ""), "\(message)：實得 \(probe.value as? String ?? "nil")", file: file, line: line)
    }

    /// I-18：黑金屬曲風 → 組合配方，字型屬黑金屬群（Catacombs／Grimoire／Fraktur）
    func testABlackMetalTrackGetsAComposedStyle() {
        start(.lyricsFX, extra: [Scenario.raisedStyleVariable: "lyricsFX", LyricsFXPreviewFixture.genreVariable: "Black Metal"])
        waitForStyle("lyricsFX")
        waitForRecipe({ ["Catacombs", "Grimoire", "Fraktur", "Cenobyte", "DarkMetal", "Mirage"].contains($0) }, "黑金屬應抽到黑金屬群字型")
    }

    /// B2 批 1：樂團覆寫優先於曲風——曲風寫 Pop（目錄外），樂團是 AC/DC 仍得到硬搖滾群字型
    func testASignedRockBandGetsItsComposedStyleRegardlessOfGenre() {
        start(.lyricsFX, extra: [
            Scenario.raisedStyleVariable: "lyricsFX", LyricsFXPreviewFixture.artistVariable: "AC/DC", LyricsFXPreviewFixture.genreVariable: "Pop",
        ])
        waitForStyle("lyricsFX")
        waitForRecipe({ ["AlfaSlab", "Bebas", "Oswald", "Anton"].contains($0) }, "AC/DC 應抽到硬搖滾群字型")
    }

    /// B2 批 2：龐克系新進表的團同樣不看曲風——Weezer 曲風寫 Pop，仍得到 power pop 群的字型
    func testASignedPowerPopBandGetsItsComposedStyleRegardlessOfGenre() {
        start(.lyricsFX, extra: [
            Scenario.raisedStyleVariable: "lyricsFX", LyricsFXPreviewFixture.artistVariable: "Weezer", LyricsFXPreviewFixture.genreVariable: "Pop",
        ])
        waitForStyle("lyricsFX")
        waitForRecipe({ ["Rubik", "Archivo", "Elite", "Grotesk"].contains($0) }, "Weezer 應抽到 power pop 群字型")
    }

    /// I-18：認不得的曲風 → mono
    func testAnUnknownGenreStaysMono() {
        start(.lyricsFX, extra: [Scenario.raisedStyleVariable: "lyricsFX"])
        waitForStyle("lyricsFX")
        waitForRecipe({ $0 == "mono" }, "Pop 不在 B1 的兩個家族內")
    }

    /// I-21：減少動態效果一律 mono
    func testReducedMotionFallsBackToMono() {
        start(.lyricsFX, extra: [
            Scenario.raisedStyleVariable: "lyricsFX", LyricsFXPreviewFixture.genreVariable: "Black Metal",
            LyricsFXPreviewFixture.reduceMotionVariable: "1",
        ])
        waitForStyle("lyricsFX")
        waitForRecipe({ $0 == "mono" }, "減少動態效果應畫 mono")
    }
}
