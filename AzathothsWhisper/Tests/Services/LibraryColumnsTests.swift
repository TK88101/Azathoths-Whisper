import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門（/thecure 2026-10-28：豁免只限 ScriptingBridge 邊界）：讀回的字串欄→列、讀不完整一律失敗。歌手、曲名自編
@Suite("Library columns")
struct LibraryColumnsTests {
    @Test func fiveColumnsBecomeTrackRows() throws {
        let rows = try LibraryColumns.trackRows([["A", "B"], ["Song A", "Song B"], ["Paper Harbour", "Velvet Lanterns"], ["Night Ferry", "Grey"], ["Rock", "Pop"]])
        #expect(rows == [
            LibraryTrackRow(persistentID: "A", name: "Song A", artist: "Paper Harbour", album: "Night Ferry", genre: "Rock"),
            LibraryTrackRow(persistentID: "B", name: "Song B", artist: "Velvet Lanterns", album: "Grey", genre: "Pop"),
        ])
    }

    @Test func twoColumnsBecomeLyricsRows() throws {
        #expect(try LibraryColumns.lyricsRows([["A"], ["Lanterns over the river"]]) == [ArtistLyricsRow(persistentID: "A", lyrics: "Lanterns over the river")])
    }

    @Test func anEmptyLibraryIsNotAFailure() throws {
        #expect(try LibraryColumns.trackRows([[], [], [], [], []]).isEmpty)
    }

    @Test(arguments: [
        nil,
        [["A"], ["Song A"], ["Paper Harbour"], ["Night Ferry"]],
        [["A", "B"], ["Song A"], ["Paper Harbour"], ["Night Ferry"], ["Rock"]],
    ] as [[[String]]?])
    func anIncompleteReadFails(columns: [[String]]?) {
        #expect(throws: MusicError.scriptingFailure("library read incomplete")) { try LibraryColumns.trackRows(columns) }
    }

    @Test func pairsKeepTheOldEmptyOnFailureMeaningForCallersThatWantIt() throws {
        #expect((try? LibraryColumns.pairs(nil)) == nil)
        #expect(try LibraryColumns.pairs([["x"], ["y"]]).map { [$0.0, $0.1] } == [["x", "y"]])
        #expect(throws: MusicError.scriptingFailure("library read incomplete")) { try LibraryColumns.pairs([["x"], []]) }
    }
}
