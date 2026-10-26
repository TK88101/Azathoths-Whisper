import SwiftUI

/// 播放控制按鈕：每按一下都給即時回饋（使用者的範本是 Music 迷你播放器，2026-10-18 錄影）——
/// 按住時背後灰色圓底、放開淡出；上一首／下一首的三角形往按的方向滑一格（出去的縮小淡出、進來的由小變大）。
/// 等待回覆期間按鈕不變淡（使用者會以為按了無效）；等得比正常久才在角落轉圈
struct TransportButton: View {
    enum Glyph { case skip(forward: Bool), symbol(String), genius }

    let glyph: Glyph
    let label: LocalizedStringKey
    let id: String
    let pendingCount: Int
    let isSlow: Bool
    /// 播放列（舊）／底部控制層（CR-023：圖示較小、點擊區仍 ≥ 44 pt）
    var size: Size = .bar
    /// VoiceOver 提示（Genius 未授權時說明要去 Mac 允許）
    var hint: LocalizedStringKey?
    let action: @MainActor () async -> Void

    enum Size { case bar, dock }

    /// 底部控制層：點擊框比圖示寬的部分（右緣對齊用）
    static let dockHitInset: CGFloat = (44 - DockPresentation.skipIconSide) / 2

    @State private var presses = 0
    /// 真的停用（無權限、Music 未開、斷線）才變灰；等待回覆中 isEnabled 仍為 true、不變淡（F15）
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            presses += 1
            Task { await action() }
        } label: {
            icon
                .foregroundStyle(isEnabled ? .primary : .tertiary)   // 三個按鈕同一個顏色（跟著系統文字色）
                .frame(width: size == .dock ? 44 : 48, height: size == .dock ? 44 : 48)
                .overlay(alignment: .bottomTrailing) {
                    if isSlow { ProgressView().controlSize(.mini) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressCircleStyle())
        .accessibilityLabel(label)
        .accessibilityValue(pendingCount > 0 ? Text("Waiting: \(pendingCount)") : Text(verbatim: ""))
        .accessibilityHint(hint.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityIdentifier(id)
    }

    /// 播放鍵比上一首／下一首大（Music 的比例：跳曲的三角形高約為播放鍵的 0.7）
    @ViewBuilder private var icon: some View {
        switch glyph {
        case .skip(let forward):
            SkipGlyph()
                .keyframeAnimator(initialValue: 0.0, trigger: presses) { _, phase in SkipGlyph(phase: phase) } keyframes: { _ in
                    CubicKeyframe(1, duration: 0.3)
                }
                .scaleEffect(x: forward ? 1 : -1)
                .frame(width: size == .dock ? DockPresentation.skipIconSide : 30, height: size == .dock ? 13 : 18)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size == .dock ? 24 : 30))
                .symbolEffect(.bounce, value: presses)
        case .genius:
            // 比 ▶／❚❚ 的視覺高（約 20 pt）稍小：18 pt（使用者 2026-10-24 在場指定）
            GeniusGlyph()
                .frame(width: size == .dock ? 18.6 : 24, height: size == .dock ? 18 : 23)
                .keyframeAnimator(initialValue: 1.0, trigger: presses) { glyph, scale in glyph.scaleEffect(scale) } keyframes: { _ in
                    CubicKeyframe(0.85, duration: 0.1)
                    CubicKeyframe(1, duration: 0.2)
                }
        }
    }
}

/// 按住時背後浮出灰色圓底，放開後約 0.25 s 淡出（Music 錄影逐格：按下即出現、放開才淡）
private struct PressCircleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Color.primary.opacity(0.12))
                    .opacity(configuration.isPressed ? 1 : 0)
                    .animation(configuration.isPressed ? nil : .easeOut(duration: 0.25), value: configuration.isPressed)
            }
    }
}

/// ▶▶：三個三角形放在 -1／0／1 格，可見的是 0、1 格；phase 0→1 時整排往前滑一格——
/// 最前一個邊縮小邊淡出、後面空位長出一個由小變大淡入的新三角形（Music 錄影逐格，每格 25 ms，全程約 0.3 s）。
/// phase 1 的樣子與 phase 0 相同，所以動畫結束跳回 0 看不出接縫
private struct SkipGlyph: View {
    var phase: Double = 0
    private static let smallest = 0.3

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 2
            ZStack(alignment: .leading) {
                ForEach([-1.0, 0, 1], id: \.self) { slot in
                    let position = slot + phase
                    let visible = min(max(min(position + 1, 2 - position), 0), 1)
                    Image(systemName: "play.fill")   // 與播放鍵同一個系統三角形：顏色、圓角一致（自畫的 Shape 在按鈕裡會被染成灰）
                        .resizable()
                        .frame(width: width, height: geometry.size.height)
                        .scaleEffect(Self.smallest + (1 - Self.smallest) * visible)
                        .opacity(visible)
                        .offset(x: position * width)
                }
            }
        }
    }
}
