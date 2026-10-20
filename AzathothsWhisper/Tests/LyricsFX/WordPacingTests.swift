import Testing

@testable import AzathothsWhisper

// 行內逐字最慢速度（docs/plans/2026-10-19-lyrics-fx-word-pacing.md §3）。歌詞全部是編造的測試句
@Suite("WordPacing")
struct WordPacingTests {
    /// 20 個字母、4 個詞 → 0.08×20 + 0.40×4 = 3.2 s
    private let latin = "Lanterns over the river"

    @Test func longGapIsCappedBySingingSpeed() {
        #expect(abs(WordPacing.revealEnd(text: latin, start: 10, lineEnd: 30) - 13.2) < 1e-9)
    }

    @Test func shortGapKeepsTheLineEnd() {
        #expect(WordPacing.revealEnd(text: latin, start: 10, lineEnd: 11) == 11)
    }

    @Test func zeroOrNegativeGapNeverPrecedesTheStart() {
        #expect(WordPacing.revealEnd(text: latin, start: 10, lineEnd: 10) == 10)
        #expect(WordPacing.revealEnd(text: latin, start: 10, lineEnd: 9) == 10)
    }

    @Test func nonFiniteInputIsLeftUntouched() {
        #expect(WordPacing.revealEnd(text: latin, start: 10, lineEnd: .infinity) == .infinity)
        #expect(WordPacing.revealEnd(text: latin, start: .nan, lineEnd: 30) == 30)
    }

    @Test(arguments: [
        "Café über la rivière",
        "Lanterns, over the river!",
        "Count to 3 and run",
    ])
    func latinLinesWithSpacesArePaced(text: String) {
        #expect(WordPacing.isPaced(text))
    }

    /// 只評估過英文：CJK、韓文、西里爾字母、整行一詞都照舊（計劃 §1 非目標）
    @Test(arguments: [
        "夜明けの鐘",
        "灯火 over the river",
        "바다 위의 등불",
        "Русалка над рекой",
        "Lanterns",
        "",
        "  ",
    ])
    func otherLinesAreNotPaced(text: String) {
        #expect(!WordPacing.isPaced(text))
        #expect(WordPacing.revealEnd(text: text, start: 10, lineEnd: 30) == 30)
    }

    @Test func timedLineDefaultsRevealEndToTheLineEnd() {
        let line = TimedLine(start: 2, end: 6, text: latin, isChorus: false)
        #expect(line.revealEnd == 6)
        #expect(abs(line.words.last!.end - 6) < 1e-9)
    }

    @Test func wordsAreSpreadUpToTheRevealEnd() {
        let line = TimedLine(start: 2, end: 20, text: latin, isChorus: false, revealEnd: 5)
        #expect(line.end == 20)
        #expect(line.words.first!.start == 2)
        #expect(abs(line.words.last!.end - 5) < 1e-9)
    }

    /// 外部時間軸：行仍停到下一行起點，字在唱速上限內出完
    @Test func alignedExternalTimelineIsPaced() throws {
        let music = "Lanterns over the river\nAsh in the wind\nCount the silent bells"
        let lrc = [LRCLine(start: 10, text: "Lanterns over the river"), LRCLine(start: 30, text: "Ash in the wind"), LRCLine(start: 34, text: "Count the silent bells")]
        let timeline = try #require(LRCAligner.align(lyrics: music, lrc: lrc, duration: 100, source: .lrclib))
        let first = timeline.lines[0]
        #expect(first.end == 30)
        #expect(abs(first.revealEnd - 13.2) < 1e-9)
        #expect(abs(first.words.last!.end - 13.2) < 1e-9)
        // 12 個字母、4 個詞 → 2.56 s，比到下一行的 4 s 短
        #expect(abs(timeline.lines[1].revealEnd - 32.56) < 1e-9)
    }

    /// 存檔讀回的路徑（LRCAligner.timeline(stored:)）也要套用：與即時對齊同一個出口
    @Test func storedExternalTimelineIsPaced() throws {
        let music = "Lanterns over the river\nAsh in the wind\nCount the silent bells"
        let stored = [TimingRecord.LineStart(index: 0, start: 10), TimingRecord.LineStart(index: 1, start: 30), TimingRecord.LineStart(index: 2, start: 34)]
        let timeline = try #require(LRCAligner.timeline(lyrics: music, stored: stored, duration: 100, source: .lrclib))
        #expect(timeline.lines[0].end == 30)
        #expect(abs(timeline.lines[0].revealEnd - 13.2) < 1e-9)
    }

    @Test func embeddedLRCIsPaced() throws {
        let timeline = try #require(LyricsTimelineBuilder.build(lyrics: "[00:05.00]Lanterns over the river\n[00:30.00]Ash in the wind", duration: 100))
        #expect(timeline.lines[0].end == 30)
        #expect(abs(timeline.lines[0].revealEnd - 8.2) < 1e-9)
    }

    /// 估算路徑不套用（行長本身就按字數估）
    @Test func estimatedTimelineIsNotPaced() throws {
        let timeline = try #require(LyricsTimelineEstimator.estimate(lyrics: "Lanterns over the river\nAsh in the wind", duration: 200))
        for line in timeline.lines { #expect(line.revealEnd == line.end) }
    }
}
