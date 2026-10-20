import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.4：雙向覆蓋、最少錨點、外部 cue 驗證、存檔錨點的讀回驗證與重建。歌詞全部是編造的測試句
@Suite("LRCAligner（C 段）")
struct TimingAlignmentTests {
    private let music = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn"

    private func lrc(_ pairs: [(Double, String)]) -> [LRCLine] { pairs.map { LRCLine(start: $0.0, text: $0.1) } }

    /// Codex R2 反例：Music 漏了前段，LRC 有兩段相同的副歌。前向第一個命中會整段錨到前一段，
    /// Music 側 100 %，但 LRC 側只錨到一半以下 → 拒絕
    @Test func aRepeatedChorusWithAMissingFirstHalfIsRejected() {
        let chorusOnly = "Count the silent bells\nPaper boats at dawn\nHold the lantern high"
        let full = lrc([
            (10, "Lanterns over the river"), (14, "Ash in the wind"), (18, "Smoke along the shore"),
            (22, "Count the silent bells"), (26, "Paper boats at dawn"), (30, "Hold the lantern high"),
            (40, "Lanterns over the river"), (44, "Ash in the wind"), (48, "Smoke along the shore"),
            (52, "Count the silent bells"), (56, "Paper boats at dawn"), (60, "Hold the lantern high"),
        ])
        let alignment = LRCAligner.alignment(lyrics: chorusOnly, lrc: full)
        #expect(alignment?.musicRate == 1)
        #expect((alignment?.lrcCoverage ?? 1) < LRCAligner.lrcCoverageThreshold)
        #expect(LRCAligner.align(lyrics: chorusOnly, lrc: full, duration: 100, source: .netease) == nil)
    }

    @Test func fewerThanThreeAnchorsIsRejectedEvenAtFullRate() {
        let two = "Lanterns over the river\nAsh in the wind"
        let timed = lrc([(10, "Lanterns over the river"), (14, "Ash in the wind")])
        #expect(LRCAligner.alignment(lyrics: two, lrc: timed)?.musicRate == 1)
        #expect(LRCAligner.align(lyrics: two, lrc: timed, duration: 100, source: .lrclib) == nil)
    }

    @Test func coverageCountsOnlyDirectOneToOneAnchors() throws {
        let timed = lrc([(10, "Lanterns over the river"), (12, ""), (14, "Ash in the wind"), (20, "Count the silent bells"), (24, "Paper boats at dawn"), (30, "Spare line")])
        let alignment = try #require(LRCAligner.alignment(lyrics: music, lrc: timed))
        #expect(alignment.anchors == [10, 14, 20, 24])
        #expect(alignment.musicRate == 1)
        #expect(alignment.lrcCoverage == 0.8)   // 空行不進分母：4／5
    }

    @Test func cuesAreSanitized() {
        let raw = lrc([(.nan, "a"), (-1, "b"), (30, "late"), (10, "first"), (10, "same time"), (205.5, "too far"), (12, "")])
        let clean = LRCAligner.sanitizedCues(raw, duration: 200)
        #expect(clean == lrc([(10, "first"), (12, ""), (30, "late")]))
    }

    @Test func storedAnchorsRebuildTheSameTimelineAsTheLiveAlignment() throws {
        let timed = lrc([(10, "Lanterns over the river"), (14, "Something else entirely here"), (20, "Count the silent bells"), (24, "Paper boats at dawn")])
        let live = try #require(LRCAligner.align(lyrics: music, lrc: timed, duration: 100, source: .youtubeMusic))
        let alignment = try #require(LRCAligner.alignment(lyrics: music, lrc: timed))
        let stored = alignment.lineStarts
        #expect(stored == [.init(index: 0, start: 10), .init(index: 2, start: 20), .init(index: 3, start: 24)])
        let rebuilt = try #require(LRCAligner.timeline(lyrics: music, stored: stored, duration: 100, source: .youtubeMusic))
        #expect(rebuilt == live)
    }

    @Test(arguments: [
        [TimingRecord.LineStart(index: 4, start: 10)],                                             // 超出行數
        [TimingRecord.LineStart(index: 0, start: 20), TimingRecord.LineStart(index: 1, start: 10)], // 時間倒退
        [TimingRecord.LineStart(index: 0, start: 106)],                                            // 超過曲長＋5 s
        [TimingRecord.LineStart(index: 0, start: .infinity)],
        [],
    ])
    func invalidStoredAnchorsAreNotShown(stored: [TimingRecord.LineStart]) {
        #expect(LRCAligner.timeline(lyrics: music, stored: stored, duration: 100, source: .lrclib) == nil)
    }
}
