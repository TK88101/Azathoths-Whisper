import CoreGraphics

/// Cover Flow 的 3D 幾何計算（上游 Plan §4.8 的參數逐項對照）。
///
/// 抽成純函數而非寫死在 View 裡：幾何可完全單測，View 只負責把結果套進
/// `rotation3DEffect`／`scaleEffect`／`zIndex`。這也是 P1-0「先驗幾何、後接資料」的落地形式
/// ——公式由測試釘住，吸附行為／實際疊放次序／resize 觀感屬目視項，待 M8 並排對照（同 H-02 口徑）。
struct CoverFlowGeometry {
    /// 單張封面寬度；同時是距離歸一化的單位
    let itemWidth: CGFloat

    // MARK: 規格常數（§4.8）

    /// 兩側斜角上限。負值＝右側向左轉，左側取反
    private static let maxRotationDegrees: CGFloat = 55
    /// 兩側最小縮放
    private static let minScale: CGFloat = 0.82
    /// 負間距覆疊比例
    private static let overlapRatio: CGFloat = -0.42

    let perspective: CGFloat = 0.55

    /// `LazyHStack` 的間距：負值造成覆疊
    var spacing: CGFloat { Self.overlapRatio * itemWidth }

    // MARK: 距離

    /// 以 itemWidth 為單位的帶號距離：中心為 0，右側為正、左側為負。
    /// 不 clamp——呼叫端可能需要原始距離（例如判斷是否在預取範圍內）。
    func normalizedDistance(itemMidX: CGFloat, viewportMidX: CGFloat) -> CGFloat {
        guard itemWidth > 0 else { return 0 }
        return (itemMidX - viewportMidX) / itemWidth
    }

    // MARK: 變換

    /// −55° × clamp(d, −1, 1)。**必須 clamp**：不 clamp 的話遠處項目會無限旋轉翻面
    func rotationDegrees(forDistance d: CGFloat) -> CGFloat {
        -Self.maxRotationDegrees * clamped(d)
    }

    /// 1.0（中心）→ 0.82（一個 itemWidth 外），線性插值後 clamp
    func scale(forDistance d: CGFloat) -> CGFloat {
        let t = min(abs(d), 1)
        return 1.0 + (Self.minScale - 1.0) * t
    }

    /// −|d|：中心在最上層，兩側對稱下沉
    func zIndex(forDistance d: CGFloat) -> Double {
        -Double(abs(d))
    }

    /// 依**畫面位置**的疊放層級（H-02 缺陷 2）：距離先換算成「離中心第幾個卡位」再取 −|卡位|。
    /// 用卡位而非連續距離：捲動時只在越過兩卡中點的那一刻改值，不逐幀寫狀態
    func stackingOrder(forDistance d: CGFloat) -> Double {
        let strideRatio = 1 + Self.overlapRatio
        return zIndex(forDistance: (d / strideRatio).rounded())
    }

    /// 可點判定的容差（計劃 D6、N2）：|d| ≤ 0.2 個卡寬才算「在正中」。
    /// 相鄰兩卡相距 0.58 個卡寬，捲動跨中點途中沒有任何卡落在容差內——不會點到正在滑過的卡
    static let centeredTolerance: CGFloat = 0.2

    func isCentered(forDistance d: CGFloat) -> Bool {
        abs(d) <= Self.centeredTolerance
    }

    /// 正中那張的封面正面（不含倒影）：卡片在條帶內垂直置中，高＝邊長 ×（1＋倒影比）。
    /// 點擊、懸停、無障礙按鈕都以它為準（D6、AC3）
    func centreFace(in stripSize: CGSize, reflectionRatio: CGFloat) -> CGRect {
        let cardHeight = itemWidth * (1 + reflectionRatio)
        return CGRect(x: (stripSize.width - itemWidth) / 2, y: (stripSize.height - cardHeight) / 2,
                      width: itemWidth, height: itemWidth)
    }

    /// AC3 的最終許可：播放卡位於幾何正中（條帶回報給 VM）∧ 點在它的封面正面內
    static func acceptsPlayingCardTap(isCentered: Bool, location: CGPoint, face: CGRect) -> Bool {
        isCentered && face.contains(location)
    }

    /// 旋轉錨點：左側項目繞右緣轉、右側項目繞左緣轉，才有「向中心翻開」的觀感
    func anchorIsTrailing(forDistance d: CGFloat) -> Bool {
        d < 0
    }

    // MARK: 佈局

    /// 左右邊距，使**首尾項**也能滑到視口中心。
    /// 視窗比單項還窄時回 0——負 padding 會讓佈局炸開
    func edgePadding(viewWidth: CGFloat) -> CGFloat {
        max(0, (viewWidth - itemWidth) / 2)
    }

    private func clamped(_ d: CGFloat) -> CGFloat {
        min(max(d, -1), 1)
    }
}
