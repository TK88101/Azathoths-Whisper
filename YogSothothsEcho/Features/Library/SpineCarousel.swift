import CoreGraphics
import RemoteProtocol

/// 盒子在側封的哪一側（sprint-6-detail.md §4.2）：u＝0 歸 right，旋轉、書脊邊、命中都只讀它
enum CarouselSide: Equatable, Sendable { case left, right }

/// 一個方盒的擺放：x＝盒子原點（書脊邊）在世界座標的水平位置、繞 y 軸的角度（左側正、右側負）。
/// scale 以原點為錨等比縮放、y 為垂直位移：側封恆為 1、0，只有開合轉場中飛行的那張會動（§4.5）
struct BoxPose: Equatable, Sendable {
    var x: CGFloat
    var rotationDegrees: Double
    var side: CarouselSide
    var scale: CGFloat = 1
    var y: CGFloat = 0
}

/// 側封參數的唯一真源（§4.2、D4）：預設值＝小樣使用者看過的 13 吋值（A 764、slot 145、d 1,600），其餘按 A 等比例。
/// A 以畫布高 0.74 起算（小樣以整個 1032 pt 畫布量），再夾在瀏覽區高與 0.6W 之內——13 吋實機瀏覽區比畫布矮，
/// 照字面用「瀏覽區高 × 0.74」會比使用者看過的小樣小一截（附錄 C T1 記錄）
struct SpineCarouselMetrics: Equatable, Sendable {
    static let referenceCover: CGFloat = 764
    static let referenceSlot: CGFloat = 145
    static let referencePerspective: CGFloat = 1600
    static let coverToCanvasHeight: CGFloat = 0.74
    static let coverToBrowseHeightMax: CGFloat = 0.92
    static let coverToWidthMax: CGFloat = 0.6
    static let spineToCover: CGFloat = 0.03

    let browse: CGRect
    let cover: CGFloat
    let spine: CGFloat
    let slot: CGFloat
    let perspective: CGFloat
    let spacingGrowth: CGFloat = 0.05
    let spacingExponent: CGFloat = 1.5
    let edgeDegrees: Double = 76
    let edgeU: CGFloat = 2

    init(browse: CGRect, canvasHeight: CGFloat) {
        self.browse = browse
        let cover = max(1, min(Self.coverToCanvasHeight * canvasHeight,
                               Self.coverToBrowseHeightMax * browse.height,
                               Self.coverToWidthMax * browse.width))
        self.cover = cover
        spine = Self.spineToCover * cover
        slot = Self.referenceSlot / Self.referenceCover * cover
        perspective = Self.referencePerspective / Self.referenceCover * cover
    }

    /// 消失點＝瀏覽區中心；方盒垂直置中於此
    var center: CGPoint { CGPoint(x: browse.midX, y: browse.midY) }
}

enum SpineCarousel {
    /// 地面線＝盒底（盒子垂直置中於消失點）：倒影與陰影帶以它為準（F10 E.3，小樣 CY＋A/2）
    static func floor(_ m: SpineCarouselMetrics) -> CGFloat { m.center.y + m.cover / 2 }

    static func side(u: CGFloat) -> CarouselSide { u < 0 ? .left : .right }

    /// x(u) = side · slot · (|u| + c·|u|^p)
    static func x(u: CGFloat, metrics m: SpineCarouselMetrics) -> CGFloat {
        let a = abs(u)
        let magnitude = m.slot * (a + m.spacingGrowth * pow(a, m.spacingExponent))
        return u < 0 ? -magnitude : magnitude
    }

    /// φ(a) = 90° − (90° − θe)·smoothstep(a/uₑ)；左側正（正面朝右）、右側負
    static func rotationDegrees(u: CGFloat, metrics m: SpineCarouselMetrics) -> Double {
        let s = Double(min(1, abs(u) / m.edgeU))
        let phi = 90 - (90 - m.edgeDegrees) * s * s * (3 - 2 * s)
        return side(u: u) == .left ? phi : -phi
    }

    /// 原點再往外側挪半個書脊厚：書脊在原點外側、厚 T，不挪的話跨過中央時會跳 T（附錄 C T1 記錄）
    static func pose(u: CGFloat, metrics m: SpineCarouselMetrics) -> BoxPose {
        let side = side(u: u)
        let half = m.spine / 2
        return BoxPose(x: x(u: u, metrics: m) + (side == .left ? -half : half),
                       rotationDegrees: rotationDegrees(u: u, metrics: m), side: side)
    }

    /// 槽位在 ScrollView 內前留白 W/2 − slot/2，故第 i 張的中心與可見中心相差 i·slot − offset
    static func u(index: Int, offset: CGFloat, metrics m: SpineCarouselMetrics) -> CGFloat {
        CGFloat(index) - offset / m.slot
    }

    static func zIndex(u: CGFloat) -> Double { -Double(abs(u)) }

    /// 最靠近中央的那張（夾在清單內）
    static func centerIndex(offset: CGFloat, count: Int, metrics m: SpineCarouselMetrics) -> Int {
        min(count - 1, max(0, Int((offset / m.slot).rounded())))
    }

    /// 由中央往兩側找到第一張完全在瀏覽區外的為止（x(u) 單調），再各加 1 張緩衝；不設張數上限
    static func visibleRange(offset: CGFloat, count: Int, metrics m: SpineCarouselMetrics) -> Range<Int> {
        let shown = onScreenRange(offset: offset, count: count, metrics: m)
        guard !shown.isEmpty else { return shown }
        return max(0, shown.lowerBound - 1)..<min(count, shown.upperBound + 1)
    }

    /// 開啟時其他盒的外滑方向（#6-1 v0.6 F4）：以被點那張為界，左邊的往左（−1）、右邊的往右（+1）；被點那張不在其中
    static func outward(albums: [AlbumSummary], visible: Range<Int>, target: Int) -> [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: visible.filter { $0 != target }.map { (albums[$0].id, CGFloat($0 < target ? -1 : 1)) })
    }

    /// 投影與瀏覽區相交的盒子（不含緩衝）
    static func onScreenRange(offset: CGFloat, count: Int, metrics m: SpineCarouselMetrics) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let projection = BoxProjection(metrics: m)
        let center = centerIndex(offset: offset, count: count, metrics: m)
        func onScreen(_ index: Int) -> Bool {
            let pose = pose(u: u(index: index, offset: offset, metrics: m), metrics: m)
            return projection.bounds(.front, pose: pose).union(projection.bounds(.spine, pose: pose)).intersects(m.browse)
        }
        var lower = center
        while lower > 0, onScreen(lower - 1) { lower -= 1 }
        var upper = center
        while upper < count - 1, onScreen(upper + 1) { upper += 1 }
        return lower..<(upper + 1)
    }
}
