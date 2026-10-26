import XCTest

// S4 T11（sprint-4-detail.md §4.9 的 X 層）：抽 #2、#3、#7、#10——畫面真的出現文案，恢復或按下後消失。合成資料，不截圖
final class RemoteFailureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func notice(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func openFirstAlbumAndPlay(_ app: XCUIApplication, row: Int) {
        app.openFirstAlbum(waitingFor: row)
        app.buttons[AccessibilityID.albumTracksRow(row)].tap()
    }

    /// #2 Mac 未允許控制 Music：說明出現、控制鈕不可按；權限恢復（合成資料數秒後推 ok）→ 說明消失、可按
    func testAutomationDeniedShowsExplanationUntilAllowed() {
        let app = XCUIApplication.launchConnected([AccessibilityID.musicDeniedArgument])
        let text = notice(app, AccessibilityID.nowPlayingNotice)
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("hasn't allowed control of Music"))
        // CR-023：被拒時 Mac 讀不到目前曲（事件不帶 trackID）→ 底部是小膠囊、沒有播放控制
        XCTAssertFalse(app.buttons[AccessibilityID.nowPlayingToggle].exists)
        XCTAssertTrue(waitFor("exists == false", on: text, timeout: 15))
    }

    /// #3 Music 未開：說明＋重試；Music 開了（合成資料推 ok）→ 說明消失
    func testMusicNotRunningOffersRetryAndRecovers() {
        let app = XCUIApplication.launchConnected([AccessibilityID.musicNotRunningArgument])
        let text = notice(app, AccessibilityID.nowPlayingNotice)
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("Open Music on your Mac"))
        app.buttons[AccessibilityID.nowPlayingRetry].tap()
        XCTAssertTrue(waitFor("exists == false", on: text, timeout: 15))
    }

    /// #7 捷徑未安裝：點歌 → 「已只播這首（Mac 缺少捷徑）」
    func testMissingShortcutExplainsSingleSongPlayback() {
        let app = XCUIApplication.launchConnected([AccessibilityID.playDegradedArgument])
        openFirstAlbumAndPlay(app, row: 2)
        let text = notice(app, AccessibilityID.albumTracksNotice)
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("Your Mac is missing the shortcut"))
    }

    /// #10 驗證逾時：「狀態無法確定」＋重新同步；按下 → 提示消失
    func testUncertainResultOffersResync() {
        let app = XCUIApplication.launchConnected([AccessibilityID.playUncertainArgument])
        openFirstAlbumAndPlay(app, row: 4)
        let text = notice(app, AccessibilityID.albumTracksNotice)
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("Couldn't confirm what's playing"))
        app.buttons["Resync"].firstMatch.tap()
        XCTAssertTrue(waitFor("exists == false", on: text, timeout: 5))
    }
}
