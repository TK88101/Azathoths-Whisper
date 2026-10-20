import Testing

@testable import AzathothsWhisper

// 外部時間軸只借時間、不借文字（母計劃 §2.4；A1 計劃 §3.4）。歌詞全部是編造的測試句
@Suite("LRCAligner")
struct LRCAlignmentTests {
    private let music = "[Verse]\nLanterns over the river\nAsh in the wind\n[Chorus]\nCount the silent bells\nPaper boats at dawn"

    private func lrc(_ pairs: [(Double, String)]) -> [LRCLine] { pairs.map { LRCLine(start: $0.0, text: $0.1) } }

    @Test func identicalTextAlignsEveryLine() throws {
        let timeline = try #require(LRCAligner.align(
            lyrics: music,
            lrc: lrc([(10, "Lanterns over the river"), (14, "Ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn")]),
            duration: 100, source: .lrclib
        ))
        #expect(timeline.source == .lrclib)
        #expect(timeline.lines.map(\.start) == [10, 14, 20, 24])
        #expect(timeline.lines.map(\.isChorus) == [false, false, true, true])
    }

    /// 畫面永遠顯示 Music 的文字：大小寫與標點差異不影響對齊
    @Test func displayTextComesFromMusicNotTheLRC() throws {
        let timeline = try #require(LRCAligner.align(
            lyrics: music,
            lrc: lrc([(10, "LANTERNS, over the river!"), (14, "ash in the wind"), (20, "Count the silent bells..."), (24, "paper boats at dawn")]),
            duration: 100, source: .lrclib
        ))
        #expect(timeline.lines.map(\.text) == ["Lanterns over the river", "Ash in the wind", "Count the silent bells", "Paper boats at dawn"])
    }

    @Test func noiseHeaderLineDoesNotDisturbTheAlignment() throws {
        let timeline = try #require(LRCAligner.align(
            lyrics: music,
            lrc: lrc([(0, "Some Band - Some Song"), (10, "Lanterns over the river"), (14, "Ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn")]),
            duration: 100, source: .lrclib
        ))
        #expect(timeline.lines.first?.start == 10)
    }

    @Test func aDifferentSongIsRejected() {
        let other = lrc([(10, "Engines in the night"), (14, "Neon on the road"), (20, "Running out of time"), (24, "Static on the radio")])
        #expect(LRCAligner.align(lyrics: music, lrc: other, duration: 100, source: .lrclib) == nil)
    }

    /// 3/4＝0.75 ≥ 0.7 採用；未對上的行在相鄰已對上行之間內插
    @Test func unmatchedLinesAreInterpolatedMonotonically() throws {
        let timeline = try #require(LRCAligner.align(
            lyrics: music,
            lrc: lrc([(10, "Lanterns over the river"), (14, "Something else entirely here"), (20, "Count the silent bells"), (24, "Paper boats at dawn")]),
            duration: 100, source: .lrclib
        ))
        #expect(timeline.lines.map(\.start) == [10, 15, 20, 24])
    }

    @Test func belowTheAlignmentRateIsRejected() {
        let half = lrc([(10, "Lanterns over the river"), (20, "Count the silent bells")])
        #expect(LRCAligner.align(lyrics: music, lrc: half, duration: 100, source: .lrclib) == nil)
    }

    @Test func similarityOfNearMatchesPassesTheThreshold() {
        #expect(LRCAligner.similarity("Lanterns over the river", "Lanterns over a river") >= LRCAligner.lineSimilarityThreshold)
        #expect(LRCAligner.similarity("Lanterns over the river", "Static on the radio") < LRCAligner.lineSimilarityThreshold)
        #expect(LRCAligner.similarity("", "") == 0)
    }

    // Genius 常把 LRC 的兩、三行合成一行（docs/plans/2026-10-19-lyrics-fx-merged-line-align.md）
    /// 同一段文字前面以兩行出現、後面以一行出現：取前面（單調前向、取最早，與一對一時相同）
    @Test func earliestMatchWinsBetweenAConcatenationAndALaterSingleCue() throws {
        let alignment = try #require(LRCAligner.alignment(lyrics: merged, lrc: lrc([
            (10, "Lanterns over the river"), (12, "Ash in the wind"), (20, "Count the silent bells"),
            (24, "Paper boats at dawn"), (28, "Stones under the old bridge"), (40, "Lanterns over the river ash in the wind"),
        ])))
        #expect(alignment.anchors == [10, 20, 24, 28])
    }

    /// LRC 有兩段相同副歌、Music 只寫一次且合成一行：錨到第一段，後面的行不被吃掉
    @Test func repeatedChorusAnchorsToTheFirstOccurrence() throws {
        let song = "Count the silent bells paper boats at dawn\nStones under the old bridge\nSmoke above the hills"
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Count the silent bells"), (12, "Paper boats at dawn"), (20, "Stones under the old bridge"),
            (30, "Count the silent bells"), (32, "Paper boats at dawn"), (40, "Smoke above the hills"),
        ])))
        #expect(alignment.anchors == [10, 20, 40])
    }

    private let merged = "Lanterns over the river ash in the wind\nCount the silent bells\nPaper boats at dawn\nStones under the old bridge"

    @Test func mergedLineAnchorsToTheFirstOfTwoCues() throws {
        let alignment = try #require(LRCAligner.alignment(lyrics: merged, lrc: lrc([
            (10, "Lanterns over the river"), (12, "Ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn"), (28, "Stones under the old bridge"),
        ])))
        #expect(alignment.anchors == [10, 20, 24, 28])
        // LRC 側覆蓋率照舊以「對上的 Music 行數」計，不因串接放寬（Codex M1-Q2）：4／5
        #expect(alignment.lrcCoverage == 0.8)
        #expect(alignment.isAccepted)
    }

    @Test func mergedLineAnchorsToTheFirstOfThreeCues() throws {
        let three = "Lanterns over the river ash in the wind count the bells\nPaper boats at dawn\nStones under the old bridge\nSmoke above the hills"
        let alignment = try #require(LRCAligner.alignment(lyrics: three, lrc: lrc([
            (10, "Lanterns over the river"), (12, "Ash in the wind"), (14, "Count the bells"), (20, "Paper boats at dawn"), (24, "Stones under the old bridge"), (28, "Smoke above the hills"),
        ])))
        #expect(alignment.anchors == [10, 20, 24, 28])
        #expect(abs(alignment.lrcCoverage - 4.0 / 6.0) < 1e-9)
    }

    /// 單行可中時不取串接：Music「Ash in the wind」只對自己那一行
    @Test func singleCueMatchWinsOverConcatenation() throws {
        let alignment = try #require(LRCAligner.alignment(lyrics: music, lrc: lrc([
            (10, "Lanterns over the river"), (14, "Ash in the wind"), (16, "Ash in the wind again"), (20, "Count the silent bells"), (24, "Paper boats at dawn"),
        ])))
        #expect(alignment.anchors == [10, 14, 20, 24])
    }

    /// 空行是段落分隔：串接不跨過它
    @Test func concatenationDoesNotCrossABlankCue() throws {
        let alignment = try #require(LRCAligner.alignment(lyrics: merged, lrc: lrc([
            (10, "Lanterns over the river"), (11, ""), (12, "Ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn"), (28, "Stones under the old bridge"),
        ])))
        #expect(alignment.anchors == [nil, 20, 24, 28])
    }

    /// 四行以上不串（k 上限 3）
    @Test func fourCuesAreNotConcatenated() throws {
        let four = "Lanterns over the river ash in the wind count the bells by the cold and silent water tonight\nPaper boats at dawn\nStones under the old bridge\nSmoke above the hills"
        let alignment = try #require(LRCAligner.alignment(lyrics: four, lrc: lrc([
            (10, "Lanterns over the river"), (12, "Ash in the wind"), (14, "Count the bells"), (16, "By the cold and silent water tonight"), (20, "Paper boats at dawn"), (24, "Stones under the old bridge"), (28, "Smoke above the hills"),
        ])))
        #expect(alignment.anchors.first == .some(nil))
    }
}
