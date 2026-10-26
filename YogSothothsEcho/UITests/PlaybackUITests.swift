import XCTest

// S4 T11（sprint-4-detail.md §7「X」）：以 DEBUG 合成播放器（曲名自編）走選歌、暫停、跳曲、拖進度（失敗文案在 RemoteFailureUITests）。不截圖
final class PlaybackUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testPickSongPauseSkipAndDragProgress() {
        let app = XCUIApplication.launchConnected()
        app.openFirstAlbum()
        app.buttons[AccessibilityID.albumTracksRow(3)].tap()
        app.buttons[AccessibilityID.albumTracksClose].tap()

        let title = app.staticTexts[AccessibilityID.nowPlayingTitle]
        XCTAssertTrue(waitFor("label == %@", ["Synthetic Song 03"], on: title))
        let toggle = app.buttons[AccessibilityID.nowPlayingToggle]
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: toggle))
        toggle.tap()
        XCTAssertTrue(waitFor("label == %@", ["Play"], on: toggle))

        app.buttons[AccessibilityID.nowPlayingNext].tap()
        XCTAssertTrue(waitFor("label == %@", ["Synthetic Song 04"], on: title))
        app.buttons[AccessibilityID.nowPlayingPrevious].tap()
        XCTAssertTrue(waitFor("label == %@", ["Synthetic Song 03"], on: title))

        // CR-023：iPad 不提供跳進度（F-P-04 → W），播放列不再有進度條
        XCTAssertFalse(app.sliders.firstMatch.exists)
    }

    // MARK: Genius（CR-030 G6；合成器：Genius 換到下一張合成專輯的第 1 首）

    func testGeniusOnWideCapsuleSwitchesToAnotherAlbum() {
        let app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument])
        let title = app.staticTexts[AccessibilityID.nowPlayingTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let genius = app.buttons[AccessibilityID.nowPlayingGenius]
        XCTAssertTrue(genius.waitForExistence(timeout: 10))
        XCTAssertEqual(genius.label, "Genius")
        XCTAssertTrue(app.buttons[AccessibilityID.nowPlayingPrevious].exists)
        XCTAssertLessThan(genius.frame.maxX, app.buttons[AccessibilityID.nowPlayingPrevious].frame.minX, "Genius 要在 ◀◀ 前")
        XCTAssertEqual(genius.frame.height, app.buttons[AccessibilityID.nowPlayingNext].frame.height, accuracy: 0.5)
        let before = title.value as? String
        genius.tap()
        XCTAssertTrue(waitFor("value != %@", [before ?? ""], on: title, timeout: 10))
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: app.buttons[AccessibilityID.nowPlayingToggle]))
    }

    /// CR-031：沒有目前曲＝小膠囊 3 鈕，順序 展示方式→Genius→唱盤
    func testIdleCapsuleHasLayoutGeniusAndTurntableInOrder() {
        let app = XCUIApplication.launchConnected()
        let dock = app.otherElements[AccessibilityID.nowPlayingBar]
        XCTAssertTrue(app.buttons[AccessibilityID.nowPlayingGenius].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[AccessibilityID.nowPlayingPrevious].exists)
        let ids = (0..<dock.buttons.count).map { dock.buttons.element(boundBy: $0).identifier }
        XCTAssertEqual(ids, [AccessibilityID.browseLayoutButton, AccessibilityID.nowPlayingGenius, AccessibilityID.nowPlayingOpenTurntable])
        XCTAssertEqual(app.buttons[AccessibilityID.nowPlayingGenius].label, "Genius")
    }

    /// 小膠囊按 Genius → 開始播、展開成寬膠囊
    func testIdleGeniusStartsPlayingAndWidensTheCapsule() {
        let app = XCUIApplication.launchConnected()
        let genius = app.buttons[AccessibilityID.nowPlayingGenius]
        XCTAssertTrue(genius.waitForExistence(timeout: 10))
        genius.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.nowPlayingPrevious].waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: app.buttons[AccessibilityID.nowPlayingToggle]))
    }

    /// 舊 Mac：小膠囊回到現行兩欄（不留中間空格）
    func testLegacyMacIdleCapsuleKeepsTheTwoColumnLayout() {
        let app = XCUIApplication.launchConnected([AccessibilityID.geniusLegacyMacArgument])
        let turntable = app.buttons[AccessibilityID.nowPlayingOpenTurntable]
        XCTAssertTrue(turntable.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[AccessibilityID.nowPlayingGenius].exists)
        let dock = app.otherElements[AccessibilityID.nowPlayingBar].buttons
        XCTAssertEqual(dock.count, 2)
        let layout = app.buttons[AccessibilityID.browseLayoutButton].frame, spin = turntable.frame
        // 沒有提示列時 nowPlayingBar 的寬＝膠囊寬。兩欄等分＝兩鈕中心距＝膠囊寬的一半（三欄藏中間＝2/3，會被抓到）
        let capsule = app.otherElements[AccessibilityID.nowPlayingBar].frame
        XCTAssertEqual(spin.midX - layout.midX, capsule.width / 2, accuracy: 1)
        XCTAssertEqual(layout.midX - capsule.minX, capsule.width / 4, accuracy: 1)
    }

    func testIdleGeniusWithoutAccessibilityShowsHint() {
        let app = XCUIApplication.launchConnected([AccessibilityID.geniusNeedsAccessibilityArgument])
        let genius = app.buttons[AccessibilityID.nowPlayingGenius]
        XCTAssertTrue(genius.waitForExistence(timeout: 10))
        genius.tap()
        let notice = app.descendants(matching: .any)[AccessibilityID.nowPlayingNotice]
        XCTAssertTrue(waitFor("label CONTAINS %@", ["Accessibility"], on: notice, timeout: 5))
        XCTAssertFalse(app.buttons[AccessibilityID.nowPlayingPrevious].exists)
    }

    func testLegacyMacHidesGenius() {
        let app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument, AccessibilityID.geniusLegacyMacArgument])
        XCTAssertTrue(app.buttons[AccessibilityID.nowPlayingPrevious].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[AccessibilityID.nowPlayingGenius].exists)
    }

    func testGeniusWithoutAccessibilityShowsHintAndKeepsTheSong() {
        let app = XCUIApplication.launchConnected([AccessibilityID.nowPlayingArgument, AccessibilityID.geniusNeedsAccessibilityArgument])
        let title = app.staticTexts[AccessibilityID.nowPlayingTitle]
        let genius = app.buttons[AccessibilityID.nowPlayingGenius]
        XCTAssertTrue(genius.waitForExistence(timeout: 10))
        let before = title.value as? String
        genius.tap()
        let notice = app.descendants(matching: .any)[AccessibilityID.nowPlayingNotice]
        XCTAssertTrue(waitFor("label CONTAINS %@", ["Accessibility"], on: notice, timeout: 5))
        XCTAssertEqual(title.value as? String, before)
    }
}

