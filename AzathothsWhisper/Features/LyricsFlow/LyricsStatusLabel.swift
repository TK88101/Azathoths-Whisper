import SwiftUI

/// 歌詞狀態字（設計稿：✓ Lyrics in file／✗ Missing lyrics／— Marked: no lyrics）。
/// Editor 的 Now Editing 卡片與 Cover Flow 中心下方共用，樣式只在這裡定義
struct LyricsStatusLabel: View {
    let status: LyricsStatus

    var body: some View {
        (Text(verbatim: LyricsBadge.symbol(for: status) + " ") + Text(LocalizedStringKey(LyricsBadge.statusKey(for: status))))
            .font(Theme.Fonts.mono(11))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(LyricsBadge.tone(for: status).color)
    }
}
