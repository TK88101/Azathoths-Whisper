import SwiftUI
import Testing
@testable import YogSothothsEcho

// CR-023（s6-61-f8f9-shell.md §5.3）：底部膠囊只看「是否有目前曲」；未連線＝idle
struct DockPresentationTests {
    @Test(arguments: [true, false])
    func stateFollowsCurrentTrackOnly(connected: Bool) {
        #expect(DockPresentation.state(currentTrackID: "00000000000000aa", isConnected: connected) == (connected ? .hasCurrentTrack : .idle))
        #expect(DockPresentation.state(currentTrackID: nil, isConnected: connected) == .idle)
    }

    @Test func geometryMatchesTheSignedPreview() {
        #expect(DockPresentation.size(.idle) == CGSize(width: 168, height: 46))
        #expect(DockPresentation.size(.hasCurrentTrack) == CGSize(width: 640, height: 64))
        #expect(DockPresentation.controlInset == (horizontal: 62, vertical: 7))
        #expect(DockPresentation.bottomMargin == 26)
    }

    /// 小封面離控制層左緣、▶▶ 可見圖形離右緣同為 16 pt（圖示框 22 pt、▶▶ 圖形右側留白 3/24）
    @Test func controlLayerEdgesAreSymmetric() {
        let rightGlyphGap = DockPresentation.skipIconSide * 3 / 24
        #expect(abs(DockPresentation.controlPadding.leading - 16) < 1e-9)
        #expect(abs(DockPresentation.controlPadding.trailing + rightGlyphGap - 16) < 1e-9)
    }

    /// 控制層透到背景：字色依控制層後面背景的亮度（同詳情頁門檻與遲滯；使用者 2026-10-23「太黑的背景時看不清」）
    @Test func controlInkFollowsTheBackgroundBehindIt() {
        #expect(DockPresentation.controlInk(luminance: 0.05, previous: nil) == .white)
        #expect(DockPresentation.controlInk(luminance: 0.6, previous: nil) == .dark)
        #expect(DockPresentation.controlInk(luminance: 0.20, previous: .white) == .white, "帶內沿用")
        #expect(DockPresentation.controlInk(luminance: 0.20, previous: nil) == .dark)
    }

    /// 取樣區＝控制層在畫面上的框
    @Test func controlRectSitsAboveTheBottomMargin() {
        let rect = DockPresentation.controlRect(in: CGSize(width: 1376, height: 1032))
        #expect(rect.width == 640 - 2 * 62 && rect.height == 64 - 2 * 7)
        #expect(rect.midX == 688 && abs(rect.maxY - (1032 - 26 - 7)) < 1e-9)
    }
}

struct ShellChromeTests {
    /// 詳情開著時設定鈕隱藏、返回鍵佔左上（使用者 2026-10-23 認可）
    @Test func settingsButtonHidesWhileDetailIsOpen() {
        #expect(ShellChrome.showsSettingsButton(detailOpen: false))
        #expect(!ShellChrome.showsSettingsButton(detailOpen: true))
    }
}
