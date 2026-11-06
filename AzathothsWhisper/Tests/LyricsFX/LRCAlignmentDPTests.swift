import Foundation
import Testing

@testable import AzathothsWhisper

// ⑩ 計劃（docs/plans/2026-11-06-lyrics-timing-fix.md）§4.1／§4.2：單調最優對齊＋「多個 Music 行↔一個 LRC 行」。
// 歌詞全部是編造的測試句（不得用真歌詞）
@Suite("LRCAligner revision 3")
struct LRCAlignmentDPTests {
    private func lrc(_ pairs: [(Double, String)]) -> [LRCLine] { AlignmentFixtures.lrc(pairs) }

    private let six = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn\nStones under the old bridge\nSmoke above the hills"

    // MARK: 反向群組（Music 把 LRC 一行拆成多行）

    /// 權重＝正規化字數：lanternsovertheriver 20、ashinthewind 12、countthesilentbells 19、paperboatsatdawn 16
    @Test func musicLinesSplitFromOneCueAlignToThatCue() throws {
        let alignment = try #require(LRCAligner.alignment(lyrics: six, lrc: lrc([
            (10, "Lanterns over the river ash in the wind"), (20, "Count the silent bells paper boats at dawn"),
            (30, "Stones under the old bridge"), (40, "Smoke above the hills"),
        ]), duration: 100))
        let anchors = alignment.anchors.map { $0 ?? -1 }
        let expected = [10, 10 + 10 * 20.0 / 32, 20, 20 + 10 * 19.0 / 35, 30, 40]
        #expect(zip(anchors, expected).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(alignment.musicRate == 1)
        #expect(alignment.groups == 4)
        #expect(alignment.lrcCoverage == 1)   // 群組數／LRC 非空行：不會超過 1
        #expect(alignment.isAccepted)
    }

    @Test func revisionTwoRejectedTheSplitLinesCase() throws {
        let cues = lrc([
            (10, "Lanterns over the river ash in the wind"), (20, "Count the silent bells paper boats at dawn"),
            (30, "Stones under the old bridge"), (40, "Smoke above the hills"),
        ])
        let old = try #require(LRCAlignerV2Oracle.alignment(lyrics: six, lrc: cues))
        #expect(old.musicRate < LRCAligner.alignmentRateThreshold)
    }

    @Test func aGroupAtTheEndSplitsUpToTheLastLineEnd() throws {
        let alignment = try #require(LRCAligner.alignment(lyrics: six, lrc: lrc([
            (10, "Lanterns over the river"), (14, "Ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn"),
            (30, "Stones under the old bridge smoke above the hills"),
        ]), duration: 50))
        // stonesundertheoldbridge 23、smokeabovethehills 18；上界＝lastLineEnd(30, 50)＝50
        let last = try #require(alignment.anchors[5])
        #expect(abs(last - (30 + 20 * 23.0 / 41)) < 1e-9)
        #expect(alignment.anchors[4] == 30)
    }

    @Test func aGroupBeforeAFarCueSplitsUpToThatCue() throws {
        let four = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn"
        let alignment = try #require(LRCAligner.alignment(lyrics: four, lrc: lrc([
            (10, "Lanterns over the river ash in the wind"), (90, "Count the silent bells"), (94, "Paper boats at dawn"),
        ]), duration: 100))
        #expect(alignment.anchors == [10, 10 + 80 * 20.0 / 32, 90, 94])
    }

    /// 群組中間一行正規化後為空（只有標點）：權重 0，與前一行同一時刻（單調不減）
    @Test func anEmptyLineInsideAGroupGetsZeroWeight() throws {
        let song = "Lanterns over the river\n...\nAsh in the wind\nCount the silent bells\nPaper boats at dawn"
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Lanterns over the river ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn"),
        ]), duration: 100))
        #expect(alignment.anchors == [10, 16.25, 16.25, 20, 24])
        #expect(alignment.groups == 3)
    }

    @Test func groupStartsSplitByWeightAndEquallyWhenAllWeightsAreZero() {
        #expect(LRCAligner.groupStarts(weights: [20, 12], start: 10, end: 20) == [10, 16.25])
        #expect(LRCAligner.groupStarts(weights: [0, 0], start: 10, end: 20) == [10, 15])
        #expect(LRCAligner.groupStarts(weights: [1, 0, 1], start: 0, end: 8) == [0, 4, 4])
    }

    /// 存檔存的是每個 timeline 行的起點（群組非首行也存），讀回重建同一條時間軸
    @Test func storedGroupAnchorsRebuildTheLiveTimeline() throws {
        let cues = lrc([
            (10, "Lanterns over the river ash in the wind"), (20, "Count the silent bells paper boats at dawn"),
            (30, "Stones under the old bridge"), (40, "Smoke above the hills"),
        ])
        let live = try #require(LRCAligner.align(lyrics: six, lrc: cues, duration: 60, source: .lrclib))
        let stored = try #require(LRCAligner.alignment(lyrics: six, lrc: cues, duration: 100)).lineStarts
        #expect(stored.count == 6)
        let rebuilt = try #require(LRCAligner.timeline(lyrics: six, stored: stored, duration: 60, source: .lrclib))
        #expect(rebuilt == live)
    }

    // MARK: 貪婪陷阱

    /// Music 第一行只在 LRC 尾端出現：貪婪錨過去後整首全滅；最優對齊跳過它
    @Test func aLineMatchingOnlyNearTheEndDoesNotSwallowTheSong() throws {
        let song = "Hold on tight\nLanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn"
        let cues = lrc([(10, "Lanterns over the river"), (14, "Ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn"), (40, "Hold on tight")])
        let old = try #require(LRCAlignerV2Oracle.alignment(lyrics: song, lrc: cues))
        #expect(old.matched == 1)
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: cues, duration: 100))
        #expect(alignment.anchors == [nil, 10, 14, 20, 24])
        #expect(alignment.isAccepted)
    }

    // MARK: 同分規則（§4.1、附錄 D）

    /// 同一 cue 可單行也可反向、兩條路徑 (對上數, 群組數) 不同：取群組多者＝單行
    @Test func singleCueWinsOverAReverseGroupAtTheSameCue() throws {
        let song = "Paper boats at the dawn\nOh\nStones under the old bridge\nSmoke above the hills"
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Paper boats at the dawn oh"), (12, "Oh"), (20, "Stones under the old bridge"), (24, "Smoke above the hills"),
        ]), duration: 100))
        #expect(alignment.anchors == [10, 12, 20, 24])
        #expect(alignment.groups == 4)
    }

    /// 附錄 D 反例：LRC 先有合併行、後有分開的行；對上數相同時取群組多者（覆蓋率 3／4 可採用，而非 2／4 被拒）
    @Test func equalMatchesPreferMoreGroupsOverAnEarlierReverseGroup() throws {
        let song = "Count the silent bells\nPaper boats at dawn\nStones under the old bridge"
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Count the silent bells paper boats at dawn"), (20, "Count the silent bells"), (24, "Paper boats at dawn"), (30, "Stones under the old bridge"),
        ]), duration: 100))
        #expect(alignment.anchors == [20, 24, 30])
        #expect(alignment.lrcCoverage == 0.75)
        #expect(alignment.isAccepted)
    }

    /// 完全同分（對上數與群組數都相同）：取最早的 cue
    @Test func fullTiesTakeTheEarliestCue() throws {
        let song = "Count the silent bells\nStones under the old bridge\nSmoke above the hills"
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Count the silent bells"), (14, "Count the silent bells"), (20, "Stones under the old bridge"), (24, "Smoke above the hills"),
        ]), duration: 100))
        #expect(alignment.anchors == [10, 20, 24])
    }

    /// Music 某行無處可配：停在原 cue 跳過它，下一行仍從同一 cue 起找（v1.0「先跳 cue」會讓下一行錨到較後的重複句）
    @Test func anUnmatchableLineIsSkippedWithoutConsumingCues() throws {
        let song = "Lanterns over the river\nNothing like this anywhere\nAsh in the wind\nCount the silent bells"
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Lanterns over the river"), (14, "Ash in the wind"), (20, "Count the silent bells"), (30, "Ash in the wind"), (34, "Count the silent bells"),
        ]), duration: 100))
        #expect(alignment.anchors == [10, nil, 14, 20])
    }

    // MARK: 邊界（simcodex R1 安全評審 F1、F2）

    /// 反向群組落在曲長＋5 s 內的最後一個 cue：切分點不得超過 `duration + durationSlack`，否則存檔讀回顯示不了、也永不重查
    @Test func aGroupOnALateLastCueStaysWithinTheStoredDurationLimit() throws {
        let song = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nStones under the old bridge\nOh"
        let duration = 200.0
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Lanterns over the river"), (14, "Ash in the wind"), (20, "Count the silent bells"), (204, "Stones under the old bridge oh"),
        ]), duration: duration))
        #expect(alignment.groups == 4)
        #expect(alignment.anchors.compactMap { $0 }.allSatisfy { $0 <= duration + LRCAligner.durationSlack })
        #expect(LRCAligner.storedLinesFit(alignment.lineStarts, lineCount: 5, durationLimit: duration + LRCAligner.durationSlack))
    }

    /// Music 行數多到「每個 cue 吃滿 3 行也到不了 0.7」：不跑 DP（不配置 M×L 表）、直接不採用
    @Test func tooManyMusicLinesForTheCuesAreRejectedWithoutAligning() throws {
        let filler = (0..<17).map { "Invented filler line number \($0)" }
        let song = (["Lanterns over the river", "Ash in the wind", "Count the silent bells"] + filler).joined(separator: "\n")
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([
            (10, "Lanterns over the river"), (14, "Ash in the wind"), (20, "Count the silent bells"),
        ]), duration: 100))
        #expect(!alignment.isAccepted)
        #expect(alignment.groups == 0)
        #expect(alignment.anchors.allSatisfy { $0 == nil })
    }

    // MARK: 防錯錨（新版不得由拒轉收；每條同時以 v2 確認原本就拒）

    @Test func sectionsInSwappedOrderAreRejected() throws {
        let song = "Lanterns over the river\nAsh in the wind\nSmoke along the shore\nCount the silent bells\nPaper boats at dawn\nHold the lantern high"
        let cues = lrc([
            (10, "Count the silent bells"), (14, "Paper boats at dawn"), (18, "Hold the lantern high"),
            (30, "Lanterns over the river"), (34, "Ash in the wind"), (38, "Smoke along the shore"),
        ])
        let old = try #require(LRCAlignerV2Oracle.alignment(lyrics: song, lrc: cues))
        #expect(old.musicRate < LRCAligner.alignmentRateThreshold)
        #expect(LRCAligner.align(lyrics: song, lrc: cues, duration: 100, source: .lrclib) == nil)
    }

    @Test func aDifferentSongSharingOneChorusLineIsRejected() throws {
        let song = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn\nStones under the old bridge"
        let cues = lrc([
            (10, "Engines in the night"), (14, "Neon on the road"), (20, "Count the silent bells"),
            (24, "Running out of time"), (28, "Static on the radio"),
        ])
        let old = try #require(LRCAlignerV2Oracle.alignment(lyrics: song, lrc: cues))
        #expect(!(old.musicRate >= LRCAligner.alignmentRateThreshold && old.lrcCoverage >= LRCAligner.lrcCoverageThreshold))
        #expect(LRCAligner.align(lyrics: song, lrc: cues, duration: 100, source: .lrclib) == nil)
    }

    /// 反向群組只算 1 個錨：三行對一個 cue 不足 `minimumAnchors`
    @Test func aSingleReverseGroupIsNotEnoughAnchors() throws {
        let song = "Lanterns over the river\nAsh in the wind\nCount the bells"
        let alignment = try #require(LRCAligner.alignment(lyrics: song, lrc: lrc([(10, "Lanterns over the river ash in the wind count the bells")]), duration: 100))
        #expect(alignment.musicRate == 1)
        #expect(alignment.groups == 1)
        #expect(!alignment.isAccepted)
    }

    // MARK: 效能（§4.1 效能驗收）

    /// 最壞輸入（2000×2000、每行 500 字、全不相同）：取消後 ≤ 1 s 內實際返回 nil。
    /// resolver 的 20 s 時限就是取消對齊所在的 task，所以這條等於「時限到點後 ≤ 1 s 返回」
    @Test func theWorstCaseReturnsWithinOneSecondOfCancellation() async {
        let lyrics = AlignmentFixtures.worstCaseLines(salt: 1).joined(separator: "\n")
        let cues = AlignmentFixtures.worstCaseLines(salt: 2).enumerated().map { LRCLine(start: Double($0.offset), text: $0.element) }
        let task = Task.detached { LRCAligner.alignment(lyrics: lyrics, lrc: cues, duration: 9000) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let cancelledAt = ContinuousClock.now
        task.cancel()
        let result = await task.value
        let elapsed = ContinuousClock.now - cancelledAt
        #expect(result == nil)
        #expect(elapsed <= .seconds(1), "取消後 \(elapsed) 才返回")
    }

    // MARK: 取消

    /// cue 數足以通過預檢，確實走進 DP 才遇到取消
    @Test func aCancelledTaskReturnsNil() async {
        let cues = LyricsLines.lyricTexts(six).enumerated().map { LRCLine(start: Double($0.offset) * 4 + 10, text: $0.element) }
        let task = Task { () -> LRCAligner.Alignment? in
            try? await Task.sleep(nanoseconds: 50_000_000)
            return LRCAligner.alignment(lyrics: six, lrc: cues, duration: 100)
        }
        task.cancel()
        #expect(await task.value == nil)
    }
}
