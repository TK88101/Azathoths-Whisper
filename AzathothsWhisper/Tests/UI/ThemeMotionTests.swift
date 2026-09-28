import SwiftUI
import Testing

@testable import AzathothsWhisper

// 層的位移動畫（設計稿 cubic-bezier(.16, 1, .3, 1) 620ms）：Cover Flow 升降與換歌平移共用
// （計劃 docs/plans/2026-09-26-coverflow-follow-playback-slide.md §3.6、§7-1）
@Suite("Theme.Motion")
struct ThemeMotionTests {
    @Test func layerShiftMatchesTheDesign() {
        #expect(Theme.Motion.layerShiftDuration == 0.62)
        #expect(Theme.Motion.layerShift == Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.62))
    }
}
