import Foundation

/// 一首歌的歌詞狀態（計劃 §5.2）。由（檔內歌詞, 無詞標記）推導，不存。
///
/// `unknown`＝沒讀到——**不得折疊成 `missing`**：把「沒讀到」當成「沒有」，新介面就會把有詞的歌
/// 降下成 Editor，使用者一按 Write 便覆蓋掉原本的詞。
enum LyricsStatus: Equatable, Sendable {
    case present
    case missing
    case markedNone
    case unknown

    /// 優先序：檔內有詞 ＞ 已標記 ＞ 缺詞。`lyrics == nil`＝讀取失敗。
    /// 純空白＝缺詞（C-29，判定見 `LyricsText`）
    static func resolve(lyrics: String?, isMarked: Bool) -> LyricsStatus {
        guard let lyrics else { return .unknown }
        if !LyricsText.isBlank(lyrics) { return .present }
        return isMarked ? .markedNone : .missing
    }
}
