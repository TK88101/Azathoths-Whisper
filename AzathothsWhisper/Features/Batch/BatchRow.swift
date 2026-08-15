import SwiftUI

// Batch 列表單行（py:564-601）：補零序號／artist／title／狀態點。
// 序號來自呼叫端傳入的列表索引，與 trackNumber 無關（C-04）。
struct BatchRow: View {
    let number: String
    let track: AlbumTrack
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: number)
                .foregroundStyle(isHovering ? Color.white : Theme.Gray.g600)
                .frame(width: 48)                              // w-12
                .padding(.vertical, 12)                        // py-3

            cell(track.artist, color: isHovering ? .white : Theme.Gray.g400)

            cell(track.title, color: .white, weight: .bold)

            statusDot
                .frame(width: 96)                              // w-24
                .padding(.vertical, 12)
        }
        .font(Theme.Fonts.mono(12))                            // font-mono text-xs
        .background(background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border.opacity(0.5))               // border-border-dark/50
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
    }

    private func cell(_ text: String, color: Color, weight: Font.Weight = .regular) -> some View {
        Text(verbatim: text)
            .fontWeight(weight)
            .lineLimit(1)
            .truncationMode(.tail)                             // truncate
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)                          // px-4
    }

    /// py:587-593：有詞＝白點（Has Lyrics）／缺詞＝暗紅點（Missing）。
    /// 缺詞判定收攏在 AlbumTrack.hasLyrics（C-29：純空白算缺詞）
    private var statusDot: some View {
        Circle()
            .fill(track.hasLyrics ? Color.white : Theme.dangerDeep)
            .frame(width: 8, height: 8)                        // w-2 h-2
            .help(track.hasLyrics ? "Has Lyrics" : "Missing")  // title 屬性
    }

    private var background: Color {
        if isSelected { return Color.white.opacity(0.1) }      // py:567 bg-white/10
        return isHovering ? Color.white.opacity(0.05) : .clear // hover:bg-white/5
    }
}
