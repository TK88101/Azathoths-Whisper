import Testing

@testable import AzathothsWhisper

// 層 3 估算（母計劃 §2.4；A1 計劃 §3.4）。歌詞全部是編造的測試句
@Suite("LyricsTimelineEstimator")
struct LyricsTimelineEstimatorTests {
    private let song = """
    [Verse 1]
    Lanterns over the river
    Ash in the wind

    [Chorus]
    Count the silent bells
    Paper boats at dawn
    [Guitar Solo]
    [Verse 2]
    Quiet harbor lights
    """

    @Test func linesAreMonotonicAndInsideTheWindow() throws {
        let timeline = try #require(LyricsTimelineEstimator.estimate(lyrics: song, duration: 200))
        #expect(timeline.source == .estimated)
        #expect(timeline.duration == 200)
        let lines = timeline.lines
        #expect(lines.count == 5)
        #expect(lines.first!.start >= 200 * LyricsTimelineEstimator.leadFraction - 1e-9)
        #expect(lines.last!.end <= 200 * LyricsTimelineEstimator.tailFraction + 1e-9)
        for (a, b) in zip(lines, lines.dropFirst()) {
            #expect(a.start < a.end)
            #expect(a.end <= b.start + 1e-9)
        }
    }

    @Test func sectionTagsAreNotShownAndChorusIsMarked() throws {
        let lines = try #require(LyricsTimelineEstimator.estimate(lyrics: song, duration: 200)).lines
        #expect(lines.map(\.text) == ["Lanterns over the river", "Ash in the wind", "Count the silent bells", "Paper boats at dawn", "Quiet harbor lights"])
        #expect(lines.map(\.isChorus) == [false, false, true, true, false])
    }

    /// 間奏標籤留一段無字空白：比一般段落間隔長
    @Test func interludeLeavesALongerGapThanAParagraphBreak() throws {
        let lines = try #require(LyricsTimelineEstimator.estimate(lyrics: song, duration: 200)).lines
        let paragraphGap = lines[2].start - lines[1].end
        let soloGap = lines[4].start - lines[3].end
        #expect(paragraphGap > 0)
        #expect(soloGap > paragraphGap * 2)
    }

    @Test func longerLinesGetMoreTime() throws {
        let lines = try #require(LyricsTimelineEstimator.estimate(lyrics: "Hi\nA much longer line than the other one\nHi", duration: 120)).lines
        #expect(lines[1].end - lines[1].start > lines[0].end - lines[0].start)
    }

    @Test func shortLinesGetAtLeastTheMinimumDuration() throws {
        let lines = try #require(LyricsTimelineEstimator.estimate(lyrics: "Oh\nA rather long line that takes most of the weight in this song", duration: 30)).lines
        #expect(lines[0].end - lines[0].start >= LyricsTimelineEstimator.minLineDuration - 1e-9)
    }

    /// 下限總和超過時間窗：整體縮放，仍單調且留在窗內
    @Test func tooManyLinesForTheWindowAreScaledDown() throws {
        let text = (1...40).map { "line \($0)" }.joined(separator: "\n")
        let lines = try #require(LyricsTimelineEstimator.estimate(lyrics: text, duration: 20)).lines
        #expect(lines.count == 40)
        #expect(lines.last!.end <= 20 * LyricsTimelineEstimator.tailFraction + 1e-9)
        for (a, b) in zip(lines, lines.dropFirst()) { #expect(a.end <= b.start + 1e-9) }
    }

    @Test func emptyLyricsOrZeroDurationGiveNoTimeline() {
        #expect(LyricsTimelineEstimator.estimate(lyrics: "", duration: 100) == nil)
        #expect(LyricsTimelineEstimator.estimate(lyrics: "[Intro]\n\n", duration: 100) == nil)
        #expect(LyricsTimelineEstimator.estimate(lyrics: "a", duration: 0) == nil)
        #expect(LyricsTimelineEstimator.estimate(lyrics: "a", duration: -1) == nil)
    }

    @Test func wordsSplitByLengthWithinTheLine() throws {
        let line = try #require(LyricsTimelineEstimator.estimate(lyrics: "aa bbbb", duration: 100)?.lines.first)
        #expect(line.words.map(\.text) == ["aa", "bbbb"])
        #expect(line.words.first!.start == line.start)
        #expect(abs(line.words.last!.end - line.end) < 1e-9)
        let first = line.words[0].end - line.words[0].start
        let second = line.words[1].end - line.words[1].start
        #expect(abs(second - first * 2) < 1e-9)
    }

    @Test func cjkLinesWithoutSpacesSplitPerCharacter() throws {
        let line = try #require(LyricsTimelineEstimator.estimate(lyrics: "夜明けの鐘", duration: 100)?.lines.first)
        #expect(line.words.map(\.text) == ["夜", "明", "け", "の", "鐘"])
    }
}

@Suite("LyricsTimelineBuilder")
struct LyricsTimelineBuilderTests {
    @Test func embeddedLRCWinsOverEstimation() throws {
        let timeline = try #require(LyricsTimelineBuilder.build(lyrics: "[00:05.00]Lanterns\n[00:09.00]Ash\n[00:12.00]", duration: 100))
        #expect(timeline.source == .embeddedLRC)
        #expect(timeline.lines.map(\.text) == ["Lanterns", "Ash"])
        #expect(timeline.lines.map(\.start) == [5, 9])
        #expect(timeline.lines.map(\.end) == [9, 12])
    }

    @Test func lastLRCLineEndsAtTheDurationOrAFallback() throws {
        let withDuration = try #require(LyricsTimelineBuilder.build(lyrics: "[00:05.00]a\n[00:09.00]b", duration: 100))
        #expect(withDuration.lines.last?.end == 100)
        let noDuration = try #require(LyricsTimelineBuilder.build(lyrics: "[00:05.00]a\n[00:09.00]b", duration: 0))
        #expect(noDuration.lines.last?.end == 9 + LyricsTimelineBuilder.lastLineFallback)
    }

    @Test func plainTextFallsBackToEstimation() throws {
        let timeline = try #require(LyricsTimelineBuilder.build(lyrics: "a\nb", duration: 60))
        #expect(timeline.source == .estimated)
    }

    @Test func nothingToShowGivesNil() {
        #expect(LyricsTimelineBuilder.build(lyrics: "", duration: 60) == nil)
    }
}
