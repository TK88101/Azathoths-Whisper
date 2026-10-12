import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 3 計劃 T4：Nu-metal 新增的動作模板、背景與效果（原樣移植原型 lyrics-fx-preview.html 的 drop／flip／type／bands、
// scan／grid 背景與 rgbsplit）。歌詞為編造句

@Suite("Glyph templates — B2 batch 3")
struct GlyphTemplatesB2BatchThreeTests {
    static let context = GlyphTemplatesTests.context

    @Test func dropFallsFromHighAboveAndSquashesAsItLands() {
        let start = EnterTemplate.drop.transform(progress: 0, context: Self.context)
        #expect(abs(start.dy - (-560 * 0.9)) < 1e-6 && start.scaleX == 1 && start.scaleY == 1 && start.alpha == 1)
        // 最後四分之一壓扁：橫向變窄、縱向拉高，著地時回到原狀
        let landing = EnterTemplate.drop.transform(progress: 0.9, context: Self.context)
        #expect(abs(landing.scaleX - 0.96) < 1e-9 && abs(landing.scaleY - 1.072) < 1e-9)
    }

    @Test func flipOpensVerticallyFromAHairline() {
        let start = EnterTemplate.flip.transform(progress: 0, context: Self.context)
        #expect(abs(start.scaleY - 0.01) < 1e-9 && start.scaleX == 1 && start.alpha == 1)
        #expect(abs(EnterTemplate.flip.transform(progress: 0.5, context: Self.context).scaleY - 0.875) < 1e-9)
    }

    @Test func typeAppearsAtOnceSlightlyLargerThenSettles() {
        let start = EnterTemplate.type.transform(progress: 0, context: Self.context)
        #expect(abs(start.scale - 1.08) < 1e-9 && start.alpha == 1)
    }

    /// 原型組合模式的 paint 不讀 `bands`（只有 circuit 家族會切帶）：字原樣停住，到時才消失
    @Test func bandsKeepsTheGlyphUntouchedLikeThePrototypesComposedMode() {
        for x in [0.0, 0.4, 0.99] { #expect(ExitTemplate.bands.transform(progress: x, context: Self.context) == .identity) }
    }
}

@Suite("B2 batch 3 effects")
struct B2BatchThreeEffectTests {
    static let size = CGSize(width: 900, height: 560)
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 2, end: 6, text: "static over glass", isChorus: false),
    ], source: .embeddedLRC, duration: 60)
    static let profile = SongProfile(axes: [.aggression: 0.7, .cold: 0.6], tags: [.cybermetal])

    private func plan(_ t: Double, fx1: String = "none", backdrop: String = "void") -> FramePlan {
        let recipe = ComposedRecipe(font: "Anton", backdrop: backdrop, enter: "type", exit: "cut", fx1: fx1, fx2: "none", palette: "hybridGrey", seed: 3, profile: Self.profile)
        return LyricsFXFrame.plan(timeline: Self.timeline, time: t, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: FixedWidthMeasurer())
    }

    @Test func scanLinesAreAThinDarkLineEveryThreePointsWithOnlyLightGrainOnTop() {
        let frame = plan(3, backdrop: "scan")
        #expect(frame.back == [.hairlines(spacing: 3, color: RGB(hex: 0x000000), opacity: 0.25)])
        #expect(frame.front.count == 1)
        if case .grain(let opacity, _, let overlay)? = frame.front.first { #expect(opacity == 0.05 && !overlay) } else { Issue.record("掃描線上方應只有細顆粒") }
    }

    @Test func gridIsHairlineSquaresInTheDimColourDriftingDiagonally() throws {
        let palette = try #require(LyricsFXCatalog.palette("hybridGrey"))
        let still = ComposedBackdrop.back(.grid, palette: palette, size: Self.size, time: 0)
        guard case .rects(let rects, let color, let opacity)? = still.first, still.count == 1 else { Issue.record("網格應是一層細線"); return }
        #expect(color == palette.dim && opacity == 0.5)
        #expect(rects.filter { $0.width == 1 }.count == 25 && rects.filter { $0.height == 1 }.count == 16)
        #expect(rects.filter { $0.width == 1 }.map(\.minX).min() == 0)
        // 每秒移 20 點，36 點一格
        guard case .rects(let moved, _, _)? = ComposedBackdrop.back(.grid, palette: palette, size: Self.size, time: 1).first else { return }
        #expect(moved.filter { $0.width == 1 }.map(\.minX).min() == -20)
        #expect(BackdropKind.grid.tone == nil && BackdropKind.scan.tone == nil)
    }

    @Test func rgbSplitFlanksEachGlyphWithARedAndABlueCopyOnlyEarlyInItsEntrance() {
        let early = plan(2.02, fx1: "rgbsplit")
        let red = early.ghosts.filter { $0.color == .splitRed }, blue = early.ghosts.filter { $0.color == .splitBlue }
        #expect(!red.isEmpty && red.count == blue.count)
        let sides: [(GlyphDraw, CGFloat)] = red.map { ($0, -1) } + blue.map { ($0, 1) }
        for (copy, side) in sides {
            let glyph = early.glyphs.first { $0.text == copy.text && abs($0.origin.y - copy.origin.y) < 1e-6 && abs($0.origin.x - copy.origin.x) <= 6 + 1e-6 }
            #expect(glyph != nil)
            if let glyph { #expect((copy.origin.x - glyph.origin.x) * side >= 0 && abs(copy.opacity - glyph.opacity * 0.9) < 1e-9) }
        }
        #expect(!plan(5.5, fx1: "rgbsplit").ghosts.contains { $0.color == .splitRed || $0.color == .splitBlue })
        #expect(!plan(2.02).ghosts.contains { $0.color == .splitRed })
    }
}
