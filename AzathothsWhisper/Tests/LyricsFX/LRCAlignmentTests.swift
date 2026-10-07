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
}
