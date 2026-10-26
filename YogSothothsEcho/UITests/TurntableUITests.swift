import XCTest

/// S5 T11（sprint-5-detail.md §5）：唱機畫面以合成播放器（一開始就在播第一張的第 1 首）驗手勢接上真控制：
/// 播放列入口 → 點唱片＝暫停／繼續 → 左甩＝下一首、右甩＝上一首 → 浮層關閉回曲庫（唱機不提供拖唱頭，CR-019）（只橫屏由 S1 的 Shell 測試與 Info.plist 保證）
final class TurntableUITests: XCTestCase {
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
    private var arm: XCUIElement { app.descendants(matching: .any)[AccessibilityID.turntableArm] }

    /// 關閉唱機回到曲庫，讀播放列的曲名
    private func closeAndReadTitle() -> String {
        // 最右側中間＝整組唱機（寬 ≤ 0.92W、置中）以外的空白：叫出浮層。上方中央會落在傾斜封面的外接框內（＝點封面套）
        // 甩動切歌的轉場（約 1.2 s＋期限）進行中點擊一律忽略（§4.2b v1.4）：點了沒出現浮層就等一下再點
        let close = app.buttons[AccessibilityID.turntableClose]
        for _ in 0..<5 where !close.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.5)).tap()
            _ = close.waitForExistence(timeout: 1.5)
        }
        XCTAssertTrue(close.exists)
        close.tap()
        let title = app.staticTexts[AccessibilityID.nowPlayingTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        return title.label
    }

    func testTapRecordTogglesPlayback() {
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: record))
        record.tap()
        XCTAssertTrue(waitFor("label == %@", ["Play"], on: record))
        record.tap()
        XCTAssertTrue(waitFor("label == %@", ["Pause"], on: record))
    }

    /// XCUITest 以裝置（直立）座標回報與拖動，畫面卻是橫屏：以「唱片中心 → 唱臂」當畫面的右方，拖動向量沿它算
    private func swipe(towardRight: Bool) {
        let r = record.frame, a = arm.frame
        var dx = a.midX - r.midX, dy = a.midY - r.midY
        let length = max(hypot(dx, dy), 1)
        dx /= length
        dy /= length
        let sign: CGFloat = towardRight ? 1 : -1
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: r.midX, dy: r.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: sign * dx * 400, dy: sign * dy * 400)))
    }

    /// v2.1 T8：DEBUG 調整面板的滑桿拖到兩端，不得被場景的甩動手勢吃掉而切歌
    func testTuningSlidersDoNotSkipTracks() {
        let tint = app.sliders[AccessibilityID.turntableTuningTint], haze = app.sliders[AccessibilityID.turntableTuningOtherHaze]
        for _ in 0..<5 where !tint.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.5)).tap()
            _ = tint.waitForExistence(timeout: 1.5)
        }
        XCTAssertTrue(tint.exists && haze.exists)
        for slider in [tint, haze] {
            slider.adjust(toNormalizedSliderPosition: 0)
            slider.adjust(toNormalizedSliderPosition: 1)
        }
        XCTAssertEqual(closeAndReadTitle(), "Synthetic Song 01")
    }

    func testSwipeLeftSkipsToNextAndRightGoesBack() {
        swipe(towardRight: false)
        XCTAssertEqual(closeAndReadTitle(), "Synthetic Song 02")
        app.buttons[AccessibilityID.nowPlayingOpenTurntable].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        swipe(towardRight: true)
        XCTAssertEqual(closeAndReadTitle(), "Synthetic Song 01")
    }
}
