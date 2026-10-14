import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// 批 4 T7 回饋修正（docs/plans/2026-10-14-lyrics-fx-b2-batch4-t7-fixes.md）：Rock Salt 出框、拿掉雨絲、暈開減量、倒影調淡。
// 歌詞為編造句
@MainActor
@Suite("B2 batch 4 T7 fixes")
struct B2BatchFourT7FixTests {
    /// 內建螢幕上 app 視窗的歌詞區（約 1728×945 點）
    static let size = CGSize(width: 1728, height: 945)
    static let line = "Lanterns over water, salt along the rope, gulls above the ferry, bells across the bay, and paper boats beside the pier tonight"
    static let timeline = LyricsTimeline(lines: [TimedLine(start: 2, end: 30, text: line, isChorus: false)], source: .embeddedLRC, duration: 60)
    static let profile = SongProfile(axes: [.theatrical: 0.9, .aggression: 0.6], tags: [.emo])

    private func plan(font: String, _ t: Double = 29.5, fx1: String = "none") -> FramePlan {
        let recipe = ComposedRecipe(font: font, backdrop: "void", enter: "fadeUp", exit: "sink", fx1: fx1, fx2: "none", palette: "revenge", seed: 3, profile: Self.profile)
        return LyricsFXFrame.plan(timeline: Self.timeline, time: t, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: CoreTextMeasurer())
    }

    /// 每個主字形實際墨跡的上下緣：真實字形外框套上繪製端同一個仿射變換（含旋轉、scaleX／Y）
    static func inkSpan(_ frame: FramePlan) -> (top: CGFloat, bottom: CGFloat) {
        let paths = GlyphPathCache()
        var top = CGFloat.infinity, bottom = -CGFloat.infinity
        for glyph in frame.glyphs {
            let entry = paths.entry(for: glyph)
            let box = entry.path.boundingBoxOfPath.applying(LyricsFXCanvas.transform(for: glyph, entry: entry))
            top = min(top, box.minY)
            bottom = max(bottom, box.maxY)
        }
        return (top, bottom)
    }

    @Test func rockSaltIsDrawnAtThePrototypesSmallerSizeAndOtherFontsAreNot() throws {
        let rockSalt = try #require(LyricsFXCatalog.component("RockSalt"))
        guard case .font(let face) = rockSalt.payload else { Issue.record("RockSalt 不是字型"); return }
        #expect(abs(face.sizeScale - 0.085 / 0.12) < 1e-9)
        for id in ["IMFell", "ShadowsLight", "CourierPrime", "Anton"] {
            guard case .font(let other)? = LyricsFXCatalog.component(id)?.payload else { Issue.record("\(id) 不是字型"); continue }
            #expect(other.sizeScale == 1, "\(id)")
        }
    }

    /// 使用者 T7：「字體被砍掉了、沒有顯示全」——長句折行後，Rock Salt 的每個字都要完整落在歌詞區內、且至少兩列
    @Test func aLongRockSaltLineStaysInsideTheLyricsArea() {
        let frame = plan(font: "RockSalt")
        let span = Self.inkSpan(frame)
        let margin = Self.size.height * ComposedStyle.fitMargin
        #expect(span.top >= margin && span.bottom <= Self.size.height - margin, "墨跡 \(span.top)…\(span.bottom)／高 \(Self.size.height)")
        // 以實際列高分組（em 已乘 sizeScale），兩列的字至少差一列高的一半
        let rowHeight = Self.size.height * ComposedStyle.emRatio * (0.085 / 0.12) * ComposedStyle.lineHeight
        let ys = frame.glyphs.map(\.origin.y)
        #expect((ys.max() ?? 0) - (ys.min() ?? 0) >= rowHeight * 0.5)
    }

    /// 使用者 T7：「雨絲不要了」（三團候選不含 rain 由重產的簽字對照檔＋`B2BatchFourSignedFixtureTests` 把關）
    @Test func rainIsGoneFromTheCatalog() {
        #expect(LyricsFXCatalog.component("rain") == nil)
    }

    /// 使用者 T7：「層數減少一些，不要暈開那麼大」——兩份副本、最遠 0.12 字級
    @Test func weepLeavesTwoCopiesReachingAtMostTwelveHundredthsOfTheFontSize() {
        #expect(ComposedStyle.weepCopies == 2)
        let frame = plan(font: "CourierPrime", fx1: "weep")
        // 長句的最後幾個字剛出現、還沒開始暈開，所以只驗上限；「每字恰兩份」由 B2BatchFourEffectTests 的短句驗
        #expect(!frame.ghosts.isEmpty && frame.ghosts.count <= frame.glyphs.count * 2)
        let deepest = frame.glyphs.map { glyph in
            frame.ghosts.filter { $0.text == glyph.text && abs($0.origin.x - glyph.origin.x) < 1e-6 && $0.origin.y > glyph.origin.y }
                .map { ($0.origin.y - glyph.origin.y) / glyph.fontSize }
                .filter { $0 <= 0.5 }
                .max() ?? 0
        }
        #expect(deepest.allSatisfy { $0 <= 0.12 + 1e-9 } && deepest.contains { abs($0 - 0.12) < 1e-9 })
    }

    /// 使用者 T7：「讓這個倒影淡一些」→ 0.08，看過後「再淺一些」→ 0.04（所有用倒影的團一起，使用者選 A）
    @Test func reflectionIsAQuarterAsStrongAsBefore() {
        let frame = plan(font: "CourierPrime", 5.5, fx1: "reflect")
        let mirrored = frame.ghosts.filter { $0.scaleY < 0 }
        #expect(!mirrored.isEmpty && mirrored.allSatisfy { $0.opacity <= 0.04 + 1e-9 })
        #expect(mirrored.contains { $0.opacity > 0.035 })
    }
}

// T7 目視第 2 項（計劃 §2.6）：一句折行後太高才縮字，放得下的完全不變。歌詞為編造句
@MainActor
@Suite("B2 batch 4 T7 long-line fit")
struct LongLineFitTests {
    static let wide = CGSize(width: 1728, height: 945)
    static let narrow = CGSize(width: 900, height: 945)
    static let short = "Paper boats beside the pier tonight"
    static let long = B2BatchFourT7FixTests.line
    /// 207 字元級的極端長句
    static let extreme = Array(repeating: "lanterns over the water and the rope", count: 6).joined(separator: ", ")
    static let profile = SongProfile(axes: [.theatrical: 0.9, .aggression: 0.9], tags: [.emo])

    static func recipe(font: String, enter: String = "type", fx1: String = "jitter", fx2: String = "reflect") -> ComposedRecipe {
        ComposedRecipe(font: font, backdrop: "void", enter: enter, exit: "cut", fx1: fx1, fx2: fx2, palette: "revenge", seed: 3, profile: profile)
    }

    static func ratio(_ text: String, font: String, size: CGSize, enter: String = "type") -> CGFloat {
        ComposedStyle.fittedEmRatio(line: TimedLine(start: 2, end: 40, text: text, isChorus: false), index: 0,
                                    recipe: recipe(font: font, enter: enter), size: size, measurer: CoreTextMeasurer())
    }

    @Test(arguments: ["Marker", "RockSalt", "Anton", "Bebas", "CourierPrime"])
    func aShortLineKeepsItsSizeExactly(font: String) {
        #expect(Self.ratio(Self.short, font: font, size: Self.wide) == 1)
        #expect(Self.ratio(Self.short, font: font, size: Self.narrow) == 1)
    }

    /// 使用者 T7：The Used（Permanent Marker、整行大寫）「歌詞有超出顯示範圍的問題」
    @Test(arguments: ["Marker", "RockSalt", "IMFell"], [CGSize(width: 1728, height: 945), CGSize(width: 900, height: 945)])
    func aLongLineShrinksUntilEveryMainGlyphIsInside(font: String, size: CGSize) {
        let timeline = LyricsTimeline(lines: [TimedLine(start: 2, end: 40, text: Self.long, isChorus: false)], source: .embeddedLRC, duration: 60)
        let margin = size.height * ComposedStyle.fitMargin
        for t in [30.0, 33.3, 37.7] {
            let frame = LyricsFXFrame.plan(timeline: timeline, time: t, size: size, motion: .full, recipe: .composed(Self.recipe(font: font)), measurer: CoreTextMeasurer())
            let span = B2BatchFourT7FixTests.inkSpan(frame)
            #expect(!frame.glyphs.isEmpty && span.top >= margin && span.bottom <= size.height - margin, "\(font) \(size) t=\(t) 墨跡 \(span.top)…\(span.bottom)")
        }
    }

    @Test func theUsedsLongMarkerLineIsTheOneThatShrinks() {
        #expect(Self.ratio(Self.long, font: "Marker", size: Self.wide) < 1)
        #expect(Self.ratio(Self.long, font: "Marker", size: Self.narrow) < Self.ratio(Self.long, font: "Marker", size: Self.wide))
    }

    @Test func anExtremeLineStopsAtHalfSize() {
        #expect(Self.ratio(Self.extreme, font: "Marker", size: Self.narrow) == ComposedStyle.minimumFitRatio)
    }

    /// 判定用的停留上限是從 `HoldTemplate` 抄來的：掃全部模板，任何一個超過就紅（同一語義兩處定義的守門）
    @Test func theFitAllowanceCoversEveryHoldTemplate() {
        let em: CGFloat = 100
        for template in HoldTemplate.allCases {
            for step in 0..<400 {
                for phase in [0.0, 1.3, 3.5, 5.9] {
                    let context = GlyphContext(em: em, width: 1000, height: 600, radius: 550, dir: 1, side: 1, phase: phase, angle: 0, bend: 0)
                    let t = Double(step) * 0.037
                    let hold = template.transform(time: t, context: context)
                    #expect(abs(hold.dy) <= ComposedStyle.holdReach * em + ComposedStyle.holdJitter + 1e-9, "\(template) dy")
                    #expect(abs(hold.rotation) <= ComposedStyle.holdRotation + 1e-9, "\(template) rotation")
                    #expect(hold.scale <= ComposedStyle.holdScale + 1e-9, "\(template) scale")
                }
            }
        }
    }

    /// 實測（T7 第 3 次每幀）：每幀重新二分搜尋讓 Courier 由過變超 → 同一句、同畫布、同配方只算一次
    @Test func aShrunkLineIsWorkedOutOnceAndReused() {
        let line = TimedLine(start: 2, end: 40, text: Self.long + " (cache probe)", isChorus: false)
        let recipe = Self.recipe(font: "Marker")
        let first = ComposedStyle.fittedEmRatio(line: line, index: 7, recipe: recipe, size: Self.narrow, measurer: CoreTextMeasurer())
        #expect(ComposedStyle.cachedFitRatio(line: line, index: 7, recipe: recipe, size: Self.narrow, measurer: CoreTextMeasurer()) == first)
        #expect(first < 1)
    }

    /// 量測器不同（測試替身 vs CoreText）字寬就不同：快取不得互相污染
    @Test func theCacheKeepsMeasurersApart() {
        let line = TimedLine(start: 2, end: 40, text: Self.long + " (measurer probe)", isChorus: false)
        let recipe = Self.recipe(font: "Marker")
        let real = ComposedStyle.fittedEmRatio(line: line, index: 3, recipe: recipe, size: Self.narrow, measurer: CoreTextMeasurer())
        let fake = ComposedStyle.fittedEmRatio(line: line, index: 3, recipe: recipe, size: Self.narrow, measurer: FixedWidthMeasurer())
        #expect(real != fake)
    }

    /// 彈片堆的詞錨點按畫布比例散布、不隨 em 走：縮字救不了，照現狀
    @Test func thePileEntranceIsLeftAlone() {
        #expect(Self.ratio(Self.long, font: "Marker", size: Self.narrow, enter: "slam") == 1)
    }
}
