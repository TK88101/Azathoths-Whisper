import Foundation

// H-03：中心下方標籤 `ARTIST // TITLE`（Plan §4.8）。
//
// 提為純函數是為了可測：原先它是 `CoverFlowView` 的 private computed property，
// 唯一的外部觀測點是 `.accessibilityLabel`——而 View 上的 `.textCase(.uppercase)`
// 只作用於渲染，不改回傳值。對 accessibilityLabel 斷言「大寫」會假失敗（M8 三角評審 #B5）。
// 這裡只負責組裝，大小寫與 mono 排版留在 View。
enum CoverFlowCenterLabel {
    /// 無中心曲目（牌組空、centerID 不在牌組裡、或該曲詳情尚未讀到）時的佔位
    static let placeholder = "--"

    static func text(centerID: String?, cards: [DeckCard], details: [String: TrackDetails]) -> String {
        guard let centerID,
              let card = cards.first(where: { $0.id == centerID }),
              let info = details[card.persistentID]
        else { return placeholder }
        return "\(info.artist) // \(info.title)"
    }
}
