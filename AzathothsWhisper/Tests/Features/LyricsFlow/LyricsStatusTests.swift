import Testing

@testable import AzathothsWhisper

// 計劃 AC7：徽章與狀態一致；優先序 present ＞ markedNone ＞ missing；讀不到＝unknown
@Suite("LyricsStatus")
struct LyricsStatusTests {
    @Test("全真值表", arguments: [
        (String?.some("verse"), false, LyricsStatus.present),
        (String?.some("verse"), true, LyricsStatus.present),        // 檔內有詞時標記無效
        (String?.some(""), false, LyricsStatus.missing),
        (String?.some(""), true, LyricsStatus.markedNone),
        (String?.some(" \n\t "), false, LyricsStatus.missing),      // C-29：純空白＝缺詞
        (String?.some(" \n\t "), true, LyricsStatus.markedNone),
        (String?.none, false, LyricsStatus.unknown),                // 讀不到不折疊成缺詞
        (String?.none, true, LyricsStatus.unknown),
    ])
    func resolve(lyrics: String?, isMarked: Bool, expected: LyricsStatus) {
        #expect(LyricsStatus.resolve(lyrics: lyrics, isMarked: isMarked) == expected)
    }
}
