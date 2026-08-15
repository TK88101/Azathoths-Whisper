import XCTest

// Batch 面板的 UI 驗收（ACCEPTANCE C-07／C-15／C-21／C-25）。
// 紀律見 AppUITestCase：不模擬全域按鍵、以 PID 定界收尾、語言僅注入該次啟動。
// 這些用例不依賴 Music 內容——切入 Batch 後即使列表為空，外殼元素（表頭／狀態欄／
// 三按鈕／預覽框）仍在，正是要驗的對象。
final class BatchUITests: AppUITestCase {
    /// 啟動 → 等主 UI → 切到 Batch 分頁
    private func launchToBatch(
        language: String? = nil,
        batchTabLabel: String = "BATCH",
        editorLabel: String = "EDITOR",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        launch(language: language)
        waitForMainUI(editorLabel, file: file, line: line)

        let batchTab = app.buttons[batchTabLabel]
        XCTAssertTrue(batchTab.exists, "導航應有 Batch 分頁", file: file, line: line)
        batchTab.click()
    }

    /// SwiftUI 的 Text 在 macOS AX 樹裡把文字放在 **value**，label 為空（2026-08-14 實測），
    /// 故兩者都比對；大小寫不敏感（`.textCase(.uppercase)` 未必反映到 AX 屬性）
    /// 限定在 staticTexts：用 descendants(.any) 掃全樹在載入 12 首曲目後會讓 UI query 超時
    /// （實測 111s 仍未回應，2026-08-14）
    private func containsText(_ text: String) -> Bool {
        app.staticTexts
            .matching(NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", text, text))
            .firstMatch
            .exists
    }

    // MARK: - C-21／C-25

    /// C-21：表頭走 i18n；C-25：Batch 狀態欄為硬編碼 "Ready"
    func testBatchShellInEnglish() {
        launchToBatch()

        XCTAssertTrue(app.staticTexts["ARTIST"].waitForExistence(timeout: 10), "C-21 col_artist")
        XCTAssertTrue(app.staticTexts["TITLE"].exists, "C-21 col_title")
        XCTAssertTrue(app.staticTexts["STAT"].exists, "C-21 col_stat")
        XCTAssertTrue(app.staticTexts["PREVIEW"].exists, "C-21 col_preview")
        XCTAssertTrue(app.staticTexts["#"].exists, "C-21：# 欄為硬編碼符號")
        XCTAssertTrue(app.staticTexts["READY"].exists, "C-25 Batch 狀態欄初始值")

        // 標題列為硬編碼英文（py:210 無 data-i18n）
        XCTAssertTrue(containsText("BATCH PROCESSING"), "header 標題")
    }

    /// C-21＋C-25 的關鍵對照：日文下表頭走 ja，但狀態欄仍是英文 "READY"。
    /// 對照組＝Editor footer 的 status_ready 在 ja 為「準備完了」——兩者刻意不同（py:241 vs py:196）
    func testBatchColumnsLocalizeButStatusStaysEnglishInJapanese() {
        launchToBatch(language: "ja", batchTabLabel: "一括処理", editorLabel: "エディタ")

        XCTAssertTrue(app.staticTexts["アーティスト"].waitForExistence(timeout: 10), "C-21 ja col_artist")
        XCTAssertTrue(app.staticTexts["タイトル"].exists, "C-21 ja col_title")
        XCTAssertTrue(app.staticTexts["状態"].exists, "C-21 ja col_stat")
        XCTAssertTrue(app.staticTexts["プレビュー"].exists, "C-21 ja col_preview")

        XCTAssertTrue(app.staticTexts["READY"].exists, "C-25：Batch 狀態欄不隨語言變")
        XCTAssertFalse(containsText("準備完了"), "C-25：不得誤用 status_ready 的 ja 值")
    }

    /// C-21：繁中表頭
    func testBatchColumnsLocalizeInTraditionalChinese() {
        launchToBatch(language: "zh-Hant", batchTabLabel: "批量處理", editorLabel: "編輯器")

        XCTAssertTrue(app.staticTexts["藝術家"].waitForExistence(timeout: 10), "C-21 zh-Hant col_artist")
        XCTAssertTrue(app.staticTexts["標題"].exists, "C-21 zh-Hant col_title")
        XCTAssertTrue(app.staticTexts["狀態"].exists, "C-21 zh-Hant col_stat")
        XCTAssertTrue(app.staticTexts["預覽"].exists, "C-21 zh-Hant col_preview")
        XCTAssertTrue(app.staticTexts["READY"].exists, "C-25：繁中下同樣維持英文")
    }

    // MARK: - C-07

    /// C-07：預覽面板唯讀（py:236 textarea readonly）——鍵入不得改變內容
    func testPreviewPaneIsReadOnly() {
        launchToBatch()

        let preview = app.textViews["batch-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "預覽框應存在")

        let before = preview.value as? String ?? ""
        // PlainTextEditor 回傳的是 NSScrollView 容器，本身沒有 hit point——以歸一化座標點入取得焦點
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeText("SHOULD NOT BE TYPED")

        let after = preview.value as? String ?? ""
        XCTAssertEqual(before, after, "C-07：唯讀面板不得接受鍵入")
        XCTAssertFalse(containsText("SHOULD NOT BE TYPED"), "鍵入內容不得出現在畫面上")
    }

    // MARK: - C-15

    /// C-15：Import All 前先出確認框，文案與原版 confirm() 逐字相同（py:715）
    func testImportAllShowsConfirmationWithExactWording() {
        launchToBatch()

        // 用 identifier 定位：按鈕的 accessibility label 會混入 MaterialSymbol 連字文本且隨語言變動
        let importAll = app.buttons["batch-import-all"]
        XCTAssertTrue(importAll.waitForExistence(timeout: 10), "footer 應有 Import All 按鈕")
        importAll.click()

        // 確認框在 macOS 上呈現為 sheet（label 'alert'），文案落在 StaticText 的 value
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "C-15：Import All 前應先出確認框")

        let wording = "Writes lyrics for ALL tracks in list where lyrics are present. Continue?"
        XCTAssertTrue(
            sheet.staticTexts
                .matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", wording, wording))
                .firstMatch
                .waitForExistence(timeout: 5),
            "C-15：確認框文案須與原版逐字相同"
        )

        // 取消後不得有任何寫入動作發生（狀態欄維持初始值）
        // 限定在 sheet 內：畫面上不只一個 label 為 Cancel 的元素
        let cancel = sheet.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "確認框應有 Cancel")
        cancel.click()

        XCTAssertTrue(app.staticTexts["READY"].waitForExistence(timeout: 5), "取消後狀態欄不變")
    }
}
