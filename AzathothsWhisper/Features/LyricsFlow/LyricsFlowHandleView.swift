import SwiftUI

extension LyricsBadge.Tone {
    /// 設計稿：有詞綠、缺詞紅、已標記與讀不到灰
    var color: Color {
        switch self {
        case .present: return Theme.success
        case .missing: return Theme.danger
        case .marked, .unknown: return Theme.Gray.g400
        }
    }
}

/// Cover Flow 頂端的把手（計劃 Q4；設計稿 64pt）：升降兩態皆顯示——降下時只露這一條。
/// 左＝標題與箭頭（升起時向下＝收起），中＝每張卡一道刻度（播過的短、接下來的長、播放中白色）
struct LyricsFlowHandleView: View {
    static let height: CGFloat = 64

    let isRaised: Bool
    let ticks: [HandleTick]
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: isRaised ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                    Text("nav_coverflow")
                }
                .font(Theme.Fonts.display(11))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(isHovering ? Color.white : Theme.Gray.g500)
                .fixedSize()

                tickRow
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(Theme.cardBackground)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier(AccessibilityID.lyricsFlowHandle)
        .accessibilityLabel(Text(isRaised ? "coverflow_hide" : "coverflow_show"))
    }

    private var tickRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                tickMark(tick)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private func tickMark(_ tick: HandleTick) -> some View {
        let look = tick.appearance
        return Rectangle()
            .fill(tickColor(look.palette))
            .frame(width: look.width, height: look.height)
            .shadow(color: look.glows ? .white.opacity(0.6) : .clear, radius: 4)
    }

    /// 刻度的色票（與徽章的 `LyricsBadge.Tone.color` 是兩套：刻度不強調「有詞」）
    private func tickColor(_ palette: TickAppearance.Palette) -> Color {
        switch palette {
        case .bright: return .white
        case .danger: return Theme.danger
        case .dim: return Theme.Gray.g600
        case .muted: return Theme.Gray.g400
        }
    }
}
