import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

/// 每個字寬＝0.5 × 字級：測試只看版面規則，不看真字型
struct FixedWidthMeasurer: TextMeasuring {
    func advances(of text: String, fontSize: CGFloat, weight: GlyphWeight) -> [CGFloat] {
        (0...text.count).map { CGFloat($0) * fontSize * 0.5 }
    }
}

// A2 計劃 §3.4：mono 的 plan。歌詞為編造句
@Suite("LyricsFXFrame mono plan")
struct LyricsFXFrameTests {
    static let size = CGSize(width: 1000, height: 600)
    static let measurer = FixedWidthMeasurer()

    static func line(_ start: Double, _ end: Double, _ text: String) -> TimedLine {
        TimedLine(start: start, end: end, text: text, isChorus: false)
    }

    /// 1–4 s「Paper boats at dawn」、4–8 s 間奏（空時間點已被 builder 吃掉）、10–14 s「Quiet harbor」
    static let timeline = LyricsTimeline(
        lines: [line(1, 4, "Paper boats at dawn"), line(10, 14, "Quiet harbor")],
        source: .embeddedLRC, duration: 60
    )

    private func plan(_ t: Double?, _ motion: LyricsFXMotion = .full, timeline: LyricsTimeline? = timeline, size: CGSize = size) -> FramePlan {
        LyricsFXFrame.plan(timeline: timeline, time: t, size: size, motion: motion, measurer: Self.measurer)
    }

    private func text(_ glyphs: [GlyphDraw]) -> String {
        glyphs.map(\.text).joined()
    }

    @Test func nothingWithoutATimelineATimeOrRoom() {
        #expect(plan(2, timeline: nil).glyphs.isEmpty)
        #expect(plan(nil).glyphs.isEmpty)
        #expect(plan(2, size: CGSize(width: 100, height: 600)).glyphs.isEmpty)
    }

    @Test func farBeforeTheFirstLineThereIsNothing() {
        #expect(plan(-1.5).glyphs.isEmpty)
    }

    @Test func withinTwoSecondsOfTheFirstLineOnlyItsPreviewShows() {
        let glyphs = plan(-0.5).glyphs
        #expect(text(glyphs) == "Paperboatsatdawn")
        #expect(glyphs.allSatisfy { $0.tone == .secondary && $0.opacity == LyricsFXFrame.Mono.previewOpacity })
    }

    @Test func theCurrentLineHasOneGlyphPerNonBlankCharacterAndThePreviewFollows() throws {
        let glyphs = plan(3).glyphs
        let current = glyphs.filter { $0.tone == .primary }
        let preview = glyphs.filter { $0.tone == .secondary }
        #expect(text(current) == "Paperboatsatdawn")
        #expect(text(preview) == "Quietharbor")
        #expect(current.allSatisfy { $0.opacity == 1 })
        let first = try #require(current.first)
        let lowest = try #require(current.map(\.origin.y).max())
        #expect(preview.allSatisfy { $0.fontSize < first.fontSize })
        #expect(preview.allSatisfy { $0.origin.y > lowest })
    }

    @Test func theCurrentLineFadesInAndRisesMonotonically() throws {
        let samples = stride(from: 1.0, through: 1.4, by: 0.05).compactMap { plan($0).glyphs.first { $0.tone == .primary } }
        try #require(samples.count == 9)
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later.opacity >= earlier.opacity)
            #expect(later.origin.y <= earlier.origin.y)
        }
        #expect(samples.first?.opacity == 0)
        #expect(samples.last?.opacity == 1)
    }

    /// 精確例（Codex R1 #10）：4–8 s 無字、8–10 s 只有下一行的預覽
    @Test func theInterludeRespectsTheLineEnd() {
        let fading = plan(4.1).glyphs
        #expect(text(fading) == "Paperboatsatdawn", "剛結束的行還在淡出")
        #expect(fading.allSatisfy { $0.opacity < 1 })
        #expect(plan(5).glyphs.isEmpty)
        #expect(plan(7.9).glyphs.isEmpty)
        let preview = plan(8.5).glyphs
        #expect(text(preview) == "Quietharbor")
        #expect(preview.allSatisfy { $0.tone == .secondary })
    }

    @Test func atALineChangeTheOldLineFadesOutWhileTheNewOneFadesIn() {
        let back = LyricsTimeline(lines: [Self.line(1, 4, "Paper boats"), Self.line(4, 8, "Quiet harbor")], source: .embeddedLRC, duration: 60)
        let glyphs = plan(4.1, timeline: back).glyphs
        let old = glyphs.filter { $0.text == "P" }
        let new = glyphs.filter { $0.text == "Q" && $0.tone == .primary }
        #expect(old.count == 1 && new.count == 1)
        #expect(old.allSatisfy { $0.opacity < 1 && $0.opacity > 0 })
        #expect(new.allSatisfy { $0.opacity < 1 && $0.opacity > 0 })
        #expect(plan(4.4, timeline: back).glyphs.filter { $0.text == "P" }.isEmpty, "淡出結束就不畫")
    }

    @Test func afterTheLastLineAndItsExitThereIsNothing() {
        #expect(plan(14 + LyricsFXFrame.Mono.exit + 0.01).glyphs.isEmpty)
    }

    @Test func everyGlyphStaysOnTheCanvas() {
        let long = LyricsTimeline(
            lines: [Self.line(0, 5, String(repeating: "lanterns drift ", count: 30)), Self.line(5, 9, String(repeating: "ash ", count: 40))],
            source: .estimated, duration: 9
        )
        for t in stride(from: 0.0, through: 9, by: 0.25) {
            for glyph in plan(t, timeline: long).glyphs {
                #expect(glyph.origin.x >= 0 && glyph.origin.x <= Self.size.width)
                #expect(glyph.origin.y >= 0 && glyph.origin.y <= Self.size.height)
                #expect((0...1).contains(glyph.opacity))
            }
        }
    }

    @Test func reducedMotionIsStaticAndHasNoFadingLine() {
        let entering = plan(1.05, .reduced).glyphs.filter { $0.tone == .primary }
        #expect(entering.allSatisfy { $0.opacity == 1 })
        #expect(entering.map(\.origin.y) == plan(3, .reduced).glyphs.filter { $0.tone == .primary }.map(\.origin.y))
        #expect(plan(4.1, .reduced).glyphs.isEmpty)
    }

    @Test func theSameInputGivesTheSamePlan() {
        #expect(plan(2.345) == plan(2.345))
    }

    @Test func blankLinesNeverBecomeThePreview() {
        let withBlank = LyricsTimeline(lines: [Self.line(1, 4, "Paper boats"), Self.line(4, 6, "   "), Self.line(6, 9, "Quiet harbor")], source: .estimated, duration: 9)
        #expect(text(plan(2, timeline: withBlank).glyphs.filter { $0.tone == .secondary }) == "Quietharbor")
    }

    @Test func theCurrentLineText() {
        #expect(LyricsFXFrame.currentLineText(timeline: Self.timeline, time: 2) == "Paper boats at dawn")
        #expect(LyricsFXFrame.currentLineText(timeline: Self.timeline, time: 5) == nil)
        #expect(LyricsFXFrame.currentLineText(timeline: nil, time: 2) == nil)
    }
}

@Suite("Mono layout")
struct MonoLayoutTests {
    private let measurer = FixedWidthMeasurer()

    @Test func wrapsAtWordsWithinTheWidth() {
        // 字級 20 → 每字 10 pt；寬 100 放得下 10 字
        let rows = MonoLayout.rows(of: "paper boats at dawn", fontSize: 20, weight: .medium, maxWidth: 100, maxRows: 4, measurer: measurer)
        #expect(rows == ["paper", "boats at", "dawn"])
    }

    @Test func aWordWiderThanTheLineBreaksByCharacter() {
        let rows = MonoLayout.rows(of: "abcdefghijklmn", fontSize: 20, weight: .medium, maxWidth: 100, maxRows: 4, measurer: measurer)
        #expect(rows == ["abcdefghij", "klmn"])
    }

    @Test func cjkBreaksAnywhere() {
        let rows = MonoLayout.rows(of: "灯籠が川を流れてゆく夜", fontSize: 20, weight: .medium, maxWidth: 50, maxRows: 4, measurer: measurer)
        #expect(rows == ["灯籠が川を", "流れてゆく", "夜"])
    }

    @Test func extraRowsAreCut() {
        let rows = MonoLayout.rows(of: "aa bb cc dd ee", fontSize: 20, weight: .medium, maxWidth: 20, maxRows: 2, measurer: measurer)
        #expect(rows == ["aa", "bb"])
    }

    @Test func theFontSizeIsClamped() {
        #expect(MonoLayout.currentFontSize(width: 100) == 24)
        #expect(MonoLayout.currentFontSize(width: 5000) == 54)
        #expect(MonoLayout.currentFontSize(width: 800) == 800 * 0.052)
    }
}

@Suite("LyricsFX schedule")
struct LyricsFXScheduleTests {
    @Test(arguments: [
        (false, true, false, LyricsFXSchedule.none),
        (true, false, false, .none),
        (true, true, false, .animation),
        (true, true, true, .periodic),
    ])
    func resolves(isVisible: Bool, isRunning: Bool, reduceMotion: Bool, expected: LyricsFXSchedule) {
        #expect(LyricsFXSchedule.resolve(isVisible: isVisible, isRunning: isRunning, reduceMotion: reduceMotion) == expected)
    }
}
