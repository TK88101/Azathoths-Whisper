import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// 批 4 遺留的三個顯示問題（docs/plans/2026-10-17-lyrics-fx-batch4-leftovers.md）：超寬單字、霓虹描邊隨該句 em、Anton 字級。
// 歌詞為編造句
@MainActor
@Suite("B2 batch 4 leftovers")
struct B2BatchFourLeftoverTests {
    static let wide = LongLineFitTests.wide
    static let narrow = LongLineFitTests.narrow
    /// 沒有空白的一串（像網址或拉長的叫喊）：寬視窗用 24 字、窄視窗用 13 字——原 em 放不下、縮到 0.5 倍以內就放得下
    static func oversized(for size: CGSize) -> String {
        "Paper " + (size.width > 1200 ? "harborlightsdriftingpast" : "harborlightsd") + " tonight"
    }
    /// 0.5 倍也放不下的一串
    static let enormous = "Gulls " + String(repeating: "lanternsoverthewater", count: 6) + " bells"

    static func line(_ text: String) -> TimedLine { TimedLine(start: 2, end: 40, text: text, isChorus: false) }

    static func report(_ text: String, font: String = "Marker", size: CGSize, fx1: String = "jitter", fx2: String = "reflect") -> ComposedStyle.FitReport? {
        ComposedStyle.fitReport(line: line(text), index: 0, recipe: LongLineFitTests.recipe(font: font, fx1: fx1, fx2: fx2), size: size, measurer: CoreTextMeasurer())
    }

    static func plan(_ text: String, font: String = "Marker", size: CGSize, t: Double = 33.3, enter: String = "type", fx1: String = "jitter", fx2: String = "reflect") -> FramePlan {
        let timeline = LyricsTimeline(lines: [line(text)], source: .embeddedLRC, duration: 60)
        return LyricsFXFrame.plan(timeline: timeline, time: t, size: size, motion: .full,
                                  recipe: .composed(LongLineFitTests.recipe(font: font, enter: enter, fx1: fx1, fx2: fx2)), measurer: CoreTextMeasurer())
    }

    /// 主字形實際墨跡的左右緣（真實字形外框＋繪製端同一個仿射變換）
    static func inkSpanX(_ frame: FramePlan) -> (left: CGFloat, right: CGFloat) {
        let paths = GlyphPathCache()
        var left = CGFloat.infinity, right = -CGFloat.infinity
        for glyph in frame.glyphs {
            let entry = paths.entry(for: glyph)
            let box = entry.path.boundingBoxOfPath.applying(LyricsFXCanvas.transform(for: glyph, entry: entry))
            left = min(left, box.minX)
            right = max(right, box.maxX)
        }
        return (left, right)
    }

    static func maxWidth(_ size: CGSize) -> CGFloat { size.width * ComposedStyle.maxWidthRatio }

    // MARK: ① 超寬單字

    @Test(arguments: [CGSize(width: 1728, height: 945), CGSize(width: 900, height: 945)])
    func anOversizedWordShrinksUntilEveryRowFitsTheWrapWidth(size: CGSize) throws {
        let text = Self.oversized(for: size)
        let report = try #require(Self.report(text, size: size))
        #expect(report.ratio < 1)
        #expect(!report.breaksLongWords)
        #expect(report.rowWidths.allSatisfy { $0 <= Self.maxWidth(size) }, "列寬 \(report.rowWidths)／上限 \(Self.maxWidth(size))")
        let margin = size.height * ComposedStyle.fitMargin
        for t in [30.0, 33.3, 37.7] {
            let frame = Self.plan(text, size: size, t: t)
            let x = Self.inkSpanX(frame), y = B2BatchFourT7FixTests.inkSpan(frame)
            #expect(!frame.glyphs.isEmpty && x.left >= size.width * ComposedStyle.fitMargin && x.right <= size.width * (1 - ComposedStyle.fitMargin), "t=\(t) 左右 \(x)")
            #expect(y.top >= margin && y.bottom <= size.height - margin, "t=\(t) 上下 \(y)")
        }
    }

    @Test func aWordTooWideEvenAtHalfSizeIsBrokenAcrossRowsAsOneWord() throws {
        let report = try #require(Self.report(Self.enormous, size: Self.narrow))
        #expect(report.ratio == ComposedStyle.minimumFitRatio)
        #expect(report.breaksLongWords)
        #expect(report.rowWidths.allSatisfy { $0 <= Self.maxWidth(Self.narrow) }, "列寬 \(report.rowWidths)")
        let broken = report.glyphs.filter { $0.wordIndex == 1 }
        #expect(broken.count == 120)
        #expect(Set(broken.map(\.row)).count >= 2)
        let frame = Self.plan(Self.enormous, size: Self.narrow)
        let x = Self.inkSpanX(frame)
        #expect(x.left >= 0 && x.right <= Self.narrow.width, "左右 \(x)")
    }

    /// 斷詞以 extended grapheme cluster（Swift Character）為單位：emoji 序列、國旗、組合音標、網址不被拆壞
    @Test func brokenWordsKeepWholeGraphemes() throws {
        let token = String(repeating: "\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1F1EF}\u{1F1F5}e\u{0301}", count: 12)
            + "https://example.com/harbor/lights?boat=paper&tide=slow#pier"
        let report = try #require(Self.report("Boats " + token, size: Self.narrow))
        let glyphs = report.glyphs.filter { $0.wordIndex == 1 }
        #expect(glyphs.allSatisfy { $0.text.count == 1 })
        #expect(glyphs.count == token.count)
    }

    @Test func aBrokenLineThatStillCannotFitIsDrawnAtHalfSize() throws {
        let size = CGSize(width: 900, height: 300)
        let text = String(repeating: "saltalongtheropeandthebells", count: 12)
        let report = try #require(Self.report(text, size: size))
        #expect(report.ratio == ComposedStyle.minimumFitRatio && report.breaksLongWords)
        #expect(!Self.plan(text, size: size).glyphs.isEmpty)
    }

    /// 改版前（main 93dee59）記下的比例：不含超寬單字的句子必須逐位元相同；第二次（快取命中）也一樣
    static let baselineLines = [LongLineFitTests.short, LongLineFitTests.long, LongLineFitTests.extreme, "灯籠が川を流れてゆく夜",
                                "Lanterns low 灯籠が流れる lanterns slow", "Quiet harbor, quiet hands and the ferry hums a tune nobody wrote"]
    static let baseline: [(font: String, line: Int, width: Int, height: Int, bits: UInt64)] = [
        ("Marker", 0, 1728, 945, 0x3ff0000000000000),
        ("Marker", 0, 900, 945, 0x3ff0000000000000),
        ("Marker", 0, 1200, 800, 0x3ff0000000000000),
        ("Marker", 1, 1728, 945, 0x3fecc00000000001),
        ("Marker", 1, 900, 945, 0x3fe4800000000000),
        ("Marker", 1, 1200, 800, 0x3fe9800000000000),
        ("Marker", 2, 1728, 945, 0x3fe6400000000001),
        ("Marker", 2, 900, 945, 0x3fe0000000000000),
        ("Marker", 2, 1200, 800, 0x3fe3800000000000),
        ("Marker", 3, 1728, 945, 0x3ff0000000000000),
        ("Marker", 3, 900, 945, 0x3ff0000000000000),
        ("Marker", 3, 1200, 800, 0x3ff0000000000000),
        ("Marker", 4, 1728, 945, 0x3ff0000000000000),
        ("Marker", 4, 900, 945, 0x3ff0000000000000),
        ("Marker", 4, 1200, 800, 0x3ff0000000000000),
        ("Marker", 5, 1728, 945, 0x3ff0000000000000),
        ("Marker", 5, 900, 945, 0x3fe9c00000000000),
        ("Marker", 5, 1200, 800, 0x3ff0000000000000),
        ("RockSalt", 0, 1728, 945, 0x3ff0000000000000),
        ("RockSalt", 0, 900, 945, 0x3ff0000000000000),
        ("RockSalt", 0, 1200, 800, 0x3ff0000000000000),
        ("RockSalt", 1, 1728, 945, 0x3ff0000000000000),
        ("RockSalt", 1, 900, 945, 0x3fea800000000000),
        ("RockSalt", 1, 1200, 800, 0x3ff0000000000000),
        ("RockSalt", 2, 1728, 945, 0x3fed400000000001),
        ("RockSalt", 2, 900, 945, 0x3fe5000000000000),
        ("RockSalt", 2, 1200, 800, 0x3fe9c00000000000),
        ("RockSalt", 3, 1728, 945, 0x3ff0000000000000),
        ("RockSalt", 3, 900, 945, 0x3ff0000000000000),
        ("RockSalt", 3, 1200, 800, 0x3ff0000000000000),
        ("RockSalt", 4, 1728, 945, 0x3ff0000000000000),
        ("RockSalt", 4, 900, 945, 0x3ff0000000000000),
        ("RockSalt", 4, 1200, 800, 0x3ff0000000000000),
        ("RockSalt", 5, 1728, 945, 0x3ff0000000000000),
        ("RockSalt", 5, 900, 945, 0x3ff0000000000000),
        ("RockSalt", 5, 1200, 800, 0x3ff0000000000000),
        ("IMFell", 0, 1728, 945, 0x3ff0000000000000),
        ("IMFell", 0, 900, 945, 0x3ff0000000000000),
        ("IMFell", 0, 1200, 800, 0x3ff0000000000000),
        ("IMFell", 1, 1728, 945, 0x3fef000000000000),
        ("IMFell", 1, 900, 945, 0x3fe8000000000000),
        ("IMFell", 1, 1200, 800, 0x3fee800000000000),
        ("IMFell", 2, 1728, 945, 0x3fe8000000000000),
        ("IMFell", 2, 900, 945, 0x3fe1c00000000000),
        ("IMFell", 2, 1200, 800, 0x3fe6c00000000000),
        ("IMFell", 3, 1728, 945, 0x3ff0000000000000),
        ("IMFell", 3, 900, 945, 0x3ff0000000000000),
        ("IMFell", 3, 1200, 800, 0x3ff0000000000000),
        ("IMFell", 4, 1728, 945, 0x3ff0000000000000),
        ("IMFell", 4, 900, 945, 0x3ff0000000000000),
        ("IMFell", 4, 1200, 800, 0x3ff0000000000000),
        ("IMFell", 5, 1728, 945, 0x3ff0000000000000),
        ("IMFell", 5, 900, 945, 0x3fefc00000000000),
        ("IMFell", 5, 1200, 800, 0x3ff0000000000000),
        ("Bebas", 0, 1728, 945, 0x3ff0000000000000),
        ("Bebas", 0, 900, 945, 0x3ff0000000000000),
        ("Bebas", 0, 1200, 800, 0x3ff0000000000000),
        ("Bebas", 1, 1728, 945, 0x3ff0000000000000),
        ("Bebas", 1, 900, 945, 0x3fe9400000000000),
        ("Bebas", 1, 1200, 800, 0x3fef400000000000),
        ("Bebas", 2, 1728, 945, 0x3feb400000000000),
        ("Bebas", 2, 900, 945, 0x3fe3c00000000001),
        ("Bebas", 2, 1200, 800, 0x3fe8400000000000),
        ("Bebas", 3, 1728, 945, 0x3ff0000000000000),
        ("Bebas", 3, 900, 945, 0x3ff0000000000000),
        ("Bebas", 3, 1200, 800, 0x3ff0000000000000),
        ("Bebas", 4, 1728, 945, 0x3ff0000000000000),
        ("Bebas", 4, 900, 945, 0x3ff0000000000000),
        ("Bebas", 4, 1200, 800, 0x3ff0000000000000),
        ("Bebas", 5, 1728, 945, 0x3ff0000000000000),
        ("Bebas", 5, 900, 945, 0x3ff0000000000000),
        ("Bebas", 5, 1200, 800, 0x3ff0000000000000),
        ("CourierPrime", 0, 1728, 945, 0x3ff0000000000000),
        ("CourierPrime", 0, 900, 945, 0x3ff0000000000000),
        ("CourierPrime", 0, 1200, 800, 0x3ff0000000000000),
        ("CourierPrime", 1, 1728, 945, 0x3fedc00000000001),
        ("CourierPrime", 1, 900, 945, 0x3fe5800000000001),
        ("CourierPrime", 1, 1200, 800, 0x3feb400000000000),
        ("CourierPrime", 2, 1728, 945, 0x3fe7c00000000001),
        ("CourierPrime", 2, 900, 945, 0x3fe0800000000000),
        ("CourierPrime", 2, 1200, 800, 0x3fe4400000000000),
        ("CourierPrime", 3, 1728, 945, 0x3ff0000000000000),
        ("CourierPrime", 3, 900, 945, 0x3ff0000000000000),
        ("CourierPrime", 3, 1200, 800, 0x3ff0000000000000),
        ("CourierPrime", 4, 1728, 945, 0x3ff0000000000000),
        ("CourierPrime", 4, 900, 945, 0x3ff0000000000000),
        ("CourierPrime", 4, 1200, 800, 0x3ff0000000000000),
        ("CourierPrime", 5, 1728, 945, 0x3ff0000000000000),
        ("CourierPrime", 5, 900, 945, 0x3feb400000000000),
        ("CourierPrime", 5, 1200, 800, 0x3ff0000000000000),
        ("Catacombs", 0, 1728, 945, 0x3ff0000000000000),
        ("Catacombs", 0, 900, 945, 0x3ff0000000000000),
        ("Catacombs", 0, 1200, 800, 0x3ff0000000000000),
        ("Catacombs", 1, 1728, 945, 0x3ff0000000000000),
        ("Catacombs", 1, 900, 945, 0x3fe8800000000001),
        ("Catacombs", 1, 1200, 800, 0x3ff0000000000000),
        ("Catacombs", 2, 1728, 945, 0x3feb800000000001),
        ("Catacombs", 2, 900, 945, 0x3fe4000000000000),
        ("Catacombs", 2, 1200, 800, 0x3fe8800000000000),
        ("Catacombs", 3, 1728, 945, 0x3ff0000000000000),
        ("Catacombs", 3, 900, 945, 0x3ff0000000000000),
        ("Catacombs", 3, 1200, 800, 0x3ff0000000000000),
        ("Catacombs", 4, 1728, 945, 0x3ff0000000000000),
        ("Catacombs", 4, 900, 945, 0x3ff0000000000000),
        ("Catacombs", 4, 1200, 800, 0x3ff0000000000000),
        ("Catacombs", 5, 1728, 945, 0x3ff0000000000000),
        ("Catacombs", 5, 900, 945, 0x3ff0000000000000),
        ("Catacombs", 5, 1200, 800, 0x3ff0000000000000),
        ("ShadowsLight", 0, 1728, 945, 0x3ff0000000000000),
        ("ShadowsLight", 0, 900, 945, 0x3ff0000000000000),
        ("ShadowsLight", 0, 1200, 800, 0x3ff0000000000000),
        ("ShadowsLight", 1, 1728, 945, 0x3ff0000000000000),
        ("ShadowsLight", 1, 900, 945, 0x3fe9800000000000),
        ("ShadowsLight", 1, 1200, 800, 0x3fef000000000000),
        ("ShadowsLight", 2, 1728, 945, 0x3fe9800000000000),
        ("ShadowsLight", 2, 900, 945, 0x3fe2c00000000000),
        ("ShadowsLight", 2, 1200, 800, 0x3fe7800000000000),
        ("ShadowsLight", 3, 1728, 945, 0x3ff0000000000000),
        ("ShadowsLight", 3, 900, 945, 0x3ff0000000000000),
        ("ShadowsLight", 3, 1200, 800, 0x3ff0000000000000),
        ("ShadowsLight", 4, 1728, 945, 0x3ff0000000000000),
        ("ShadowsLight", 4, 900, 945, 0x3ff0000000000000),
        ("ShadowsLight", 4, 1200, 800, 0x3ff0000000000000),
        ("ShadowsLight", 5, 1728, 945, 0x3ff0000000000000),
        ("ShadowsLight", 5, 900, 945, 0x3ff0000000000000),
        ("ShadowsLight", 5, 1200, 800, 0x3ff0000000000000),
    ]

    @Test func linesWithoutAnOversizedWordKeepTheirBaselineRatio() {
        for entry in Self.baseline {
            let size = CGSize(width: entry.width, height: entry.height)
            let line = Self.line(Self.baselineLines[entry.line])
            let recipe = LongLineFitTests.recipe(font: entry.font)
            for pass in 0..<2 {
                let ratio = ComposedStyle.fittedEmRatio(line: line, index: 0, recipe: recipe, size: size, measurer: CoreTextMeasurer())
                #expect(Double(ratio).bitPattern == entry.bits, "\(entry.font) 第 \(entry.line) 句 \(size) 第 \(pass) 次：\(ratio)")
            }
        }
    }

    // MARK: ② 霓虹描邊隨該句 em

    /// 改版前的整幀常數：未縮、sizeScale＝1 的句子必須相同
    @Test func anUnshrunkLineKeepsTheStrokeItHadBefore() {
        let size = Self.wide
        let before = size.height * ComposedStyle.emRatio * ComposedStyle.strokeRatio
        let frame = Self.plan(LongLineFitTests.short, font: "Bebas", size: size, fx1: "neonstroke", fx2: "none")
        #expect(!frame.glyphs.isEmpty && frame.glyphs.allSatisfy { $0.stroke == before })
    }

    @Test func aShrunkLineStrokesWithItsShrunkEm() throws {
        let size = Self.narrow
        let report = try #require(Self.report(LongLineFitTests.long, size: size, fx1: "neonstroke", fx2: "none"))
        #expect(report.ratio < 1)
        let frame = Self.plan(LongLineFitTests.long, size: size, fx1: "neonstroke", fx2: "none")
        #expect(!frame.glyphs.isEmpty && frame.glyphs.allSatisfy { $0.stroke == report.em * ComposedStyle.strokeRatio })
        #expect(report.em * ComposedStyle.strokeRatio < size.height * ComposedStyle.emRatio * ComposedStyle.strokeRatio)
    }

    @Test(arguments: [("type", "misreg"), ("type", "reflect"), ("type", "weep"), ("type", "ransom"), ("negative", "none")])
    func mainGlyphsKeepTheirStrokeAlongsideOtherEffects(enter: String, fx2: String) {
        let frame = Self.plan(LongLineFitTests.short, font: "Bebas", size: Self.wide, t: 20, enter: enter, fx1: "neonstroke", fx2: fx2)
        #expect(!frame.glyphs.isEmpty && frame.glyphs.allSatisfy { $0.stroke > 0 }, "\(enter)＋\(fx2)")
    }

    @Test func shiftedKeepsTheStroke() {
        let glyph = GlyphDraw(text: "A", face: .displayMedium, fontSize: 40, origin: .zero, opacity: 1, color: .fg, stroke: 2.5)
        #expect(glyph.shifted(dx: 3, dy: 4, opacity: 0.5, color: .bg).stroke == 2.5)
    }

    @Test func ghostsAreNeverStrokedAndDifferentStrokesSplitRuns() {
        func glyph(_ stroke: CGFloat) -> GlyphDraw { GlyphDraw(text: "A", face: .displayMedium, fontSize: 40, origin: .zero, opacity: 1, color: .fg, stroke: stroke) }
        let glyphs = [glyph(4), glyph(4), glyph(3)]
        #expect(LyricsFXCanvas.runs(of: glyphs, stroking: true).map(\.stroke) == [4, 3])
        #expect(LyricsFXCanvas.runs(of: glyphs, stroking: false).map(\.stroke) == [0])
    }

    // MARK: ③ Anton 字級

    @Test func antonIsDrawnAtThePrototypesLargerSize() throws {
        guard case .font(let anton)? = LyricsFXCatalog.component("Anton")?.payload else { Issue.record("Anton 不是字型"); return }
        #expect(abs(anton.sizeScale - 0.15 / 0.12) < 1e-9)
    }

    @Test func anUnshrunkAntonLineUsesThePrototypeEm() throws {
        let report = try #require(Self.report(LongLineFitTests.short, font: "Anton", size: Self.wide))
        #expect(report.ratio == 1)
        #expect(abs(report.em - Self.wide.height * 0.15) < 1e-9)
    }

    /// 放大後原本放得下的短句在窄視窗會放不下 → 照 I-45 縮字，縮完主字形都在安全區內（原 `aShortLineKeepsItsSizeExactly` 的 Anton 窄視窗案例移到這裡）
    @Test func aShortAntonLineShrinksInANarrowWindowAndStaysInside() throws {
        let report = try #require(Self.report(LongLineFitTests.short, font: "Anton", size: Self.narrow))
        #expect(report.ratio < 1 && !report.breaksLongWords)
        let frame = Self.plan(LongLineFitTests.short, font: "Anton", size: Self.narrow)
        let margin = Self.narrow.height * ComposedStyle.fitMargin
        let y = B2BatchFourT7FixTests.inkSpan(frame)
        #expect(!frame.glyphs.isEmpty && y.top >= margin && y.bottom <= Self.narrow.height - margin, "上下 \(y)")
    }

    @Test func aShrunkAntonNeonLineStrokesWithTheShrunkEm() throws {
        let report = try #require(Self.report(LongLineFitTests.long, font: "Anton", size: Self.narrow, fx1: "neonstroke", fx2: "none"))
        #expect(report.ratio < 1)
        let frame = Self.plan(LongLineFitTests.long, font: "Anton", size: Self.narrow, fx1: "neonstroke", fx2: "none")
        #expect(!frame.glyphs.isEmpty && frame.glyphs.allSatisfy { $0.stroke == report.em * ComposedStyle.strokeRatio })
    }

    /// Anton 放大後點陣偏離向量超出 I-46 門檻（計劃 §9.2–9.3）：研究出尺寸策略前，Anton 的字一律走合併外框
    @Test func antonIsDrawnAsOutlinesWhileOtherFontsKeepTheRasterCache() {
        guard case .font(let anton)? = LyricsFXCatalog.component("Anton")?.payload else { Issue.record("Anton 不是字型"); return }
        #expect(!anton.rasterizes)
        for id in ["Marker", "RockSalt", "Bebas", "CourierPrime", "Catacombs", "IMFell"] {
            guard case .font(let face)? = LyricsFXCatalog.component(id)?.payload else { Issue.record("\(id) 不是字型"); continue }
            #expect(face.rasterizes, "\(id)")
        }
    }

    @Test(arguments: [(20, 1), (20, 5), (10, 1), (10, 5)])
    func aRunWithAnOutlineOnlyGlyphIsDrawnAsTheMergedOutline(level: Int, count: Int) {
        #expect(LyricsFXCanvas.glyphRunStrategy(level: level, count: count, stroke: 0, rasterizes: false) == .vectorMerged)
        #expect(LyricsFXCanvas.glyphRunStrategy(level: level, count: count, stroke: 0, rasterizes: true) != .vectorMerged)
    }
}
