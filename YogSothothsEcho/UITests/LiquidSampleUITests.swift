import XCTest

#if DEBUG

/// CR-038 L-T3（yse-liquid-vinyl-sample.md v0.4）：Debug 小樣——預覽畫布開關與四態、live 模式不改唱片的無障礙標籤與動作
final class LiquidSampleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument])
        let open = app.buttons[AccessibilityID.nowPlayingOpenTurntable]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 10))
    }

    private var record: XCUIElement { app.descendants(matching: .any)[AccessibilityID.turntableRecord] }

    /// 最右側中間＝唱機以外的空白：叫出浮層（同 TurntableUITests）
    private func showOverlay(until element: XCUIElement) {
        for _ in 0..<5 where !element.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.5)).tap()
            _ = element.waitForExistence(timeout: 1.5)
        }
        XCTAssertTrue(element.exists)
    }

    func testPreviewCanvasOpensSwitchesPhasesAndCloses() {
        let button = app.buttons[AccessibilityID.liquidPreviewButton]
        showOverlay(until: button)
        button.tap()
        let canvas = app.descendants(matching: .any)[AccessibilityID.liquidPreviewCanvas]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // 預覽唱片不是播放鈕：沒有 Play／Pause 標籤、不是 button
        let previewRecord = app.descendants(matching: .any)[AccessibilityID.liquidPreviewRecord]
        XCTAssertTrue(previewRecord.waitForExistence(timeout: 5))
        XCTAssertEqual(previewRecord.label, "Liquid sample record")
        XCTAssertFalse(app.buttons[AccessibilityID.liquidPreviewRecord].exists)
        for phase in ["still", "slow", "normal", "justStopped"] {
            let phaseButton = app.buttons[AccessibilityID.liquidPreviewPhase(phase)]
            XCTAssertTrue(phaseButton.waitForExistence(timeout: 3), phase)
            phaseButton.tap()
        }
        app.buttons[AccessibilityID.liquidPreviewAuto].tap()
        app.buttons[AccessibilityID.liquidPreviewClose].tap()
        XCTAssertTrue(waitFor("exists == false", on: canvas))
        XCTAssertTrue(record.exists)
    }

    /// live：唱片換成液態層，但仍是同一顆播放／暫停鈕（標籤跟真實狀態、點了照樣切換）
    func testLiveModeKeepsRecordAccessibilityAndAction() {
        let live = app.switches[AccessibilityID.liquidLiveToggle]
        showOverlay(until: live)
        live.switches.firstMatch.tap()
        XCTAssertTrue(waitFor("value == %@", ["1"], on: live))
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: record))
        record.tap()
        XCTAssertTrue(waitFor("label == %@", ["Play"], on: record))
        record.tap()
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: record))
    }
}

extension LiquidSampleUITests {
    /// L-T4：live 量測在模擬器跑一輪（暖機 5 s＋30 s），浮層顯示 120／60 判定、寫出量測 JSON。量測鈕在開發者工具開關後
    func testLiveMeasurementProducesResult() {
        app.terminate()
        app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument, AccessibilityID.developerToolsArgument, "YES"])
        let open = app.buttons[AccessibilityID.nowPlayingOpenTurntable]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        let live = app.switches[AccessibilityID.liquidLiveToggle]
        showOverlay(until: live)
        live.switches.firstMatch.tap()
        let measure = app.buttons["measure live 5+30 s"]
        showOverlay(until: measure)
        measure.tap()
        let result = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "liquidLive:")).firstMatch
        // 量測期間浮層可能自動隱藏：時間到後再叫出浮層讀結果
        Thread.sleep(forTimeInterval: 37)
        showOverlay(until: result)
        XCTAssertTrue(result.label.contains("120"), result.label)
    }
}
#endif
