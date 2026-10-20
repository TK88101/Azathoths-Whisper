import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// 讀得到的檢查 G2／G3（docs/plans/2026-10-20-lyrics-fx-readability-gate.md）：全部 profile × 6 個連播種子 × 三份歌詞
@Suite("Readability gate")
struct ReadabilityGateTests {
    static let profileNames = ReadabilityAudit.profiles.map(\.name)

    @Test(arguments: profileNames)
    func nothingGoesBlankWhileALineIsSung(name: String) throws {
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

    @Test(arguments: profileNames)
    func linesDoNotStayCovered(name: String) throws {
        let profile = try #require(ReadabilityAudit.profiles.first { $0.name == name }?.profile)
        let measurer = CoreTextMeasurer()
        for recipe in ReadabilityAudit.recipes(name, profile) {
            for fixture in ReadabilityAudit.fixtures {
                if let finding = ReadabilityAudit.longestCovered(fixture.timeline, recipe: recipe, measurer: measurer), finding.seconds > ReadabilityAudit.maxCovered + 1e-9 {
                    Issue.record("\(name) \(fixture.name) \(recipe.enter)/\(recipe.exit)/\(recipe.font)/\(recipe.fx1)+\(recipe.fx2)：疊住 \(finding)")
                }
            }
        }
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

    /// smoke 進場只畫副本：疊起來看得見、附近又沒有本體的副本群，算一個主字
    @Test func smokeCopiesWithoutABodyBecomeOneTarget() {
        let copies = (0..<5).map { Self.glyph("A", x: 100 + CGFloat($0), opacity: 0.25) }
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: copies, glyphs: [])).count == 1)
        // 有本體時，副本（錯位、分色）不另算
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: copies, glyphs: [Self.glyph("A", x: 100)])).count == 1)
        #expect(ReadabilityAudit.targets(Self.frame(ghosts: [Self.glyph("A", x: 100, opacity: 0.25)], glyphs: [])).isEmpty)
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
