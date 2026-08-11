import SwiftUI

// Fetch / Save 按鈕（py:165-178）：
//   border-gray-600 hover:border-white、px-8 py-2.5、300ms
//   內部白遮罩 translate-y-full → 0（由下往上滑入）＋ mix-blend-difference
//   文字 hover 反色（group-hover:text-black）
struct ActionButton: View {
    let symbol: MaterialSymbolName
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var isHot: Bool { isHovering && isEnabled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                MaterialSymbol(symbol, size: 18)
                Text(title)
                    .font(Theme.Fonts.display(14, weight: .bold))
                    .tracking(1.4)              // tracking-[0.1em] @ 14px
            }
            .textCase(.uppercase)
            .foregroundStyle(isHot ? Color.black : Color.white)
            .padding(.horizontal, 32)           // px-8
            .padding(.vertical, 10)             // py-2.5
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
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.3), value: isHot)
        .animation(.easeInOut(duration: 0.3), value: isEnabled)
    }
}
