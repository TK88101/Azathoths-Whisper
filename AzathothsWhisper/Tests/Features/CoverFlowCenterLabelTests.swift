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
    private func card(_ id: String, _ persistentID: String) -> DeckCard {
        DeckCard(id: id, persistentID: persistentID, side: .current)
    }

    private func details(_ persistentID: String, artist: String, title: String) -> [String: TrackDetails] {
        [persistentID: TrackDetails(persistentID: persistentID, artist: artist, title: title, album: "A",
                                    discNumber: 1, trackNumber: 1, lyrics: nil)]
    }

    @Test func composesArtistAndTitleWithDoubleSlash() {
        let text = CoverFlowCenterLabel.text(
            centerID: "C1", cards: [card("C1", "P1")], details: details("P1", artist: "Bjork", title: "Hyperballad")
        )
        #expect(text == "Bjork // Hyperballad")
    }

    /// 隔離 nil 分支：cards **非空**，才測得到「centerID 為 nil」這一條 guard
    @Test func returnsPlaceholderWhenCenterIDIsNilEvenWithCards() {
        let text = CoverFlowCenterLabel.text(
            centerID: nil, cards: [card("C1", "P1")], details: details("P1", artist: "Bjork", title: "Hyperballad")
        )
        #expect(text == CoverFlowCenterLabel.placeholder)
    }

    @Test func returnsPlaceholderWhenDeckIsEmpty() {
        #expect(CoverFlowCenterLabel.text(centerID: "C1", cards: [], details: [:]) == CoverFlowCenterLabel.placeholder)
    }

    @Test func returnsPlaceholderWhenCenterIDNotInCards() {
        let text = CoverFlowCenterLabel.text(
            centerID: "MISSING", cards: [card("C1", "P1")], details: details("P1", artist: "Bjork", title: "Hyperballad")
        )
        #expect(text == CoverFlowCenterLabel.placeholder)
    }

    /// 詳情還沒讀到（批次讀取進行中）→ 佔位，不顯示殘缺字串
    @Test func returnsPlaceholderWhenDetailsAreNotLoadedYet() {
        #expect(CoverFlowCenterLabel.text(centerID: "C1", cards: [card("C1", "P1")], details: [:]) == CoverFlowCenterLabel.placeholder)
    }

    /// 缺 artist 是真實場景：照常組裝（" // Untitled"），佔位符只保留給「沒有中心曲目」
    @Test func emptyArtistStillComposesRatherThanFallingBackToPlaceholder() {
        let text = CoverFlowCenterLabel.text(
            centerID: "C1", cards: [card("C1", "P1")], details: details("P1", artist: "", title: "Untitled")
        )
        #expect(text == " // Untitled")
    }

    /// 同曲在牌組出現多張（重播）：任一張居中都顯示同一首
    @Test func cardsOfTheSameTrackShareTheLabel() {
        let cards = [card("h:P1#0", "P1"), card("q:0:9", "P1")]
        let info = details("P1", artist: "Opeth", title: "Harvest")
        #expect(CoverFlowCenterLabel.text(centerID: "h:P1#0", cards: cards, details: info) == "Opeth // Harvest")
        #expect(CoverFlowCenterLabel.text(centerID: "q:0:9", cards: cards, details: info) == "Opeth // Harvest")
    }

    /// 分隔符是 " // "：欄位自身含 "/" 不得被誤解析（純組裝，無切分語義）
    @Test func slashesInsideFieldsArePreservedVerbatim() {
        let text = CoverFlowCenterLabel.text(
            centerID: "C1", cards: [card("C1", "P1")], details: details("P1", artist: "AC/DC", title: "T.N.T")
        )
        #expect(text == "AC/DC // T.N.T")
    }
}
