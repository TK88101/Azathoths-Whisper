import CoreGraphics

/// 唱機畫面常數（sprint-5-detail.md §4.2、§4.2b；真源 VINYL_SPEC.md「尺寸常量」「唱臂角度」「動畫參數」＋#5-1 定案構圖 A1-XL4）。
/// 素材尺寸單位是原版 dp，使用時乘縮放 s（＝唱片直徑／474）。唱臂與底座的常數在皮膚（`TurntableSkin.classic`，S7 F-V-07）
enum TurntableMetrics {
    static let recordSize: CGFloat = 474
    // MARK: 定案構圖（§4.2b v1.6／v1.8；A1-XL4 為底＋#5-1 第 2 項回饋、可見唱片 0.96R＋縮小封套；以唱片直徑 R 為單位）

    /// R ＝ min(0.775H, W／1.72)
    static let recordHeightFraction: CGFloat = 0.775
    static let recordWidthDivisor: CGFloat = 1.72
    /// 唱片圓心距容器右緣、比垂直中線往下
    static let recordCenterRightInset: CGFloat = 0.61
    static let recordCenterDrop: CGFloat = 0.0125
    /// 畫面上的唱片＝唱片框 × 0.96（原版靜止縮放；畫面與點擊命中共用）
    static let recordVisibleScale: CGFloat = 0.96
    /// 封套邊長＝可見唱片 × 1.0475（12 吋黑膠 30.0 cm／封套 31.4 cm；#5-1 使用者實機比較後選「縮小封套」）；
    /// 中心相對唱片圓心：角度與高度照使用者 Pencil 手擺，水平讓左下角明確出框 20 pt（Codex）
    static let sleeveToRecord: CGFloat = 1.0475
    static let sleeveCenterOffset = CGPoint(x: -0.7059, y: -0.0119)
    /// 播完沒有封面時的封套：純色（原版佔位圖帶 MD 的「M」，取其最頻色 #282828）
    static let coverPlaceholderColor = RGBColor(hex: 0x282828)
    /// SwiftUI 角度：負＝逆時針（右側上揚）
    static let coverTiltDegrees: Double = -7.88
}
