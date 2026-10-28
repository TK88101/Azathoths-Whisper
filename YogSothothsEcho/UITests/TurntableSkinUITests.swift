import XCTest

/// CR-034 T8（yse-1.0.1-skins.md §4.6）＋增補 A（yse-1.0.1-skin-picker.md §4.4）：唱機外觀選擇器——預設 Default（classic）；
/// 從唱機浮層的圓鈕開選擇器，切到 Pioneer 立即生效、重開 App 保留；重設設定（-YSEUITestResetSettings）回到 Default。
/// 設定頁在唱機關著時也能換。每次都以重設收尾，不把選擇留給其他測試
final class TurntableSkinUITests: XCTestCase {
    private static let standard = AccessibilityID.turntableSkin("classic")
    private static let sArm = AccessibilityID.turntableSkin("s-arm-1200")
    private static let rega = AccessibilityID.turntableSkin("rega-rb330")
    private static let technics = AccessibilityID.turntableSkin("technics-sl1200g")

    override func setUp() {
        continueAfterFailure = false
    }

    private func openTurntable(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument] + (reset ? [AccessibilityID.resetSettingsArgument] : []))
        let open = app.buttons[AccessibilityID.nowPlayingOpenTurntable]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.turntableRecord].waitForExistence(timeout: 10))
        // 最右側中間＝唱機組以外的空白：叫出浮層（同 TurntableUITests）
        let close = app.buttons[AccessibilityID.turntableClose]
        for _ in 0..<5 where !close.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.5)).tap()
            _ = close.waitForExistence(timeout: 1.5)
        }
        XCTAssertTrue(close.exists)
        return app
    }

    /// 增補 A：浮層的圓鈕 → popover 選擇器（取代原本右上直接點的膠囊）
    private func openPicker(_ app: XCUIApplication) {
        let button = app.buttons[AccessibilityID.turntableSkinButton]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.buttons[Self.standard].waitForExistence(timeout: 5))
    }

    private func isSelected(_ id: String, in app: XCUIApplication) -> Bool {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        let selected = NSPredicate(format: "isSelected == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: button)], timeout: 3) == .completed
    }

    func testSwitchingSkinPersistsAndResetReturnsToStandard() {
        var app = openTurntable(reset: true)
        openPicker(app)
        XCTAssertTrue(isSelected(Self.standard, in: app), "預設＝Standard")
        app.buttons[Self.sArm].tap()
        XCTAssertTrue(isSelected(Self.sArm, in: app), "點了立即生效")
        app.terminate()

        app = openTurntable(reset: false)
        openPicker(app)
        XCTAssertTrue(isSelected(Self.sArm, in: app), "重開 App 保留")
        app.terminate()

        app = openTurntable(reset: true)
        openPicker(app)
        XCTAssertTrue(isSelected(Self.standard, in: app), "重設回 Standard")
        app.terminate()
    }

    /// 增補 A：唱機關著時從設定頁換到 Pioneer → 開唱機，浮層選擇器顯示 Pioneer 選中；四款都在選擇器上（增補 B 加 Technics）
    func testSettingsChangesTheSkinWhileTheTurntableIsClosed() {
        var app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument, AccessibilityID.resetSettingsArgument])
        let settings = app.buttons[AccessibilityID.settingsButton]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let row = app.buttons[AccessibilityID.settingsTurntableSkin]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons[Self.rega].waitForExistence(timeout: 5), "四款都在")
        XCTAssertTrue(app.buttons[Self.technics].exists, "四款都在")
        XCTAssertTrue(isSelected(Self.standard, in: app))
        app.buttons[Self.sArm].tap()
        XCTAssertTrue(isSelected(Self.sArm, in: app), "唱機關著也立即生效")
        app.terminate()

        app = openTurntable(reset: false)
        openPicker(app)
        XCTAssertTrue(isSelected(Self.sArm, in: app), "開唱機後是設定頁選的那款")
        app.terminate()

        app = openTurntable(reset: true)
        app.terminate()
    }
}
