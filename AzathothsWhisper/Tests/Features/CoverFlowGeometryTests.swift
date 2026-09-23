import Foundation
import Testing

@testable import AzathothsWhisper

// Cover Flow 的 3D 幾何（上游 Plan §4.8）。
//
// 為何抽成純函數：P1-0 spike 的目的是「先驗 API 與幾何，後接資料」。
// 幾何公式可完全單測，API 可用性由編譯驗證；只有吸附行為／3D 疊放次序／resize
// 屬目視項（與 H-02 同口徑，待 M8 並排對照）。
@Suite("CoverFlowGeometry")
struct CoverFlowGeometryTests {
    private let itemWidth: CGFloat = 220

    // MARK: 歸一化距離

    /// 中心項的 d 為 0
    @Test func centerItemHasZeroDistance() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.normalizedDistance(itemMidX: 500, viewportMidX: 500) == 0)
    }

    /// 右側一個 itemWidth 處 d 為 1；左側為 -1
    @Test func distanceIsMeasuredInItemWidths() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.normalizedDistance(itemMidX: 500 + itemWidth, viewportMidX: 500) == 1)
        #expect(g.normalizedDistance(itemMidX: 500 - itemWidth, viewportMidX: 500) == -1)
    }

    // MARK: 旋轉（§4.8：-55° × clamp(d)）

    @Test func centerItemFacesFront() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.rotationDegrees(forDistance: 0) == 0)
    }

    /// 兩側斜角 ±55°；符號相反（右側向左轉、左側向右轉）
    @Test func sideItemsRotateFiftyFiveDegrees() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.rotationDegrees(forDistance: 1) == -55)
        #expect(g.rotationDegrees(forDistance: -1) == 55)
    }

    /// 超過一個 itemWidth 的距離要 clamp，不得無限旋轉
    @Test func rotationIsClampedBeyondOneItemWidth() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.rotationDegrees(forDistance: 5) == -55)
        #expect(g.rotationDegrees(forDistance: -5) == 55)
    }

    // MARK: 縮放（§4.8：1.0 → 0.82）

    @Test func centerItemIsFullScale() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.scale(forDistance: 0) == 1.0)
    }

    @Test func sideItemsScaleDownToPointEightTwo() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(abs(g.scale(forDistance: 1) - 0.82) < 0.0001)
        #expect(abs(g.scale(forDistance: -1) - 0.82) < 0.0001)
    }

    @Test func scaleIsClampedBeyondOneItemWidth() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(abs(g.scale(forDistance: 3) - 0.82) < 0.0001)
    }

    // MARK: 疊放（§4.8：zIndex = -|d|，中心在最上層）

    @Test func centerItemStacksOnTop() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.zIndex(forDistance: 0) > g.zIndex(forDistance: 1))
        #expect(g.zIndex(forDistance: 0) > g.zIndex(forDistance: -1))
    }

    /// 左右對稱：同樣距離的兩側疊放層級相同
    @Test func stackingIsSymmetric() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.zIndex(forDistance: 1) == g.zIndex(forDistance: -1))
    }

    // MARK: 依畫面位置疊放（H-02 缺陷 2：疊放不得跟 centerID 走）

    /// 相鄰兩卡中心距（以 itemWidth 為單位）＝1 + 覆疊比例
    private let strideRatio: CGFloat = 0.58

    /// 不論捲到哪，離視口中心最近的那張（|d| < 半個卡距）都壓在左右鄰張之上
    @Test(arguments: [-0.28, -0.15, 0, 0.15, 0.28] as [CGFloat])
    func nearestCardStacksAboveNeighbours(offset: CGFloat) {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        let center = g.stackingOrder(forDistance: offset)
        #expect(center > g.stackingOrder(forDistance: offset + strideRatio))
        #expect(center > g.stackingOrder(forDistance: offset - strideRatio))
    }

    /// 愈遠愈下沉：鄰張壓在次鄰張之上
    @Test func fartherSlotsStackLower() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.stackingOrder(forDistance: strideRatio) > g.stackingOrder(forDistance: 2 * strideRatio))
        #expect(g.stackingOrder(forDistance: -strideRatio) > g.stackingOrder(forDistance: -2 * strideRatio))
    }

    /// 同一個卡位內層級不變——捲動時只在越過兩卡中點的那一刻換層，不逐幀改值
    @Test func stackingIsConstantWithinASlot() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.stackingOrder(forDistance: 0.05) == g.stackingOrder(forDistance: 0.25))
        #expect(g.stackingOrder(forDistance: 0.40) == g.stackingOrder(forDistance: 0.75))
    }

    @Test func positionalStackingIsSymmetric() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.stackingOrder(forDistance: strideRatio) == g.stackingOrder(forDistance: -strideRatio))
    }

    // MARK: 錨點（§4.8：d < 0 用 .trailing，否則 .leading）

    @Test func anchorFollowsSideOfCenter() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.anchorIsTrailing(forDistance: -1))
        #expect(!g.anchorIsTrailing(forDistance: 1))
    }

    // MARK: 佈局常數

    /// 負間距覆疊：-0.42 × itemWidth
    @Test func spacingIsNegativeOverlap() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(abs(g.spacing - (-0.42 * itemWidth)) < 0.0001)
    }

    /// 首尾項可達中心：左右各留 (viewWidth - itemWidth) / 2
    @Test func edgePaddingLetsFirstAndLastReachCenter() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.edgePadding(viewWidth: 1000) == (1000 - itemWidth) / 2)
    }

    /// 視窗比單項還窄時不得回負值（resize 到極窄會讓佈局炸開）
    @Test func edgePaddingNeverNegative() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(g.edgePadding(viewWidth: 100) == 0)
    }

    // MARK: 透視

    @Test func perspectiveMatchesSpec() {
        let g = CoverFlowGeometry(itemWidth: itemWidth)
        #expect(abs(g.perspective - 0.55) < 0.0001)
    }

    // MARK: D6／AC3：正中那張的封面正面＝點擊與懸停的判定區，也是無障礙按鈕蓋住的範圍

    @Test func centreFaceIsTheSquareFrontOfTheCentredCard() {
        let ratio = CoverFlowItem.reflectionRatio
        let face = CoverFlowGeometry(itemWidth: 260).centreFace(in: CGSize(width: 1000, height: 600), reflectionRatio: ratio)
        let cardHeight = 260 * (1 + ratio)
        #expect(face == CGRect(x: 370, y: (600 - cardHeight) / 2, width: 260, height: 260))
        // 正面在卡片上端、下方留倒影：無障礙層的空白高度（寬 × 倒影比）與此同一比例
        #expect(face.maxY + 260 * ratio == (600 + cardHeight) / 2)
    }

    @Test("點擊只在播放卡位於正中、且落在正面內才算（CGRect 半開區間）", arguments: [
        (false, CGPoint(x: 500, y: 300), false),
        (true, CGPoint(x: 369, y: 300), false),
        (true, CGPoint(x: 500, y: 300), true),
        (true, CGPoint(x: 370, y: 200), true),
        (true, CGPoint(x: 630, y: 300), false),
        (true, CGPoint(x: 500, y: 460), false),
    ])
    func playingCardTapNeedsCentreAndFace(isCentered: Bool, location: CGPoint, accepted: Bool) {
        let face = CGRect(x: 370, y: 200, width: 260, height: 260)
        #expect(CoverFlowGeometry.acceptsPlayingCardTap(isCentered: isCentered, location: location, face: face) == accepted)
    }
}
