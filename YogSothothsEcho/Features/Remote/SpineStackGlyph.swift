import SwiftUI

/// 小圖狀態下「切回側封」的圖示（g 版 T8；使用者 2026-10-23 截圖 19.13.11）：兩條細豎線（側看的書脊）＋右側一塊較寬的板
/// （轉向觀眾的那張：左緣長、右緣短＝參考影片，使用者 2026-10-23 更正）。SF Symbols 無相符符號（`books.vertical` 使用者說像書架），故自繪
struct SpineStackGlyph: Shape {
    /// 板左右兩緣的高
    static func plateEdges(in rect: CGRect) -> (left: CGFloat, right: CGFloat) { (0.76 * rect.height, 0.62 * rect.height) }

    static func parts(in rect: CGRect) -> [Path] {
        let w = rect.width, h = rect.height
        // 豎線與板的長邊（左緣）等長（使用者 2026-10-24）
        let plateWidth = 0.30 * w, (plateLeft, plateRight) = plateEdges(in: rect)
        let barWidth = 0.09 * w, barHeight = plateLeft, gap = 0.08 * w
        let total = 2 * barWidth + 2 * gap + plateWidth
        let x0 = rect.minX + (w - total) / 2, midY = rect.midY
        func bar(_ x: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight), cornerRadius: barWidth / 2)
        }
        let px = x0 + 2 * barWidth + 2 * gap
        var plate = Path()
        plate.move(to: CGPoint(x: px, y: midY - plateLeft / 2))
        plate.addLine(to: CGPoint(x: px + plateWidth, y: midY - plateRight / 2))
        plate.addLine(to: CGPoint(x: px + plateWidth, y: midY + plateRight / 2))
        plate.addLine(to: CGPoint(x: px, y: midY + plateLeft / 2))
        plate.closeSubpath()
        return [bar(x0), bar(x0 + barWidth + gap), plate]
    }

    func path(in rect: CGRect) -> Path {
        Self.parts(in: rect).reduce(into: Path()) { $0.addPath($1) }
    }
}
