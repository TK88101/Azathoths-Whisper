import SwiftUI
import Testing

@testable import YogSothothsEcho

// CR-030 在場回饋（2026-10-24）：Genius 圖示改照 Apple 網頁原圖描的向量（兩弧＋兩箭頭，原圖 62×60）；SF Symbol `atom` 使用者說不對
struct GeniusGlyphTests {
    @Test func outlineHasFourClosedPiecesInsideTheUnitSquare() {
        #expect(GeniusGlyph.outlines.count == 4)
        for loop in GeniusGlyph.outlines {
            #expect(loop.count >= 3)
            #expect(loop.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        }
    }

    /// 照原圖寬高比置中，填滿較短的那一邊（與 ◀◀ 同框時不變形）
    @Test(arguments: [CGSize(width: 44, height: 44), CGSize(width: 62, height: 60), CGSize(width: 30, height: 60)])
    func pathKeepsAspectAndFillsTheLimitingSide(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let bounds = GeniusGlyph().path(in: rect).boundingRect
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds))
        let fit = min(size.width / GeniusGlyph.aspect, size.height)
        #expect(bounds.height >= fit * 0.9 && bounds.width >= fit * GeniusGlyph.aspect * 0.9)
        #expect(abs(bounds.midX - rect.midX) < 1.5 && abs(bounds.midY - rect.midY) < 1.5)
    }
}
