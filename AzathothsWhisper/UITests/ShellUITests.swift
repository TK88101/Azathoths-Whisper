import XCTest

// 外殼冒煙（ACCEPTANCE A-02…A-08、D-01/D-03/D-10、E-04/E-07/A-07）。
// 紀律：不模擬全域按鍵（會誤傷其他 app），一律走 XCUIApplication 的定界操作；
// 結束用 app.terminate()（PID 定界），不對 Music.app 或系統偏好做任何寫入。
// 語言以 launchArguments 的 -AppleLanguages 注入，只作用於該次啟動，不改使用者設定。
final class ShellUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
    }

    @discardableResult
    private func launch(language: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }
        app.launch()
        self.app = app
        return app
    }

    /// splash 3.5 秒後在同一視窗切主 UI（A-02）
    private func waitForMainUI(_ editorLabel: String = "EDITOR", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.buttons[editorLabel].waitForExistence(timeout: 15),
            "splash 後應出現主 UI 導航",
            file: file, line: line
        )
    }

    private func containsLabel(_ text: String) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
            .exists
    }

    private func attach(_ name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["AZW_UI_SHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    // MARK: 外殼

    /// A-01：啟動首屏＝splash（同一視窗，稍後換成主 UI）
    func testSplashIsShownBeforeMainUI() {
        launch()
        let splashSubtitle = app.staticTexts["INITIALIZING CORE LOGIC"]
        XCTAssertTrue(splashSubtitle.waitForExistence(timeout: 5), "首屏應為 splash")
        attach("splash")

        waitForMainUI()
        XCTAssertFalse(splashSubtitle.exists, "主 UI 出現後 splash 應消失")
        XCTAssertEqual(app.windows.count, 1, "A-02：同窗切換，不得開新視窗")
    }

    /// A-03／A-04：預設 1200×800、標題固定英文
    func testWindowGeometryAndTitle() {
        launch()
        waitForMainUI()

        let window = app.windows["Azathoth's Whisper"]
        XCTAssertTrue(window.exists, "A-04 視窗標題")
        XCTAssertEqual(window.frame.width, 1200, accuracy: 1)
        XCTAssertEqual(window.frame.height, 800, accuracy: 30, "含標題列高度")
    }

    func testLaunchShowsEditorShellAfterSplash() {
        launch()
        waitForMainUI()
        XCTAssertTrue(app.buttons["BATCH"].exists)
        XCTAssertTrue(app.buttons["COVER FLOW"].exists)
        XCTAssertTrue(app.staticTexts["NOW EDITING"].exists)
        XCTAssertTrue(app.staticTexts["STATUS:"].exists)
        XCTAssertTrue(app.staticTexts["LINES:"].exists)
        XCTAssertTrue(app.staticTexts["MEM: 64MB"].exists)      // B-18 假指標
        XCTAssertTrue(app.staticTexts["LAT: 12MS"].exists)
        XCTAssertTrue(app.staticTexts["TXT_MODE: UTF-8"].exists) // B-17
        attach("editor")
    }

    // MARK: 菜單與 modal

    /// A-05／D-01／D-03：菜單開 token modal，標題為英文覆寫
    func testSettingsMenuOpensTokenModal() {
        launch()
        waitForMainUI()
        app.menuBarItems["Settings"].click()
        app.menuItems["Token Settings..."].click()

        XCTAssertTrue(app.staticTexts["TOKEN SETTINGS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GENIUS ACCESS TOKEN:"].exists)
        // 刻意不截圖：此 modal 會從 Keychain 預填真實 token，截圖會把明文寫進
        // xcresult 附件（證據包會被分享）。全局 CLAUDE.md §7：輸出分享前查敏感資料。
    }

    /// A-05：語言設定組（兩組互斥）
    func testSettingsMenuOpensLanguageModal() {
        launch()
        waitForMainUI()
        app.menuBarItems["Settings"].click()
        app.menuItems["Language Settings..."].click()

        XCTAssertTrue(app.staticTexts["LANGUAGE SETTINGS"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["GENIUS ACCESS TOKEN:"].exists, "D-02：兩組互斥")
        attach("settings-language")
    }

    /// A-06／D-10：Help ▸ About 開 modal，含作者與兩個連結
    func testHelpMenuOpensAboutModal() {
        launch()
        waitForMainUI()
        app.menuBarItems["Help"].click()
        app.menuItems["About"].click()

        XCTAssertTrue(app.staticTexts["iBridge Zhao"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["VERSION 2.0.0"].exists)
        // 兩個連結是可點的 Button，文字併入其 accessibility label
        XCTAssertTrue(containsLabel("toadeater731@gmail.com"), "缺 mailto 連結")
        XCTAssertTrue(containsLabel("TK88101/Azathoths-Whisper"), "缺 GitHub 連結")
        attach("about")

        app.buttons["CLOSE"].click()
        XCTAssertFalse(app.staticTexts["iBridge Zhao"].waitForExistence(timeout: 2))
    }

    // MARK: 退出矩陣

    /// A-08：紅色關閉鈕＝隱藏視窗，app 不退出
    func testRedCloseButtonHidesWindowWithoutTerminating() {
        launch()
        waitForMainUI()
        let window = app.windows.firstMatch
        window.buttons[XCUIIdentifierCloseWindow].click()

        let deadline = Date().addingTimeInterval(5)
        while window.exists, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertFalse(window.exists, "紅鈕應隱藏視窗")
        XCTAssertNotEqual(app.state, .notRunning, "app 不得因關窗而退出")
    }

    /// A-10：Cmd+Q 真退出（走 app 自己的菜單項，不模擬全域按鍵）
    func testQuitMenuItemTerminatesApp() {
        launch()
        waitForMainUI()
        app.menuBarItems.element(boundBy: 1).click()      // 應用程式菜單
        app.menuItems["Quit Azathoth's Whisper"].click()

        let deadline = Date().addingTimeInterval(10)
        while app.state != .notRunning, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertEqual(app.state, .notRunning, "Cmd+Q／Quit 必須真的終止行程")
    }

    // MARK: i18n 冷啟動（E-07 四態中的兩態；system／en 由使用者機器預設涵蓋）

    /// E-04／E-07／A-07：日文冷啟動——UI 走 ja，菜單維持英文
    func testColdStartInJapaneseLocalizesUIButNotMenus() {
        launch(language: "ja")
        waitForMainUI("エディタ")

        XCTAssertTrue(app.buttons["一括処理"].exists)
        XCTAssertTrue(app.buttons["カバーフロー"].exists, "E-10 新鍵")
        XCTAssertTrue(app.staticTexts["ステータス:"].exists)
        XCTAssertTrue(app.menuBarItems["Settings"].exists, "A-07 菜單硬編碼英文")
        XCTAssertTrue(app.menuBarItems["Help"].exists)
        attach("editor-ja")
    }

    /// E-04／E-07：繁中冷啟動
    func testColdStartInTraditionalChinese() {
        launch(language: "zh-Hant")
        waitForMainUI("編輯器")

        XCTAssertTrue(app.buttons["批量處理"].exists)
        XCTAssertTrue(app.buttons["封面瀏覽"].exists)
        XCTAssertTrue(app.staticTexts["狀態:"].exists)
        XCTAssertTrue(app.menuBarItems["Settings"].exists)
        attach("editor-zh-Hant")
    }
}
