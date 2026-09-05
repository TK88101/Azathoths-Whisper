import Testing

@testable import AzathothsWhisper

// ACCEPTANCE B-07：卡片兩行＝「artist - title」以首個 " - " 切分後其餘 join
@Suite("TrackLabel")
struct TrackLabelTests {
    @Test func splitsOnFirstSeparatorAndRejoinsRest() {
        let lines = TrackLabel.lines(artist: "Opeth", title: "Ghost of Perdition")
        #expect(lines.artist == "Opeth")
        #expect(lines.title == "Ghost of Perdition")
    }

    @Test func titleContainingSeparatorIsRejoined() {
        let lines = TrackLabel.lines(artist: "Ulver", title: "Bergtatt - Ballade")
        #expect(lines.artist == "Ulver")
        #expect(lines.title == "Bergtatt - Ballade")
    }

    // 原版缺陷照搬：artist 自身含 " - " 時會被切壞（不是「修正」對象）
    @Test func artistContainingSeparatorIsSplitLikePython() {
        let lines = TrackLabel.lines(artist: "A - B", title: "Song")
        #expect(lines.artist == "A")
        #expect(lines.title == "B - Song")
    }

    @Test func labelWithoutSeparatorLeavesTitleEmpty() {
        let lines = TrackLabel.split("SoloName")
        #expect(lines.artist == "SoloName")
        #expect(lines.title == "")
    }
}
