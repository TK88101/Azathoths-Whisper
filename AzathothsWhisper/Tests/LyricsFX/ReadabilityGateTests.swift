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
        #expect(ReadabilityAudit.hasInkFromCopies(copies))
        #expect(!ReadabilityAudit.hasInkFromCopies([Self.glyph("A", x: 100, opacity: 0.25)]))
        #expect(!ReadabilityAudit.hasInkFromCopies([Self.glyph("A", x: 100, opacity: 0.25), Self.glyph("A", x: 300, opacity: 0.25)]))
    }

    @Test func faintGlyphsDoNotCover() {
        let a = Self.glyph("A", x: 100), b = Self.glyph("B", x: 102, opacity: 0.2)
        #expect(ReadabilityAudit.coveredFraction(target: [a], screen: Self.frame(glyphs: [a, b]), measurer: CoreTextMeasurer()) == 0)
    }
}
