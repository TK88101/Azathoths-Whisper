import SwiftUI
import Testing

@testable import YogSothothsEcho

// S6 #6-1 g 版 T8（s6-61-g-perf-wear.md §5.8）：小圖狀態下「切回側封」的圖示＝兩條細豎線＋右側一塊較寬的板（使用者截圖 19.13.11）
struct SpineStackGlyphTests {
    @Test func glyphHasTwoBarsAndAWiderPlate() {
        let parts = SpineStackGlyph.parts(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        #expect(parts.count == 3)
        let widths = parts.map { $0.boundingRect.width }
        #expect(widths[0] < widths[2] / 2 && widths[1] < widths[2] / 2)
        #expect(parts[0].boundingRect.maxX < parts[1].boundingRect.minX && parts[1].boundingRect.maxX < parts[2].boundingRect.minX)
        // 板的左緣長、右緣短（參考影片；使用者 2026-10-23 更正）
        let plate = parts[2].boundingRect
        #expect(plate.height > parts[0].boundingRect.height)
        #expect(SpineStackGlyph.plateEdges(in: CGRect(x: 0, y: 0, width: 24, height: 24)).left
                > SpineStackGlyph.plateEdges(in: CGRect(x: 0, y: 0, width: 24, height: 24)).right)
    }

    /// 兩條豎線與板的長邊（左緣）等長（使用者 2026-10-24）
    @Test func barsMatchThePlateLongEdge() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        let parts = SpineStackGlyph.parts(in: rect)
        let long = SpineStackGlyph.plateEdges(in: rect).left
        #expect(abs(parts[0].boundingRect.height - long) < 0.01)
        #expect(abs(parts[1].boundingRect.height - long) < 0.01)
    }

    @Test func gridStateShowsSpineGlyph() {
        #expect(BrowseLayout.grid.buttonIcon == .spines)
        #expect(BrowseLayout.spines.buttonIcon == .squares)
    }
}

import UIKit

// 唱機鈕圖示（使用者 2026-10-23：同心圓不像）：系統符號要真的存在，否則畫面上是空白
struct TurntableGlyphTests {
    @Test func opticalDiscSymbolExists() {
        #expect(UIImage(systemName: "opticaldisc.fill") != nil)
    }
}
