import XCTest

// C-20 的真機驗收：隱藏視窗不中斷 Batch 任務（Plan §4.10，對齊原版隱藏語義）。
//
// 這個用例**依賴真實環境**：Music 需正在播放/暫停於一張含缺詞曲目的專輯，且需要網路
// （會對缺詞曲目逐條發真實的 Genius→DarkLyrics 請求）。因此不列入預設測試集，
// 手動觸發：
//   xcodebuild test -only-testing:AzathothsWhisperUITests/BatchLiveUITests …
//
// 安全性：Fetch Missing 只更新記憶體中的列表，**不寫入 Music 資料庫**——
// 寫入只發生在 Import Selected／Import All 路徑，本用例不觸碰那兩個按鈕。
final class BatchLiveUITests: AppUITestCase {
    /// 讀 Batch footer 的狀態文案（經 .textCase(.uppercase) 後為大寫）
    private func batchStatus() -> String {
        let matches = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@ OR value BEGINSWITH %@ OR value == %@",
                        "FETCHING (", "FETCH COMPLETE", "READY")
        )
        return matches.firstMatch.exists ? (matches.firstMatch.value as? String ?? "") : ""
    }

    /// C-20：抓詞進行中隱藏視窗 → 任務不中斷（證據＝隱藏後仍持續產生的進度日誌）
    func testHiddenWindowDoesNotInterruptBatchFetch() throws {
        // 預設跳過：本用例需 Music 正在播放/暫停於含缺詞曲目的專輯，且會發真實網路請求。
        // 手動觸發：AZW_MUSIC_TESTS=1 xcodebuild test -only-testing:…/BatchLiveUITests
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AZW_MUSIC_TESTS"] == "1",
            "C-20 真機驗收需設 AZW_MUSIC_TESTS=1（依賴真實 Music 資料與網路）"
        )

        // 基類的 launch 已帶 -ApplePersistenceIgnoreState：本用例會以紅鈕隱藏視窗後結束，
        // macOS 的 saved state 會記住「視窗已關閉」，使下次啟動恢復成無視窗狀態
        // （實測：第二次跑等 45s 也等不到主 UI）
        launch()
        waitForMainUI()
        navButton("batch").click()

        // 依賴真實 Music 資料：需有當前專輯且含缺詞曲目
        XCTAssertTrue(
            app.staticTexts["01"].waitForExistence(timeout: 30),
            "需 Music 正在播放/暫停於一張專輯才能跑此用例"
        )

        let fetch = app.buttons["batch-fetch-missing"]
        XCTAssertTrue(fetch.waitForExistence(timeout: 10), "footer 應有 Fetch Missing")
        fetch.click()

        // 等第一條進度出現（若專輯無缺詞會改彈 alert，該情形不適用此用例）
        let progressDeadline = Date().addingTimeInterval(60)
        var firstSeen = ""
        while firstSeen.isEmpty, Date() < progressDeadline {
            let s = batchStatus()
            if s.hasPrefix("FETCHING (") { firstSeen = s }
            usleep(300_000)
        }
        XCTAssertFalse(firstSeen.isEmpty, "應開始逐條抓詞（需專輯含缺詞曲目）")

        // 紅鈕隱藏視窗——原版語義是隱藏而非退出（A-08），任務應繼續
        let window = app.windows.firstMatch
        window.buttons[XCUIIdentifierCloseWindow].click()

        waitForWindowToHide(window)
        XCTAssertFalse(window.exists, "紅鈕應隱藏視窗")
        XCTAssertNotEqual(app.state, .notRunning, "隱藏不得終止 app")

        // 讓任務在無視窗狀態下持續跑。
        // 不在此處 reopen 讀 UI：視窗重顯走 'rapp' Apple Event，而測試 runner 送 AE 會被
        // TCC 擋下（產品本身正常——獨立實測：1 視窗 → 紅鈕 → 0 視窗 → reopen → 1 視窗）。
        // 改由 `BatchViewModel` 的進度日誌提供證據，見 Scripts/c20_acceptance 說明。
        Thread.sleep(forTimeInterval: 35)

        XCTAssertNotEqual(app.state, .notRunning, "隱藏期間 app 必須存活")
        print("C-20 EVIDENCE: hidden_at_progress=[\(firstSeen)] (對照日誌中隨後的 fetch progress 條目)")
    }
}
