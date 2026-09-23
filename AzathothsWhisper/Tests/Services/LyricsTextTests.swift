import Testing

@testable import AzathothsWhisper

// 「純空白＝缺詞」（C-29）的唯一定義：與 Python 版 `bool(lyrics.strip())`（py:2254）逐字元一致。
// 對抗覆核 P2 B10 ＋ Codex R2 裁決：三處（狀態推導、Editor 自動抓詞、Batch 缺詞篩選）共用同一判定。
@Suite("LyricsText")
struct LyricsTextTests {
    @Test("與 CPython str.strip() 同一字元集", arguments: [
        ("", true),
        (" \n\t\r", true),
        ("\u{1C}\u{1F}", true),        // Python 視為空白；Foundation 不剝
        ("\u{3000}", true),
        ("\u{200B}", false),           // ZWSP：Foundation 會剝，Python 不剝
        ("\u{FEFF}", false),           // BOM：Python 不剝（py:2254 的取捨，見 LyricsText）
        ("words", false),
    ])
    func blankMatchesPythonStrip(text: String, isBlank: Bool) {
        #expect(LyricsText.isBlank(text) == isBlank)
    }

    @Test func statusAndBatchUseTheSameDefinition() {
        #expect(LyricsStatus.resolve(lyrics: "\u{1C}", isMarked: false) == .missing)
        #expect(LyricsStatus.resolve(lyrics: "\u{200B}", isMarked: false) == .present)
        #expect(!AlbumTrack.fixture(lyrics: "\u{1C}").hasLyrics)
        #expect(AlbumTrack.fixture(lyrics: "\u{200B}").hasLyrics)
    }
}
