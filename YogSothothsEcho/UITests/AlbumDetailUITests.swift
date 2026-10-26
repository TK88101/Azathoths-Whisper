import XCTest

// S6 T11（sprint-6-detail.md §5 T11、§4.5–4.8、CR-020）：以 DEBUG 合成曲庫與播放器（名稱自編）走側封→詳情→播放列→唱機。不截圖。
// XCUITest 不反映 SwiftUI accessibilityHidden（T9 實測），「唱機出現時曲庫與播放列不在 AX 樹」以「點了不生效」驗，AX 樹本身由 #6-1 VoiceOver 實機驗
final class AlbumDetailUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument] + extra)
    }

    private func row(_ app: XCUIApplication, _ number: Int) -> XCUIElement { app.buttons[AccessibilityID.albumTracksRow(number)] }
    private func back(_ app: XCUIApplication) -> XCUIElement { app.buttons[AccessibilityID.albumTracksClose] }
    private func title(_ app: XCUIApplication) -> XCUIElement { app.staticTexts[AccessibilityID.nowPlayingTitle] }
    private func record(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[AccessibilityID.turntableRecord] }

    /// 控制列顯示 5 秒後自動隱藏（TurntableOverlayState.autoHide）：「確認存在→點」之間可能剛好隱藏而點空。
    /// 改為記下位置後以座標點，點空（控制列已隱藏）就重新叫出再點，直到唱機真的關掉；驗證內容不變（關閉鈕能關唱機）
    private func closeTurntable(_ app: XCUIApplication) {
        let close = app.buttons[AccessibilityID.turntableClose]
        for _ in 0..<5 {
            if !close.exists {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.5)).tap()
                guard close.waitForExistence(timeout: 1.5) else { continue }
            }
            let frame = close.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            if waitFor("exists == false", on: record(app), timeout: 2) { return }
        }
        XCTFail("關閉鈕點了 5 次唱機仍在")
    }

    /// 詳情開著：播放列的暫停、下一首、拖進度條都照常、詳情不關（CR-020）；點曲目＝點歌且留在詳情；目前曲推來時列標示與播放列同時更新
    func testBarWorksWhileDetailStaysOpen() {
        let app = launch()
        app.openFirstAlbum()
        let toggle = app.buttons[AccessibilityID.nowPlayingToggle]
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: toggle))
        toggle.tap()
        XCTAssertTrue(waitFor("label == %@", ["Play"], on: toggle))
        XCTAssertTrue(row(app, 3).exists && back(app).exists)

        app.buttons[AccessibilityID.nowPlayingNext].tap()
        XCTAssertTrue(waitFor("label == %@", ["Synthetic Song 02"], on: title(app)))
        XCTAssertTrue(row(app, 3).exists && back(app).exists)
        // 目前曲換了：詳情裡「正在播放」標在第 2 列
        XCTAssertTrue(row(app, 2).images["Now playing"].waitForExistence(timeout: 5))

        row(app, 4).tap()
        XCTAssertTrue(waitFor("label == %@", ["Synthetic Song 04"], on: title(app)))
        XCTAssertTrue(back(app).exists && row(app, 1).exists)
    }

    /// 詳情 → 播放列唱機鈕 → 唱機；關唱機回到詳情；返回鍵回側封
    func testTurntableFromDetailReturnsToDetail() {
        let app = launch()
        app.openFirstAlbum()
        app.buttons[AccessibilityID.nowPlayingOpenTurntable].tap()
        XCTAssertTrue(record(app).waitForExistence(timeout: 10))
        // 唱機蓋住期間：點播放列原位置不生效（曲庫殼層不可點）
        let toggle = app.buttons[AccessibilityID.nowPlayingToggle]
        let before = toggle.label
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        XCTAssertEqual(toggle.label, before)
        closeTurntable(app)
        XCTAssertTrue(waitFor("exists == false", on: record(app), timeout: 5))
        XCTAssertTrue(row(app, 3).waitForExistence(timeout: 5) && back(app).isHittable)
        XCTAssertLessThan(back(app).frame.width, 100)   // 返回鍵的框只有自己，不是整個詳情區
        back(app).tap()
        XCTAssertTrue(waitFor("exists == false", on: back(app), timeout: 5))
        XCTAssertTrue(app.buttons[AccessibilityID.libraryAlbum("0000000000000001")].waitForExistence(timeout: 5))
    }

    /// 從側封直接開唱機、關閉回側封；進場中關閉、滑完後再開一次也正常
    func testTurntableFromBrowseAndQuickReopen() {
        let app = launch()
        let open = app.buttons[AccessibilityID.nowPlayingOpenTurntable]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(record(app).waitForExistence(timeout: 10))
        closeTurntable(app)
        XCTAssertTrue(waitFor("exists == false", on: record(app), timeout: 5))
        XCTAssertTrue(app.buttons[AccessibilityID.libraryAlbum("0000000000000001")].exists)
        open.tap()
        XCTAssertTrue(record(app).waitForExistence(timeout: 10))
        closeTurntable(app)
        XCTAssertTrue(waitFor("exists == false", on: record(app), timeout: 5))
    }

    /// #6-1：唱機開著時回桌面（殼層暫時換成連線畫面、唱機被直接收掉）再回來：曲庫整頁回到原位、播放列可按，不停在被推開的位置
    func testBackgroundingWithTurntableOpenRestoresTheLibrary() {
        let app = launch()
        let open = app.buttons[AccessibilityID.nowPlayingOpenTurntable]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(record(app).waitForExistence(timeout: 10))
        sleep(1)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let album = app.buttons[AccessibilityID.libraryAlbum("0000000000000001")]
        XCTAssertTrue(album.waitForExistence(timeout: 20))
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor("hittable == true", on: open, timeout: 5), "播放列的唱機鈕應在畫面內可按")
        XCTAssertGreaterThanOrEqual(app.textFields[AccessibilityID.librarySearch].frame.minX, 0, "頂列不應被推出畫面左側")
    }

    /// 詳情開著時忘記這台 Mac（→ 殼層換成連線畫面），重新配對後回到側封、不是詳情。
    /// CR-023 後詳情開著時設定鈕隱藏，改以 DEBUG 參數在啟動 15 秒後觸發同一個 forgetMac()
    func testDisconnectWhileDetailOpenResetsToBrowse() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", AccessibilityID.fakeRemoteArgument,
                               AccessibilityID.fakePayloadArgument, AccessibilityID.forgetAfterDelayArgument]
        app.launch()
        XCTAssertTrue(app.textFields[AccessibilityID.librarySearch].waitForExistence(timeout: 20))
        app.openFirstAlbum()
        XCTAssertTrue(waitFor("exists == false", on: back(app), timeout: 20))
        XCTAssertTrue(app.textFields[AccessibilityID.librarySearch].waitForExistence(timeout: 20))
        XCTAssertFalse(back(app).exists)
        XCTAssertTrue(app.buttons[AccessibilityID.libraryAlbum("0000000000000001")].waitForExistence(timeout: 10))
    }

    /// Reduce Motion（啟動參數）：開合與進唱機改淡入淡出，流程照常
    func testReduceMotionPathWorks() {
        let app = launch([AccessibilityID.forceReduceMotionArgument])
        app.openFirstAlbum()
        back(app).tap()
        XCTAssertTrue(waitFor("exists == false", on: back(app), timeout: 5))
        app.buttons[AccessibilityID.nowPlayingOpenTurntable].tap()
        XCTAssertTrue(record(app).waitForExistence(timeout: 10))
        closeTurntable(app)
        XCTAssertTrue(waitFor("exists == false", on: record(app), timeout: 5))
    }
}
