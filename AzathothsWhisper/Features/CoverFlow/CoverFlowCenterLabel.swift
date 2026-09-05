import Foundation

// H-03：中心下方標籤 `ARTIST // TITLE`（Plan §4.8）。
//
// 提為純函數是為了可測：原先它是 `CoverFlowView` 的 private computed property，
// 唯一的外部觀測點是 `.accessibilityLabel`——而 View 上的 `.textCase(.uppercase)`
// 只作用於渲染，不改回傳值。對 accessibilityLabel 斷言「大寫」會假失敗（M8 三角評審 #B5）。
// 這裡只負責組裝，大小寫與 mono 排版留在 View。
enum CoverFlowCenterLabel {
    /// 無中心曲目（列表空、或 centerID 不在列表裡）時的佔位
    static let placeholder = "--"

    static func text(centerID: String?, items: [AlbumTrack]) -> String {
        guard let centerID,
              let track = items.first(where: { $0.persistentID == centerID })
        else { return placeholder }
        return "\(track.artist) // \(track.title)"
    }
}
