import XCTest

// 外殼冒煙（ACCEPTANCE A-02…A-08、D-01/D-03/D-10、E-04/E-07/A-07）。
// 紀律：不模擬全域按鍵（會誤傷其他 app），一律走 XCUIApplication 的定界操作；
// 結束用 app.terminate()（PID 定界），不對 Music.app 或系統偏好做任何寫入。
// 語言以 launchArguments 的 -AppleLanguages 注入，只作用於該次啟動，不改使用者設定。
// 啟動／收尾／等主 UI 的共用紀律見 UITests/Support/AppUITestCase.swift。
// 一律走假 Music 的「沒在播」場景（計劃 Q3.5）：外殼測試不讀使用者的 Music——否則 Music 正在播
// 有詞的歌時，Editor 頁會升起 Cover Flow、遮住本組要驗的 Editor 外殼。
final class ShellUITests: AppUITestCase {
    private typealias Scenario = LyricsFlowUITestScenario
    private typealias ID = AccessibilityID

    private func launchShell(language: String? = nil) {
        launch(language: language, environment: Scenario.environment(.notPlaying, resetDefaults: true))
    }

    /// 菜單交互前先取回前台。連跑多個用例後焦點可能落在別的 app，症狀有二：
    /// `MenuBarItem is not foreground and does not allow background interaction`，
    /// 或點擊靜默落空——後者會讓 Quit 用例誤報「app 沒退出」（實測產品退出僅 0.02s）。
    private func menuBar() -> XCUIElementQuery {
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
        return app.menuBarItems
    }

    private func containsLabel(_ text: String) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
            .exists
    }

    // MARK: 外殼

    /// A-01：啟動首屏＝splash（同一視窗，稍後換成主 UI）
    func testSplashIsShownBeforeMainUI() {
        launchShell()
        let splashSubtitle = app.staticTexts["INITIALIZING CORE LOGIC"]
        XCTAssertTrue(splashSubtitle.waitForExistence(timeout: 5), "首屏應為 splash")
        attach("splash")

        waitForMainUI()
        // splash 以 0.2s 淡出；主 UI 已在 AX 樹上時它可能還在淡出途中
        XCTAssertTrue(splashSubtitle.waitForNonExistence(timeout: 2), "主 UI 出現後 splash 應消失")
        XCTAssertEqual(app.windows.count, 1, "A-02：同窗切換，不得開新視窗")
    }

    /// A-03／A-04：預設 1200×800、標題固定英文
    func testWindowGeometryAndTitle() {
        launchShell()
        waitForMainUI()

        let window = app.windows["Azathoth's Whisper"]
        XCTAssertTrue(window.exists, "A-04 視窗標題")
        XCTAssertEqual(window.frame.width, 1200, accuracy: 1)
        XCTAssertEqual(window.frame.height, 800, accuracy: 30, "含標題列高度")
    }

    func testLaunchShowsEditorShellAfterSplash() {
        launchShell()
        waitForMainUI()
        assertNavLabel(navButton("batch"), "BATCH")
        // AC10：導覽區恰好兩個按鈕（Editor｜Batch，以 identifier 判定）；Cover Flow 已改為 Editor 內的一層
        let navButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", ID.navPrefix))
        XCTAssertEqual(navButtons.count, 2, "導覽只剩 Editor 與 Batch")
        XCTAssertTrue(app.buttons[ID.navEditor].exists)
        XCTAssertTrue(app.buttons[ID.navBatch].exists)
        XCTAssertFalse(app.buttons["COVER FLOW"].exists, "Cover Flow 分頁已移除")
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
        launchShell()
        waitForMainUI()
        menuBar()["Settings"].click()
        app.menuItems["Token Settings..."].click()

        XCTAssertTrue(app.staticTexts["TOKEN SETTINGS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GENIUS ACCESS TOKEN:"].exists)
        // 刻意不截圖：此 modal 會從 Keychain 預填真實 token，截圖會把明文寫進
        // xcresult 附件（證據包會被分享）。全局 CLAUDE.md §7：輸出分享前查敏感資料。
    }

    /// D-01a：token 欄必須是遮蔽的（`SecureField`），不得是明文 `TextField`。
    ///
    /// 為何需要**這一條**：D-01a 的改動目的是遮蔽，而遮蔽在此之前**零回歸保護**——
    /// `SettingsViewModelTests` 驅動的是 ViewModel，全倉沒有任何測試實例化過 SwiftUI view，
    /// 把 `SecureField` 改回 `TextField` 那些測試照樣全綠（M8 對抗驗證實測結論）。
    /// 本條只斷言**控件型別**、不讀取任何值，因此不會把憑證帶進證據包。
    /// 它同時把「SecureField 在 macOS AX 樹上確實註冊為 secureTextField」
    /// 這個改動賴以成立的前提，從代碼註釋裡的斷言變成可證偽的測試。
    func testTokenFieldIsMasked() {
        launchShell()
        waitForMainUI()
        menuBar()["Settings"].click()
        app.menuItems["Token Settings..."].click()
        XCTAssertTrue(app.staticTexts["TOKEN SETTINGS"].waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.secureTextFields.firstMatch.waitForExistence(timeout: 5),
            "D-01a：token 欄必須是 SecureField"
        )
        XCTAssertEqual(app.textFields.count, 0, "D-01a：modal 內不得有明文 TextField")
    }

    /// A-05：語言設定組（兩組互斥）
    func testSettingsMenuOpensLanguageModal() {
        launchShell()
        waitForMainUI()
        menuBar()["Settings"].click()
        app.menuItems["Language Settings..."].click()

        XCTAssertTrue(app.staticTexts["LANGUAGE SETTINGS"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["GENIUS ACCESS TOKEN:"].exists, "D-02：兩組互斥")
        attach("settings-language")
    }

    /// A-06／D-10：Help ▸ About 開 modal，含作者與兩個連結
    func testHelpMenuOpensAboutModal() {
        launchShell()
        waitForMainUI()
        menuBar()["Help"].click()
        app.menuItems["About"].click()

        XCTAssertTrue(app.staticTexts["iBridge Zhao"].waitForExistence(timeout: 5))
        // D-10：版本行＝「Version 2.0.1 (Build <建置號>)」；不寫死建置號，打包 +1 時免改測試
        // SwiftUI 的 Text 在 macOS AX 樹上把文字放在 value、label 為空（見 AppUITestCase.staticText(containing:)），兩者都比
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(
                format: "(value BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@) AND (value CONTAINS[c] %@ OR label CONTAINS[c] %@)",
                "Version 2.0.1", "Version 2.0.1", "(Build ", "(Build "
            )).firstMatch.exists,
            "D-10：版本行應含建置號"
        )
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
        launchShell()
        waitForMainUI()
        let window = app.windows.firstMatch
        window.buttons[XCUIIdentifierCloseWindow].click()

        waitForWindowToHide(window)
        XCTAssertFalse(window.exists, "紅鈕應隱藏視窗")
        XCTAssertNotEqual(app.state, .notRunning, "app 不得因關窗而退出")
    }

    /// A-10：Cmd+Q 真退出（走 app 自己的菜單項，不模擬全域按鍵）
    func testQuitMenuItemTerminatesApp() {
        launchShell()
        waitForMainUI()
        menuBar().element(boundBy: 1).click()      // 應用程式菜單

        // 連跑多個用例時，展開選單到點擊之間仍可能被別的 app 搶走前台，
        // 導致點擊靜默落空、誤報「app 沒退出」（實測產品退出僅 0.02s）。
        // 故點擊前再確認一次：選單項確實在 AX 樹上，且 app 仍在前台。
        let quit = app.menuItems["Quit Azathoth's Whisper"]
        XCTAssertTrue(quit.waitForExistence(timeout: 5), "應用程式選單應展開並含 Quit")
        XCTAssertEqual(app.state, .runningForeground, "點 Quit 前 app 必須在前台")
        quit.click()

        let deadline = Date().addingTimeInterval(10)
        while app.state != .notRunning, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertEqual(app.state, .notRunning, "Cmd+Q／Quit 必須真的終止行程")
    }

    // MARK: i18n 冷啟動（E-07 四態中的兩態；system／en 由使用者機器預設涵蓋）

    /// E-04／E-07／A-07：日文冷啟動——UI 走 ja，菜單維持英文
    func testColdStartInJapaneseLocalizesUIButNotMenus() {
        launchShell(language: "ja")
        waitForMainUI("エディタ")

        assertNavLabel(navButton("batch"), "一括処理")
        XCTAssertTrue(containsLabel("カバーフロー"), "E-10：nav_coverflow 保留作把手標題（D12）")
        XCTAssertTrue(app.staticTexts["ステータス:"].exists)
        XCTAssertTrue(menuBar()["Settings"].exists, "A-07 菜單硬編碼英文")
        XCTAssertTrue(menuBar()["Help"].exists)
        attach("editor-ja")
    }

    /// E-04／E-07：繁中冷啟動
    func testColdStartInTraditionalChinese() {
        launchShell(language: "zh-Hant")
        waitForMainUI("編輯器")

        assertNavLabel(navButton("batch"), "批量處理")
        XCTAssertTrue(containsLabel("封面瀏覽"), "E-10：nav_coverflow 保留作把手標題（D12）")
        XCTAssertTrue(app.staticTexts["狀態:"].exists)
        XCTAssertTrue(menuBar()["Settings"].exists)
        attach("editor-zh-Hant")
    }
}
