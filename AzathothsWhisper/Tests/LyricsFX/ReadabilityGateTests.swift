import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// 讀得到的檢查 G2／G3（docs/plans/2026-10-20-lyrics-fx-readability-gate.md）：全部 profile × 6 個連播種子 × 三份歌詞
@Suite("Readability gate")
struct ReadabilityGateTests {
    static let profileNames = ReadabilityAudit.singleProfiles.map(\.name)
    /// ⑧ 計劃 §4.6：曲庫實際出現的多列組合（`ReadabilityPolicy.combinations`）；分開列，才能單獨重跑
    static let combinationNames = ReadabilityAudit.combinationProfiles.map(\.name)

    @Test(arguments: profileNames)
    func nothingGoesBlankWhileALineIsSung(name: String) throws {
        try Self.expectNoBlank(name)
    }

    @Test(arguments: profileNames)
    func linesDoNotStayCovered(name: String) throws {
        try Self.expectNotCovered(name)
    }

    @Test(arguments: combinationNames)
    func combinationsDoNotGoBlank(name: String) throws {
        try Self.expectNoBlank(name)
    }

    @Test(arguments: combinationNames)
    func combinationsDoNotStayCovered(name: String) throws {
        try Self.expectNotCovered(name)
    }

    private static func expectNoBlank(_ name: String) throws {
        let profile = try #require(ReadabilityAudit.profiles.first { $0.name == name }?.profile)
        let measurer = CoreTextMeasurer()
        for recipe in ReadabilityAudit.recipes(name, profile) {
            for fixture in ReadabilityAudit.fixtures {
                if let finding = ReadabilityAudit.longestBlank(fixture.timeline, recipe: recipe, measurer: measurer), finding.seconds > ReadabilityAudit.maxBlank + 1e-9 {
                    Issue.record("\(name) \(fixture.name) \(recipe.enter)/\(recipe.exit)/\(recipe.font)：空白 \(finding)")
                }
            }
        }
    }

    private static func expectNotCovered(_ name: String) throws {
        let profile = try #require(ReadabilityAudit.profiles.first { $0.name == name }?.profile)
        let measurer = CoreTextMeasurer()
        for recipe in ReadabilityAudit.recipes(name, profile) where !ReadabilityAudit.coverExemptEnters.contains(recipe.enter) {
            for fixture in ReadabilityAudit.fixtures {
                if let finding = ReadabilityAudit.longestCovered(fixture.timeline, recipe: recipe, measurer: measurer), finding.seconds > ReadabilityAudit.maxCovered + 1e-9 {
                    Issue.record("\(name) \(fixture.name) \(recipe.enter)/\(recipe.exit)/\(recipe.font)/\(recipe.fx1)+\(recipe.fx2)：疊住 \(finding)")
                }
            }
        }
    }
}

// G3 的豁免只限使用者簽字的兩個進場；要加要減都得改 ACCEPTANCE
@Suite("Readability exemptions")
struct ReadabilityExemptionTests {
    @Test func onlyTheSignedSideSlidesAreExemptFromCoverage() {
        #expect(ReadabilityAudit.coverExemptEnters == ["swagger", "slide"])
    }
}

// 量測函式自己的測試（人造情境，跨門檻兩側）
@Suite("Readability audit")
struct ReadabilityAuditTests {
    static func glyph(_ text: String, x: CGFloat, y: CGFloat = 100, opacity: Double = 1) -> GlyphDraw {
        GlyphDraw(text: text, face: .displayRegular, fontSize: 40, origin: CGPoint(x: x, y: y), opacity: opacity, color: .fg)
    }

    static func frame(ghosts: [GlyphDraw] = [], glyphs: [GlyphDraw]) -> FramePlan {
        var plan = FramePlan(palette: .mono)
        plan.ghosts = ghosts
        plan.glyphs = glyphs
        return plan
    }

    @Test func aGlyphJustBelowTheThresholdIsNotInk() {
        #expect(!ReadabilityAudit.isInk(Self.glyph("A", x: 0, opacity: 0.34)))
        #expect(ReadabilityAudit.isInk(Self.glyph("A", x: 0, opacity: 0.35)))
        #expect(!ReadabilityAudit.isInk(Self.glyph(" ", x: 0)))
    }

    @Test func neighboursSideBySideAreNotCovered() {
        let a = Self.glyph("A", x: 100), b = Self.glyph("B", x: 130)
        #expect(ReadabilityAudit.coveredFraction(target: [a, b], screen: Self.frame(glyphs: [a, b]), measurer: CoreTextMeasurer()) == 0)
    }

    @Test func aGlyphLyingOnTopOfAnotherIsCovered() {
        let a = Self.glyph("A", x: 100), b = Self.glyph("B", x: 102)
        #expect(ReadabilityAudit.coveredFraction(target: [a], screen: Self.frame(glyphs: [a, b]), measurer: CoreTextMeasurer()) == 1)
    }

    @Test func aGlyphsOwnShiftedCopyDoesNotCountAsCovering() {
        let a = Self.glyph("A", x: 100)
        let copy = Self.glyph("A", x: 103)
        #expect(ReadabilityAudit.coveredFraction(target: [a], screen: Self.frame(ghosts: [copy], glyphs: [a]), measurer: CoreTextMeasurer()) == 0)
    }

    /// 5 份 0.25 的煙霧副本疊在一起看得見；只有 1 份看不見
    @Test func stackedSmokeCopiesCountAsInk() {
        let copies = (0..<5).map { Self.glyph("A", x: 100 + CGFloat($0), opacity: 0.25) }
        #expect(!ReadabilityAudit.targets(Self.frame(ghosts: copies, glyphs: [])).isEmpty)
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: [Self.glyph("A", x: 100, opacity: 0.25)], glyphs: [])).isEmpty)
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: [Self.glyph("A", x: 100, opacity: 0.25), Self.glyph("A", x: 300, opacity: 0.25)], glyphs: [])).isEmpty)
    }

    /// 連續命中的刻度相加，最後一段再加一個刻度（兩個取樣點之間可能還在持續）
    @Test func longestRunAddsOneStepAsAnUpperBound() {
        let samples: [(hit: Bool, time: Double, step: Double)] = [(false, 0, 0.1), (true, 0.1, 0.1), (true, 0.2, 0.1), (false, 0.3, 0.1), (true, 0.4, 0.1)]
        let run = ReadabilityAudit.longestRun(samples)
        #expect(abs((run?.seconds ?? 0) - 0.3) < 1e-9)
        #expect(run?.at == 0.1)
        #expect(ReadabilityAudit.longestRun([(false, 0, 0.1)]) == nil)
    }

    /// G3：命中之間小於 0.1 s 的空隙算連續（字輪流互相穿過，眼睛看是一直疊著）；空隙到 0.1 s 就斷開
    @Test func shortGapsBridgeIntoOneRun() {
        let step = 0.02
        let pattern = "##..###..##" + "......" + "##"   // 前段空隙 0.04 s 接起來；中間 0.12 s 斷開
        let samples = pattern.enumerated().map { (hit: $1 == "#", time: Double($0) * step, step: step) }
        let run = ReadabilityAudit.longestRun(samples, bridging: ReadabilityAudit.fusionGap)
        // 第一段 0.00–0.20（11 格）＋保守上界一格
        #expect(abs((run?.seconds ?? 0) - 0.24) < 1e-9)
        #expect(run?.at == 0)
        // G2 不接空隙：最長只是 3 格＋一格
        #expect(abs((ReadabilityAudit.longestRun(samples)?.seconds ?? 0) - 0.08) < 1e-9)
    }

    /// 全程固定刻度（0.1 s 會把交疊的閃爍誤連、也會漏掉）
    @Test func samplesAreEvenlySpacedAtTheFineStep() {
        let line = TimedLine(start: 1, end: 3, text: "a", isChorus: false)
        let samples = ReadabilityAudit.samples(line)
        #expect(samples.allSatisfy { $0.step == ReadabilityAudit.step })
        #expect(ReadabilityAudit.step == 0.02)
        #expect(samples.count == Int(((line.revealEnd - line.start) / ReadabilityAudit.step).rounded(.up)))
    }

    /// smoke 進場只畫副本：疊起來看得見、附近又沒有本體的副本群，算一個主字
    @Test func smokeCopiesWithoutABodyBecomeOneTarget() {
        let copies = (0..<5).map { Self.glyph("A", x: 100 + CGFloat($0), opacity: 0.25) }
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: copies, glyphs: [])).count == 1)
        // 有本體時，副本（錯位、分色）不另算
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: copies, glyphs: [Self.glyph("A", x: 100)])).count == 1)
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: [Self.glyph("A", x: 100, opacity: 0.25)], glyphs: [])).isEmpty)
    }

    /// 倒影（上下翻轉的淡副本）不是煙霧：不跟附近的煙霧副本併成一個主字；翻轉的字框不往上翻
    @Test func reflectionsAreNotSmokeAndFlippedBoxesStayInPlace() {
        var mirror = Self.glyph("L", x: 100, y: 180, opacity: 0.04)
        mirror.scaleY = -1
        let smoke = (0..<5).map { Self.glyph("L", x: 103 + CGFloat($0), y: 195, opacity: 0.16) }
        let targets = ReadabilityAudit.targets(Self.frame(ghosts: [mirror] + smoke, glyphs: []))
        #expect(targets.count == 1)
        #expect(targets.first?.scaleY == 1)
        let measurer = CoreTextMeasurer()
        #expect(ReadabilityAudit.box(mirror, measurer: measurer) == ReadabilityAudit.box(Self.glyph("L", x: 100, y: 180), measurer: measurer))
    }

    /// 同一行相鄰的同一個字疊上來，不是自己的副本
    @Test func anotherIdenticalGlyphOnTopStillCovers() {
        let a = Self.glyph("l", x: 100), b = Self.glyph("l", x: 101)
        #expect(ReadabilityAudit.coveredFraction(target: [a], screen: Self.frame(glyphs: [a, b]), measurer: CoreTextMeasurer()) == 1)
    }

    /// 整個畫面裡的自己可能透明度不同（讓位）、位置也略有不同（隨機擺動共用亂數流，別的行在場會改變它）：最近的那一個同字是自己
    @Test func theNearestIdenticalGlyphOnScreenIsItself() {
        let a = Self.glyph("A", x: 100), shifted = Self.glyph("A", x: 107, y: 109, opacity: 0.6)
        #expect(ReadabilityAudit.coveredFraction(target: [a], screen: Self.frame(glyphs: [shifted]), measurer: CoreTextMeasurer()) == 0)
        // 自己之外，再疊上一個同字就算蓋住
        let another = Self.glyph("A", x: 102)
        #expect(ReadabilityAudit.coveredFraction(target: [a], screen: Self.frame(glyphs: [shifted, another]), measurer: CoreTextMeasurer()) == 1)
    }

    @Test func faintGlyphsDoNotCover() {
        let a = Self.glyph("A", x: 100), b = Self.glyph("B", x: 102, opacity: 0.2)
        #expect(ReadabilityAudit.coveredFraction(target: [a], screen: Self.frame(glyphs: [a, b]), measurer: CoreTextMeasurer()) == 0)
    }
}
