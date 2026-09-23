import XCTest

// Cover Flow × 找歌詞的 E2E（計劃 AC1–AC5、AC14）。Q3.5 先寫、使用者在場 #2 取紅燈、Q4 做綠。
// 全部走假 Music 組裝（場景 env，見 App/UITestSupport/LyricsFlowUITestScenario.swift）：
// 不碰使用者曲庫、Keychain、`.standard` 設定。
// 紀律同 AppUITestCase：不模擬全域按鍵——按鍵一律經 XCUIElement 送進被測 app。
final class LyricsFlowUITests: AppUITestCase {
    private typealias Scenario = LyricsFlowUITestScenario
    private typealias ID = AccessibilityID

    /// 升回＝彩帶撒完（約 3.2 秒）＋一次補讀；留足餘量
    private static let riseTimeout: TimeInterval = 15
    private static let surfaceTimeout: TimeInterval = 10

    private func start(_ scenario: Scenario, resetDefaults: Bool = true) {
        launch(environment: Scenario.environment(scenario, resetDefaults: resetDefaults))
        waitForMainUI()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Cover Flow 層常駐（降下時只露把手）：以 value 判定升降，不能只看「存在」
    @discardableResult
    private func waitForSurface(raised: Bool, timeout: TimeInterval = surfaceTimeout,
                                file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let layer = element(ID.surfaceProbe)
        let predicate = NSPredicate(format: "value == %@", raised ? ID.raised : ID.lowered)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: layer)], timeout: timeout)
        XCTAssertEqual(result, .completed, raised ? "Cover Flow 應升起" : "Cover Flow 應降下", file: file, line: line)
        return result == .completed
    }

    private func fetchCount() -> String? {
        element(ID.fetchCount).value as? String
    }

    private func hydrateCount() -> String? {
        element(ID.hydrateCount).value as? String
    }

    /// 升起且落定：播放卡按鈕只在它**位於幾何正中**時存在——能證明條帶真的捲到播放卡（不只 reducer 說升起）
    private func waitForRaisedAndSettled(timeout: TimeInterval = surfaceTimeout,
                                         file: StaticString = #filePath, line: UInt = #line) {
        waitForSurface(raised: true, timeout: timeout, file: file, line: line)
        XCTAssertTrue(app.buttons[ID.playingCard].waitForExistence(timeout: timeout),
                      "升起後播放卡應位於正中、可點", file: file, line: line)
        XCTAssertFalse(element(ID.editorLayer).exists, "升起時 Editor 不掛載", file: file, line: line)
    }

    /// 降下且可用：Editor 的控件出現（不只 reducer 說降下）
    private func waitForLoweredAndUsable(file: StaticString = #filePath, line: UInt = #line) {
        waitForSurface(raised: false, file: file, line: line)
        XCTAssertTrue(element(ID.lyricsText).waitForExistence(timeout: Self.surfaceTimeout), "Editor 歌詞框應出現",
                      file: file, line: line)
        XCTAssertTrue(app.buttons[ID.writeButton].exists, file: file, line: line)
    }

    /// 負向斷言需要一段觀察窗：條件在窗內一旦成立即失敗
    private func assertStaysFalse(
        _ condition: @autoclosure () -> Bool, for seconds: TimeInterval, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                XCTFail(message, file: file, line: line)
                return
            }
            usleep(200_000)
        }
    }

    // MARK: AC1／AC2

    /// AC1：正在播的歌有詞 → Cover Flow；把手可見
    func testPresentLyricsShowsCoverFlow() {
        start(.present)
        waitForRaisedAndSettled()
        XCTAssertTrue(element(ID.lyricsFlowHandle).exists, "把手升降兩態皆顯示")
    }

    /// AC2：缺詞 → 降下、把手可見、Editor 自動抓詞
    func testMissingLyricsShowsEditor() {
        start(.missing)
        XCTAssertTrue(element(ID.editorLayer).waitForExistence(timeout: Self.surfaceTimeout), "缺詞＝Editor")
        waitForLoweredAndUsable()
        XCTAssertTrue(element(ID.lyricsFlowHandle).exists)
        XCTAssertTrue(element(ID.fetchCount).waitForExistence(timeout: 5))
        let fetched = NSPredicate(format: "value == %@", "1")
        let expectation = XCTNSPredicateExpectation(predicate: fetched, object: element(ID.fetchCount))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "缺詞曲自動抓詞一次（B-05）")
    }

    // MARK: AC3

    /// AC3：點「正中且正在播」的那張 → Editor
    func testClickingPlayingCardOpensEditor() {
        start(.present)
        let card = app.buttons[ID.playingCard]
        XCTAssertTrue(waitUntilHittable(card, timeout: Self.surfaceTimeout), "正中播放卡是按鈕")
        card.click()
        XCTAssertTrue(element(ID.editorLayer).waitForExistence(timeout: Self.surfaceTimeout))
        waitForLoweredAndUsable()
    }

    /// AC3：其他卡不是按鈕；點了畫面不變、不抓詞
    func testClickingOtherCardsDoesNothing() {
        start(.present)
        waitForRaisedAndSettled()
        let cardButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", ID.cardPrefix))
        XCTAssertEqual(cardButtons.count, 0, "非播放中的卡不得是按鈕")

        // 點最左那張播過的歌（履歴第 0 首）：AX 子元素的次序不是牌組次序，取第 0 個可能落在視窗邊緣
        let neighbour = element(ID.cardPrefix + "h:" + Scenario.persistentID(at: 0) + "#0")
        XCTAssertTrue(neighbour.waitForExistence(timeout: 5), "牌組應有鄰張（假 Queue.dat／History.dat）")
        neighbour.click()
        assertStaysFalse(element(ID.editorLayer).exists, for: 2, "點非播放卡不得進 Editor")
        XCTAssertEqual(fetchCount() ?? "0", "0")
        XCTAssertEqual(hydrateCount() ?? "0", "0", "點非播放卡不得觸發重讀")
    }

    /// AC3：播放中但**不在正中**的卡也不可點（方向鍵把中心移走後）
    func testPlayingCardAwayFromTheCentreIsNotClickable() {
        start(.present)
        waitForRaisedAndSettled()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.buttons[ID.playingCard].waitForNonExistence(timeout: 5), "播放卡離開正中後不再是按鈕")

        let playing = element(ID.cardPrefix + "q:0:" + String(Scenario.itemID(at: Scenario.playingIndex)))
        XCTAssertTrue(playing.waitForExistence(timeout: 5))
        XCTAssertNotEqual(playing.elementType, .button)
        playing.click()
        assertStaysFalse(element(ID.editorLayer).exists, for: 2, "播放中但不在正中的卡不得進 Editor")
        XCTAssertEqual(hydrateCount() ?? "0", "0")
    }

    // MARK: AC4

    /// AC4：寫入成功 → 彩帶撒完後升回
    func testWritingLyricsRaisesCoverFlow() {
        start(.missing)
        let lyrics = element(ID.lyricsText)
        XCTAssertTrue(waitUntilHittable(lyrics, timeout: Self.surfaceTimeout))
        lyrics.click()
        lyrics.typeText("found the words")
        let write = app.buttons[ID.writeButton]
        XCTAssertTrue(waitUntilHittable(write))
        write.click()

        waitForRaisedAndSettled(timeout: Self.riseTimeout)
    }

    // MARK: AC5

    /// AC5：標記「沒有歌詞」→ 升回；重啟後同曲不跳 Editor、不自動抓詞
    func testMarkingNoLyricsPersistsAcrossRelaunch() {
        start(.missing, resetDefaults: true)
        let mark = app.buttons[ID.markNoLyrics]
        XCTAssertTrue(waitUntilHittable(mark, timeout: Self.surfaceTimeout))
        mark.click()
        waitForRaisedAndSettled()

        app.terminate()
        _ = app.wait(for: .notRunning, timeout: Self.terminationTimeout)
        start(.missing, resetDefaults: false)

        waitForRaisedAndSettled()
        assertStaysFalse((fetchCount() ?? "0") != "0", for: 2, "標記過的曲不自動抓詞")
    }

    // MARK: AC14

    /// AC14：升起時方向鍵步進 Cover Flow、打字不進被遮住的 Editor；降下時 Cover Flow 不持有焦點
    func testKeyboardFocusFollowsSurface() {
        start(.present)
        waitForRaisedAndSettled()
        let label = element(ID.centerLabel)
        XCTAssertTrue(label.waitForExistence(timeout: Self.surfaceTimeout))
        let before = label.value as? String
        app.typeKey(.rightArrow, modifierFlags: [])
        let moved = NSPredicate(format: "value != %@", before ?? "")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: moved, object: label)], timeout: 5),
            .completed, "升起時方向鍵步進 Cover Flow"
        )
        // 按鍵只送進被測 app：升起時 Editor 不掛載（D2），打字無處可去、也不得讓它出現
        app.typeKey("a", modifierFlags: [])
        XCTAssertFalse(element(ID.editorLayer).exists, "打字不得讓 Editor 出現或收到文字")

        app.buttons[ID.lyricsFlowHandle].click()
        XCTAssertTrue(element(ID.editorLayer).waitForExistence(timeout: Self.surfaceTimeout))
        let centred = label.value as? String
        app.typeKey(.rightArrow, modifierFlags: [])
        assertStaysFalse((label.value as? String) != centred, for: 1, "降下時 Cover Flow 不持有焦點")
    }
}
