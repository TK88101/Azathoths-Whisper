import SwiftUI

/// CR-023 外殼玻璃（s6-61-f8f9-shell.md §5）：iOS 26 起用系統液態玻璃，之前退回 material。
/// 「強制 material」只有一個開關＝環境值 `forcesMaterialGlass`：預設取 DEBUG 啟動參數（模擬器驗退路），
/// 渲染基準圖測試直接設環境值（s6-5 T8）
enum GlassStyle {
    static let forcedMaterialByLaunchArgument: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(AccessibilityID.forceMaterialGlassArgument)
        #else
        false
        #endif
    }()
}

extension EnvironmentValues {
    /// true＝一律走 material 退路（基準圖測試：iOS 26 液態玻璃在 ImageRenderer 的輸出未驗）
    @Entry var forcesMaterialGlass = GlassStyle.forcedMaterialByLaunchArgument
}

/// 三種玻璃共用：iOS 26 且未被環境值關掉時用 `glassEffect`，否則退回 material
private struct GlassModifier<S: Shape>: ViewModifier {
    enum Kind { case tinted, frosted, clear }
    let kind: Kind
    let shape: S
    @Environment(\.forcesMaterialGlass) private var forcesMaterial

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !forcesMaterial {
            switch kind {
            case .tinted: content.glassEffect(.regular, in: shape)
            case .frosted: content.glassEffect(.regular.tint(.white.opacity(DockPresentation.frostTint)), in: shape)
            case .clear: content.glassEffect(.clear, in: shape)
            }
        } else {
            switch kind {
            case .tinted: content.background(.ultraThinMaterial, in: shape)
            case .frosted: content.background(.ultraThinMaterial, in: shape).background(Color.white.opacity(DockPresentation.frostTint), in: shape)
            case .clear: content.background(Color.white.opacity(DockPresentation.controlTint), in: shape)
            }
        }
    }
}

extension View {
    /// 透明有色玻璃（設定鈕、搜尋框、狀態膠囊、詳情按鈕）
    func tintedGlass(in shape: some Shape) -> some View { modifier(GlassModifier(kind: .tinted, shape: shape)) }

    /// 霧面玻璃（底部膠囊下層：乳白、不被背景染色）
    func frostedGlass(in shape: some Shape) -> some View { modifier(GlassModifier(kind: .frosted, shape: shape)) }

    /// 控制層：比下層透明、無邊線，直接透到背景只帶淡霧
    func clearGlass(in shape: some Shape) -> some View { modifier(GlassModifier(kind: .clear, shape: shape)) }
}
