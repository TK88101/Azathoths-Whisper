import Testing

@testable import AzathothsWhisper

// ⑤ 中日韓字型計劃 §4.1：每行的文字種類（韓文優先）、整首的中日之分（只看歌詞）。句子全為編造
@Suite("LyricsScript")
struct LyricsScriptTests {
    @Test(arguments: [
        ("Paper boats at dawn", LineScript.latin),
        ("夜明けの灯籠", LineScript.cjk),
        ("灯籠 lanterns 川", LineScript.cjk),
        ("東京", LineScript.cjk),
        ("紙船靜靜漂流", LineScript.cjk),
        ("「」、。", LineScript.cjk),
        ("ＡＢＣ　２", LineScript.cjk),
        ("새벽 lanterns", LineScript.hangul),
        ("새벽 灯籠", LineScript.hangul),
        ("새벽 夜明け", LineScript.hangul),
        ("🎵 la la", LineScript.latin),
        ("", LineScript.latin),
    ])
    func eachLineIsClassifiedWithHangulFirst(text: String, expected: LineScript) {
        #expect(LyricsScript.line(text) == expected)
    }

    @Test func anyKanaMakesTheWholeSongJapanese() {
        #expect(LyricsScript.language(of: ["東京", "Paper boats", "夜明けの空"]) == .japanese)
    }

    @Test func hanWithoutKanaIsChinese() {
        #expect(LyricsScript.language(of: ["紙船靜靜漂流", "Paper boats"]) == .chinese)
    }

    /// 已知限制（計劃 §4.1）：全漢字的日文歌判成中文
    @Test func allKanjiJapaneseIsJudgedChinese() {
        #expect(LyricsScript.language(of: ["東京", "大阪"]) == .chinese)
    }

    @Test func aTimedLineCarriesItsScript() {
        #expect(TimedLine(start: 0, end: 1, text: "새벽 lanterns", isChorus: false).script == .hangul)
        #expect(TimedLine(start: 0, end: 1, text: "Paper boats", isChorus: false).script == .latin)
    }

    @Test func aTimelineCarriesTheSongLanguage() {
        let lines = [TimedLine(start: 0, end: 1, text: "東京", isChorus: false), TimedLine(start: 1, end: 2, text: "夜明けの空", isChorus: false)]
        #expect(LyricsTimeline(lines: lines, source: .estimated, duration: 2).cjkLanguage == .japanese)
    }

    /// 既有的假名漢字判定（分詞、曲風）語意不變：全形標點與相容漢字不算
    @Test func kanaOrKanjiKeepsItsOldRange() {
        #expect(JapaneseText.isKanaOrKanji("夜"))
        #expect(JapaneseText.isKanaOrKanji("け"))
        #expect(!JapaneseText.isKanaOrKanji("。"))
        #expect(!JapaneseText.isKanaOrKanji("Ａ"))
        #expect(!JapaneseText.isKanaOrKanji("새"))
    }
}
