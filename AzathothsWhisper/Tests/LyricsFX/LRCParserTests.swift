import Testing

@testable import AzathothsWhisper

// 層 1：Music 欄位內嵌的 LRC（母計劃 §2.4；A1 計劃 §3.4）
@Suite("LRCParser")
struct LRCParserTests {
    @Test func parsesSingleTags() {
        let lines = LRCParser.parse("[00:12.50]Lanterns over the river\n[00:17.00]Ash in the wind")
        #expect(lines == [LRCLine(start: 12.5, text: "Lanterns over the river"), LRCLine(start: 17, text: "Ash in the wind")])
    }

    @Test func expandsMultipleTagsOnOneLineAndSortsByTime() {
        let lines = LRCParser.parse("[00:30.00][00:10.00]Ho!\n[00:20.00]Count the silent bells")
        #expect(lines.map(\.start) == [10, 20, 30])
        #expect(lines.map(\.text) == ["Ho!", "Count the silent bells", "Ho!"])
    }

    @Test func fractionDigitsAreTenthsHundredthsOrMilliseconds() {
        #expect(LRCParser.parse("[01:02.5]a").first?.start == 62.5)
        #expect(LRCParser.parse("[01:02.05]a").first?.start == 62.05)
        #expect(LRCParser.parse("[01:02.005]a").first?.start == 62.005)
        #expect(LRCParser.parse("[01:02]a").first?.start == 62)
        #expect(LRCParser.parse("[01:02:50]a").first?.start == 62.5)
    }

    @Test func skipsIDTags() {
        let lines = LRCParser.parse("[ti:Some Song]\n[ar:Some Band]\n[length:08:35]\n[00:01.00]a")
        #expect(lines == [LRCLine(start: 1, text: "a")])
    }

    /// LRC 標準：offset 為毫秒，正值＝歌詞提早
    @Test func appliesTheOffsetTagAndClampsAtZero() {
        let lines = LRCParser.parse("[offset:+500]\n[00:00.20]a\n[00:02.00]b")
        #expect(lines.map(\.start) == [0, 1.5])
        #expect(LRCParser.parse("[offset:-1000]\n[00:01.00]a").first?.start == 2)
    }

    @Test func acceptsCRAndCRLF() {
        #expect(LRCParser.parse("[00:01.00]a\r[00:02.00]b\r\n[00:03.00]c").map(\.text) == ["a", "b", "c"])
    }

    @Test func noiseHeaderLinesParseLikeAnyOtherLine() {
        let lines = LRCParser.parse("[00:00.00] Some Band - Some Song\n[00:05.00]Lanterns over the river")
        #expect(lines.first?.text == "Some Band - Some Song")
    }

    @Test func stripsEnhancedWordTags() {
        let lines = LRCParser.parse("[00:01.00]<00:01.00>Lanterns <00:01.40>over <00:01.60>water")
        #expect(lines.first?.text == "Lanterns over water")
    }

    @Test func keepsEmptyLinesAsTimeMarkers() {
        let lines = LRCParser.parse("[00:01.00]a\n[00:04.00]")
        #expect(lines == [LRCLine(start: 1, text: "a"), LRCLine(start: 4, text: "")])
    }

    @Test func untaggedLinesAreIgnored() {
        #expect(LRCParser.parse("plain\n[00:01.00]a").map(\.text) == ["a"])
    }

    @Test func detectsLRC() {
        #expect(LRCParser.isLRC("[ti:x]\n[00:01.00]a\n[00:02.00]b\nstray"))
        #expect(!LRCParser.isLRC("a\nb\n[00:02.00]c"))
        #expect(!LRCParser.isLRC("[Chorus]\nCount the silent bells"))
        #expect(!LRCParser.isLRC(""))
    }
}

@Suite("LyricsLines")
struct LyricsLinesTests {
    @Test func classifiesLyricsSectionsAndBlanks() {
        let lines = LyricsLines.parse("[Verse 1]\nLanterns over the river\n\n[Chorus: Singer]\nPaper boats at dawn\n[Guitar Solo]\n[Verse 2]\nQuiet harbor")
        #expect(lines == [
            .section(.other),
            .lyric("Lanterns over the river", isChorus: false),
            .blank,
            .section(.chorus),
            .lyric("Paper boats at dawn", isChorus: true),
            .section(.interlude),
            .section(.other),
            .lyric("Quiet harbor", isChorus: false),
        ])
    }

    @Test func chorusLastsUntilTheNextSectionTag() {
        let lines = LyricsLines.parse("[Pre-Chorus]\na\n\nb\n[Bridge]\nc")
        #expect(lines.compactMap(\.lyricIsChorus) == [true, true, false])
    }

    @Test func trimsWhitespaceAndNormalizesLineEndings() {
        #expect(LyricsLines.parse("  a  \r  \rb") == [.lyric("a", isChorus: false), .blank, .lyric("b", isChorus: false)])
    }

    @Test func lrcTimestampsAreNotSections() {
        #expect(LyricsLines.parse("[00:01.00]")  == [.lyric("[00:01.00]", isChorus: false)])
    }

    @Test func lyricTextsSkipsEverythingElse() {
        #expect(LyricsLines.lyricTexts("[Intro]\na\n\nb") == ["a", "b"])
    }
}

private extension LyricsLine {
    var lyricIsChorus: Bool? {
        if case .lyric(_, let isChorus) = self { return isChorus }
        return nil
    }
}
