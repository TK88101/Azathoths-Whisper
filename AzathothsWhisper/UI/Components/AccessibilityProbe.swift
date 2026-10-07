#if DEBUG
import SwiftUI

/// UITests 讀狀態用的探針：1pt 透明文字，a11y value 承載狀態。
/// 用文字而非色塊：文字必定是 AX 元素，UITests 讀得到它的 value（色塊實測沒有 value）；
/// 容器（`children: .contain`）上的 value 會被 SwiftUI 吞掉（2026-09-23 實測），所以另設這個元素
struct AccessibilityProbe: View {
    let id: String
    let value: String

    var body: some View {
        Text(verbatim: value)
            .font(.system(size: 1))
            .foregroundStyle(Color.clear)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityIdentifier(id)
            .accessibilityValue(value)
    }
}
#endif
