import SwiftUI

/// 把手右端的兩格圖示按鈕（A2 計劃 §3.2）：只換升起層畫面，不升降。不加選單項、不加快捷鍵（母計劃 §9-C）
struct RaisedLayerStyleToggle: View {
    static let cellSize: CGFloat = 28

    let selected: RaisedLayerStyle
    let onSelect: (RaisedLayerStyle) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RaisedLayerStyle.allCases, id: \.self) { style in
                cell(style)
            }
        }
        .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func cell(_ style: RaisedLayerStyle) -> some View {
        let isSelected = style == selected
        return Button { onSelect(style) } label: {
            Image(systemName: Self.symbol(style))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Theme.Gray.g500)
                .frame(width: Self.cellSize, height: Self.cellSize)
                .background(isSelected ? Theme.Gray.g800 : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(LyricsFlowHandle.styleIdentifier(style))
        .accessibilityLabel(Text(LocalizedStringKey(LyricsFlowHandle.styleLabelKey(style))))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func symbol(_ style: RaisedLayerStyle) -> String {
        switch style {
        case .coverFlow: return "square.stack"
        case .lyricsFX: return "text.alignleft"
        }
    }
}
