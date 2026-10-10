import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 2 計劃 T4：龐克系新增的動作模板、效果與背景（原樣移植原型 lyrics-fx-preview.html 的 tumble／tumbleOut／jitter／tilt、
// speedLines、勒索信（ransom）與 B2 批 2 的背景）。歌詞為編造句

@Suite("Glyph templates — B2 batch 2")
struct GlyphTemplatesB2BatchTwoTests {
    static let context = GlyphTemplatesTests.context

    @Test func tumbleDropsInFromAboveSpinningOneFullTurn() {
        let start = EnterTemplate.tumble.transform(progress: 0, context: Self.context)
        #expect(abs(start.dy - (-560 * 0.7)) < 1e-6 && abs(start.dx - 40) < 1e-6)
        #expect(abs(start.rotation - 2 * .pi) < 1e-4 && start.alpha == 0)
        let midway = EnterTemplate.tumble.transform(progress: 0.5, context: Self.context)
        #expect(midway.alpha == 1 && midway.dy < 0 && midway.dy > start.dy)
    }

    @Test func tumbleOutFallsAndSpinsButStaysMostlyOpaque() {
        #expect(ExitTemplate.tumbleOut.transform(progress: 0, context: Self.context) == .identity)
        let end = ExitTemplate.tumbleOut.transform(progress: 1, context: Self.context)
        #expect(abs(end.dy - 560 * 0.6) < 1e-6 && abs(end.rotation - 4) < 1e-6 && abs(end.alpha - 0.7) < 1e-9)
    }

    @Test func jitterShiversByAboutAPointWithoutFading() {
        let samples = stride(from: 0.0, to: 1.0, by: 0.013).map { HoldTemplate.jitter.transform(time: $0, context: Self.context) }
        #expect(samples.allSatisfy { abs($0.dx) <= 1.2 + 1e-9 && abs($0.dy) <= 0.8 + 1e-9 && $0.alpha == 1 && $0.rotation == 0 })
        #expect(Set(samples.map { Int(($0.dx * 100).rounded()) }).count > 5)
    }

    @Test func tiltIsAFixedSmallAngleWhoseDirectionDependsOnTheGlyph() {
        let left = GlyphContext(em: 40, width: 900, height: 560, radius: 495, dir: 1, side: -1, phase: 0.7, angle: 0, bend: 0)
        let right = GlyphContext(em: 40, width: 900, height: 560, radius: 495, dir: 1, side: -1, phase: 4, angle: 0, bend: 0)
        for time in [0.0, 1.3, 9.9] {
            #expect(HoldTemplate.tilt.transform(time: time, context: left) == GlyphTransform(rotation: -0.05))
            #expect(HoldTemplate.tilt.transform(time: time, context: right) == GlyphTransform(rotation: 0.05))
        }
    }
}

@Suite("B2 batch 2 effects")
struct B2BatchTwoEffectTests {
    static let size = CGSize(width: 900, height: 560)
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 2, end: 6, text: "lanterns over water", isChorus: false),
    ], source: .embeddedLRC, duration: 60)
    static let profile = SongProfile(axes: [.aggression: 0.5, .elegance: 0.1], tags: [.poppunk])

    private static func recipe(fx1: String, fx2: String = "none", backdrop: String = "void", palette: String = "gigRed") -> ComposedRecipe {
        ComposedRecipe(font: "Bangers", backdrop: backdrop, enter: "slide", exit: "up", fx1: fx1, fx2: fx2, palette: palette, seed: 3, profile: profile)
    }

    private func plan(_ t: Double, fx1: String, fx2: String = "none", backdrop: String = "void", palette: String = "gigRed") -> FramePlan {
        LyricsFXFrame.plan(
            timeline: Self.timeline, time: t, size: Self.size, motion: .full,
            recipe: .composed(Self.recipe(fx1: fx1, fx2: fx2, backdrop: backdrop, palette: palette)), measurer: FixedWidthMeasurer()
        )
    }

    private func rects(_ layers: [LayerDraw]) -> [(rects: [CGRect], opacity: Double)] {
        layers.compactMap { if case .rects(let rects, _, let opacity) = $0 { (rects, opacity) } else { nil } }
    }

    @Test func speedLinesStreakBehindTheTextRightAfterALineStartsThenStop() throws {
        let early = try #require(rects(plan(2.05, fx1: "speedlines").back).first)
        #expect(early.rects.count == 24)
        #expect(early.rects.allSatisfy { $0.height == 1 && $0.width >= 90 - 1e-6 && $0.width <= 450 + 1e-6 })
        #expect(abs(early.opacity - 0.35 * (1 - 0.05 / 0.35)) < 1e-9)
        #expect(rects(plan(2.5, fx1: "speedlines").back).isEmpty)
        #expect(rects(plan(2.05, fx1: "none").back).isEmpty)
    }

    @Test(arguments: ["ransom", "ransomPop"])
    func ransomNotePutsATiltedScrapOfPaperBehindEveryGlyph(effect: String) {
        let frame = plan(5.5, fx1: effect)
        #expect(frame.boxes.count == frame.glyphs.count && !frame.boxes.isEmpty)
        for (box, glyph) in zip(frame.boxes, frame.glyphs) {
            switch box.color {
            case .black, .paperRed: #expect(glyph.color == .white)
            case .white, .paperYellow: #expect(glyph.color == .black)
            default: Issue.record("紙片不該用配色槽 \(box.color)")
            }
            #expect(abs(box.rotation - glyph.rotation) <= 0.15 + 1e-9)
            #expect(box.size.height > glyph.fontSize && box.opacity == glyph.opacity)
        }
        #expect(Set(frame.boxes.map(\.color)).count > 1)
        // 同一個字每一幀都是同一張紙
        #expect(plan(5.6, fx1: effect).boxes.map(\.color) == frame.boxes.map(\.color))
        #expect(plan(5.5, fx1: "none").boxes.isEmpty)
    }

    @Test(arguments: [("jitter", HoldTemplate.jitter), ("tilt", .tilt)])
    func theNewSmallHoldEffectsBecomeTheHoldTemplate(effect: String, template: HoldTemplate) throws {
        let style = try #require(ResolvedStyle(Self.recipe(fx1: effect)))
        #expect(style.personality.hold.first?.0 == template)
    }

    /// 停留的優先序照原型：bob → wobble → flicker → jitter → tilt → breathe
    @Test func olderHoldEffectsStillWinWhenTwoAreDrawnTogether() throws {
        #expect(try #require(ResolvedStyle(Self.recipe(fx1: "jitter", fx2: "wobble"))).personality.hold.first?.0 == .wobble)
        #expect(try #require(ResolvedStyle(Self.recipe(fx1: "tilt", fx2: "jitter"))).personality.hold.first?.0 == .jitter)
    }

    @Test(arguments: ["xerox", "gig", "checker", "bokeh", "skyGrad"])
    func everyNewBackdropDrawsSomething(backdrop: String) {
        let frame = plan(3, fx1: "none", backdrop: backdrop)
        #expect(!(frame.back + frame.front).isEmpty, "\(backdrop)")
    }

    @Test func theFlatBackdropIsJustThePaletteBackground() {
        let frame = plan(3, fx1: "none", backdrop: "flat", palette: "yellowBlack")
        #expect(frame.back.isEmpty && frame.front.isEmpty)
    }

    @Test func checkerIsTwoRowsOfAlternatingSquaresAlongTheBottomEdge() throws {
        let layer = try #require(rects(plan(3, fx1: "none", backdrop: "checker").back).first)
        let side = Self.size.height * 0.05
        #expect(layer.rects.count == 33)
        #expect(layer.rects.allSatisfy { abs($0.width - side) < 1e-9 && abs($0.height - side) < 1e-9 && $0.minY >= Self.size.height - 2 * side - 1e-9 })
        let bottom = Set(layer.rects.filter { $0.minY > Self.size.height - side - 1e-6 }.map { Int(($0.minX / side).rounded()) })
        let upper = Set(layer.rects.filter { $0.minY < Self.size.height - side - 1e-6 }.map { Int(($0.minX / side).rounded()) })
        #expect(bottom.allSatisfy { $0.isMultiple(of: 2) } && upper.allSatisfy { !$0.isMultiple(of: 2) })
    }

    @Test func onlyTheStageLitBackdropsInsistOnADarkPalette() {
        #expect(BackdropKind.gig.tone == .dark && BackdropKind.bokeh.tone == .dark)
        for kind in [BackdropKind.flat, .xerox, .checker, .skyGrad] { #expect(kind.tone == nil, "\(kind)") }
    }
}
