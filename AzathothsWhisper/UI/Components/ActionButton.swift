import SwiftUI

// Fetch / Save 按鈕（py:165-178）：
//   border-gray-600 hover:border-white、px-8 py-2.5、300ms
//   內部白遮罩 translate-y-full → 0（由下往上滑入）＋ mix-blend-difference
//   文字 hover 反色（group-hover:text-black）
struct ActionButton: View {
    let symbol: MaterialSymbolName
    let title: String
    let isEnabled: Bool
    // Batch 的三個按鈕較小（py:243 px-5 py-2 text-xs，圖示 14px）；預設值＝Editor 尺寸
    var horizontalPadding: CGFloat = 32
    var verticalPadding: CGFloat = 10
    var fontSize: CGFloat = 14
    var symbolSize: CGFloat = 18
    /// 供 XCUITest 定位：預設的 accessibility label 會混入 MaterialSymbol 的連字文本
    /// （如 "done_all IMPORT ALL"），且隨語言變動，不適合當定位鍵
    var accessibilityID: String?
    let action: () -> Void

    @State private var isHovering = false

    private var isHot: Bool { isHovering && isEnabled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                MaterialSymbol(symbol, size: symbolSize)
                Text(title)
                    .font(Theme.Fonts.display(fontSize, weight: .bold))
                    .tracking(fontSize * 0.1)   // tracking-[0.1em]
            }
            .textCase(.uppercase)
            .foregroundStyle(isHot ? Color.black : Color.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            // 白遮罩走 background：background 不參與尺寸協商，按鈕才會保持內容大小
            .background {
                GeometryReader { proxy in
                    Color.white
                        .offset(y: isHot ? 0 : proxy.size.height)
                        .blendMode(.difference)
                }
            }
            .compositingGroup()
            .clipped()
            .overlay(Rectangle().strokeBorder(isHot ? Color.white : Theme.Gray.g600, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)       // py:413 busy → opacity-50
        }
        .buttonStyle(.plain)
        // 只在有值時掛 identifier：塞空字串會讓 XCUITest 的元素查詢改按 identifier 比對，
        // 連帶使其他以 label 定位的查詢失效（2026-08-14 實測）
        .modifier(OptionalAccessibilityIdentifier(id: accessibilityID))
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.3), value: isHot)
        .animation(.easeInOut(duration: 0.3), value: isEnabled)
    }
}

/// 只在 id 非 nil 時套用 accessibilityIdentifier
private struct OptionalAccessibilityIdentifier: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}
