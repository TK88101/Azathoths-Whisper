import CoreGraphics
import Testing

@testable import AzathothsWhisper

// ⑤ 中日韓字型計劃 §4.4：中日文字之間不加詞距、可在字間斷行、最小禁則與違例退路；組合與素面共用。
// 固定字寬量測（每字 0.5 em），歌詞為編造句
@Suite("CJK layout")
struct CJKLayoutTests {
    static let measurer = FixedWidthMeasurer()
    static let recipe = ComposedRecipe(
        font: "Grotesk", backdrop: "void", enter: "lash", exit: "fade", fx1: "none", fx2: "none", palette: "ice", seed: 7,
        profile: SongProfile(axes: [.aggression: 0.5], tags: [])
    )

    private func report(_ text: String, size: CGSize = CGSize(width: 900, height: 560)) throws -> ComposedStyle.FitReport {
        try #require(ComposedStyle.fitReport(line: TimedLine(start: 0, end: 4, text: text, isChorus: false), index: 0, recipe: Self.recipe, size: size, measurer: Self.measurer))
    }

    private func rows(_ report: ComposedStyle.FitReport) -> [String] {
        let count = (report.glyphs.map(\.row).max() ?? -1) + 1
        return (0..<count).map { row in report.glyphs.filter { $0.row == row }.map(\.text).joined() }
    }

    @Test func aJapaneseLineWithoutSpacesHasNoWordGaps() throws {
        let fit = try report("夜明けの灯籠")
        #expect(fit.rowWidths.count == 1)
        #expect(abs(fit.rowWidths[0] - fit.metrics.map(\.width).reduce(0, +)) < 0.001)
    }

    @Test func spacesBetweenWordsKeepTheWordGap() throws {
        let fit = try report("夜明け 灯籠")
        let total = fit.metrics.map(\.width).reduce(0, +)
        #expect(abs(fit.rowWidths[0] - total - ComposedStyle.wordGap * fit.em) < 0.001)
    }

    @Test func aLongJapaneseRunBreaksBetweenCharactersInsteadOfShrinking() throws {
        let text = "灯籠が川をゆっくりと流れてゆく夜明けの静かな港で 鐘が鳴る"
        let fit = try report(text, size: CGSize(width: 480, height: 400))
        #expect(fit.ratio == 1)
        #expect(!fit.breaksLongWords)
        #expect(fit.rowWidths.count > 1)
        // 第一個詞（空格前）被拆到兩列以上：在字間斷，不是整詞搬到下一列
        let firstWordRows = Set(fit.glyphs.filter { $0.wordIndex == 0 }.map(\.row))
        #expect(firstWordRows.count > 1)
    }

    @Test func breakingKeepsEachCharacterInItsTimedWord() throws {
        let text = "灯籠が川をゆっくりと流れてゆく夜明けの静かな港で 鐘が鳴る"
        let fit = try report(text, size: CGSize(width: 480, height: 400))
        let words = TimedLine(start: 0, end: 4, text: text, isChorus: false).words
        let expected = words.enumerated().flatMap { index, word in Array(repeating: index, count: word.text.count) }
        #expect(fit.glyphs.map(\.wordIndex) == expected)
    }

    @Test(arguments: [300, 340, 380, 420, 460, 500, 560, 620])
    func closingMarksNeverStartARowAndOpeningMarksNeverEndOne(width: Int) throws {
        let fit = try report("「灯籠」が、川を流れる。『夜明け』の港で、鐘が鳴る。（静かに）、また明日。", size: CGSize(width: CGFloat(width), height: 400))
        for row in rows(fit) {
            #expect(!CJKLineBreak.closing.contains(row.first!), "列首：\(row)")
            #expect(!CJKLineBreak.opening.contains(row.last!), "列尾：\(row)")
        }
    }

    @Test func theNarrowestWidthNeverProducesAnEmptyRow() throws {
        let fit = try report("。。。「「「灯", size: CGSize(width: 90, height: 400))
        #expect(fit.rowWidths.allSatisfy { $0 > 0 })
        #expect(fit.glyphs.count == 7)
    }

    @Test func aLatinWordInsideAJapaneseLineIsNotSplit() throws {
        let fit = try report("灯籠灯籠灯籠lanternslanterns灯籠灯籠灯籠", size: CGSize(width: 560, height: 400))
        let latin = fit.glyphs.filter { $0.text.first!.isASCII }
        #expect(Set(latin.map(\.row)).count == 1)
    }

    // MARK: 素面

    private func monoRows(_ text: String, width: CGFloat) -> [String] {
        MonoLayout.rows(of: text, fontSize: 30, face: .displayMedium, maxWidth: width, maxRows: 20, measurer: Self.measurer)
    }

    @Test func monoFillsTheRowBeforeBreakingAJapaneseRun() {
        // 每字 15 pt、列寬 150：第一列要滿 10 字，而不是把空格後的整段搬到下一列
        let rows = monoRows("夜明け 灯籠が川をゆっくり流れる", width: 150)
        #expect(rows.first?.count == 10)
    }

    @Test(arguments: [90, 120, 150, 180, 210])
    func monoRespectsTheSameLineBreakingRules(width: Int) {
        for row in monoRows("「灯籠」が、川を流れる。『夜明け』の港で、鐘が鳴る。", width: CGFloat(width)) {
            #expect(!CJKLineBreak.closing.contains(row.first!), "列首：\(row)")
            #expect(!CJKLineBreak.opening.contains(row.last!), "列尾：\(row)")
        }
    }
}
