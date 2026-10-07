import CoreGraphics
import Testing

@testable import AzathothsWhisper

// B1 計劃 T2 DoD②：型別換形後，mono 的 plan 與換形前（e640d4b）錄下的 golden 逐欄相等
@Suite("mono golden")
struct MonoGoldenTests {
    @Test func theMonoPlanIsUnchangedByTheNewTypes() throws {
        var actual: [MonoGolden.Row] = []
        for (name, timeline, size) in MonoGoldenFixtures.cases {
            for t in MonoGoldenFixtures.times {
                for motion in [LyricsFXMotion.full, .reduced] {
                    let plan = LyricsFXFrame.plan(timeline: timeline, time: t, size: size, motion: motion, measurer: FixedWidthMeasurer())
                    actual += plan.glyphs.map { glyph in
                        MonoGolden.Row(
                            fixture: name, time: t, isFull: motion == .full, text: glyph.text, fontSize: glyph.fontSize,
                            isMedium: glyph.face == .displayMedium, x: glyph.origin.x, y: glyph.origin.y,
                            opacity: glyph.opacity, isPrimary: glyph.color == .fg
                        )
                    }
                }
            }
        }
        try #require(actual.count == MonoGolden.rows.count, "列數 \(actual.count) vs \(MonoGolden.rows.count)")
        for (new, old) in zip(actual, MonoGolden.rows) {
            #expect(new.fixture == old.fixture && new.time == old.time && new.isFull == old.isFull && new.text == old.text)
            #expect(abs(new.fontSize - old.fontSize) < 0.01 && new.isMedium == old.isMedium && new.isPrimary == old.isPrimary)
            #expect(abs(new.x - old.x) < 0.01 && abs(new.y - old.y) < 0.01, "\(old.fixture)@\(old.time) \(old.text)")
            #expect(abs(new.opacity - old.opacity) < 1e-9)
        }
    }

    @Test func monoGlyphsCarryNoTransform() {
        let (_, timeline, size) = MonoGoldenFixtures.cases[0]
        let glyphs = LyricsFXFrame.plan(timeline: timeline, time: 3, size: size, motion: .full, measurer: FixedWidthMeasurer()).glyphs
        #expect(!glyphs.isEmpty)
        #expect(glyphs.allSatisfy { $0.rotation == 0 && $0.scaleX == 1 && $0.scaleY == 1 })
    }

    @Test func monoUsesTheMonoPaletteAndNoLayers() {
        let (_, timeline, size) = MonoGoldenFixtures.cases[0]
        let plan = LyricsFXFrame.plan(timeline: timeline, time: 3, size: size, motion: .full, measurer: FixedWidthMeasurer())
        #expect(plan.palette == .mono)
        #expect(plan.back.isEmpty && plan.front.isEmpty && plan.ghosts.isEmpty)
    }
}

// B1 計劃 §3.2：只合併 painter order 上連續、同鍵（色槽, 量化 opacity）的字
@Suite("LyricsFX canvas runs")
struct LyricsFXCanvasRunTests {
    private func glyph(_ opacity: Double, _ color: ColorSlot = .fg) -> GlyphDraw {
        GlyphDraw(text: "a", face: .displayMedium, fontSize: 20, origin: .zero, opacity: opacity, color: color)
    }

    @Test func consecutiveSameKeysMergeIntoOneRun() {
        let runs = LyricsFXCanvas.runs(of: [glyph(1), glyph(1), glyph(1)])
        #expect(runs.count == 1)
        #expect(runs.first?.range == 0..<3)
    }

    @Test func aDifferentKeyInBetweenSplitsTheRunsToKeepPainterOrder() {
        let runs = LyricsFXCanvas.runs(of: [glyph(0.2), glyph(0.5), glyph(0.2)])
        #expect(runs.map(\.range) == [0..<1, 1..<2, 2..<3])
    }

    @Test func aDifferentColorSlotSplitsTheRun() {
        #expect(LyricsFXCanvas.runs(of: [glyph(1, .fg), glyph(1, .dim)]).count == 2)
    }

    @Test func invisibleGlyphsProduceNoRun() {
        let runs = LyricsFXCanvas.runs(of: [glyph(0), glyph(1), glyph(0.01)])
        #expect(runs.map(\.range) == [1..<2])
    }

    @Test func quantizationErrorIsAtMostHalfAStep() {
        for step in 0...1000 {
            let opacity = Double(step) / 1000
            let level = LyricsFXCanvas.opacityLevel(opacity)
            #expect(abs(LyricsFXCanvas.opacity(ofLevel: level) - opacity) <= 0.5 / Double(LyricsFXCanvas.opacityLevels) + 1e-12)
        }
    }

    @Test func monoOpacitiesAreExactLevels() {
        for opacity in [1.0, LyricsFXFrame.Mono.previewOpacity] {
            #expect(LyricsFXCanvas.opacity(ofLevel: LyricsFXCanvas.opacityLevel(opacity)) == opacity)
        }
    }
}
