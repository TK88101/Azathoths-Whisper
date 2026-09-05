import Foundation
import Testing

@testable import AzathothsWhisper

// H-03：中心下方標籤的文案組裝（Plan §4.8）。
//
// 只測**組裝**，不測大寫——`ARTIST // TITLE` 裡的大寫來自 View 的 `.textCase(.uppercase)`
// 這個渲染修飾符，純函數回傳的是原串。對回傳值斷言大寫會測到代碼沒往那兒放的東西。
// 大寫與 mono 排版屬觀感，走 M8-14 目視。
@Suite("CoverFlowCenterLabel")
struct CoverFlowCenterLabelTests {
    private func track(_ id: String, artist: String, title: String) -> AlbumTrack {
        AlbumTrack(
            persistentID: id, artist: artist, title: title, album: "A",
            discNumber: 1, trackNumber: 1, lyrics: ""
        )
    }

    @Test func composesArtistAndTitleWithDoubleSlash() {
        let items = [track("P1", artist: "Bjork", title: "Hyperballad")]
        #expect(CoverFlowCenterLabel.text(centerID: "P1", items: items) == "Bjork // Hyperballad")
    }

    /// 隔離 nil 分支：items **非空**，才測得到「centerID 為 nil」這一條 guard
    /// （原寫法同時餵 nil 與空 items，刪掉 nil guard 也不會紅）
    @Test func returnsPlaceholderWhenCenterIDIsNilEvenWithItems() {
        let items = [track("P1", artist: "Bjork", title: "Hyperballad")]
        #expect(CoverFlowCenterLabel.text(centerID: nil, items: items) == CoverFlowCenterLabel.placeholder)
    }

    @Test func returnsPlaceholderWhenListIsEmpty() {
        #expect(CoverFlowCenterLabel.text(centerID: "P1", items: []) == CoverFlowCenterLabel.placeholder)
    }

    @Test func returnsPlaceholderWhenCenterIDNotInItems() {
        let items = [track("P1", artist: "Bjork", title: "Hyperballad")]
        #expect(CoverFlowCenterLabel.text(centerID: "MISSING", items: items) == CoverFlowCenterLabel.placeholder)
    }

    /// 缺 artist 是真實場景（Music 曲目可能無 artist）。此時**照常組裝**，回傳前導 " // "，
    /// 而非退回佔位符——佔位符只保留給「沒有中心曲目」，兩種狀態不可混同：
    /// 混同會讓「有曲目但缺 artist」在 UI 上與「還沒載入」長得一樣。
    @Test func emptyArtistStillComposesRatherThanFallingBackToPlaceholder() {
        let items = [track("P1", artist: "", title: "Untitled")]
        #expect(CoverFlowCenterLabel.text(centerID: "P1", items: items) == " // Untitled")
    }

    /// 重複 persistentID 時取**首個**匹配（實作依賴 `first(where:)`，
    /// 改成 last/filter 不會被其他測試擋住）
    @Test func duplicateIDsUseFirstMatch() {
        let items = [
            track("P1", artist: "First", title: "A"),
            track("P1", artist: "Second", title: "B"),
        ]
        #expect(CoverFlowCenterLabel.text(centerID: "P1", items: items) == "First // A")
    }

    /// 分隔符是 " // "：artist 或 title 自身含 "/" 時不得被誤解析（純組裝，無切分語義）
    @Test func slashesInsideFieldsArePreservedVerbatim() {
        let items = [track("P1", artist: "AC/DC", title: "T.N.T")]
        #expect(CoverFlowCenterLabel.text(centerID: "P1", items: items) == "AC/DC // T.N.T")
    }
}
