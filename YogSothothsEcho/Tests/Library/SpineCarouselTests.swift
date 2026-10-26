import CoreGraphics
import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// S6 T1（sprint-6-detail.md §4.2、D4）：側封幾何。13 吋＝畫布 1376×1032、瀏覽區 1376×860（頂列與播放列之間）
struct SpineCarouselTests {
    static let pro13 = SpineCarouselMetrics(browse: CGRect(x: 0, y: 0, width: 1376, height: 860), canvasHeight: 1032)
    static let pro11 = SpineCarouselMetrics(browse: CGRect(x: 0, y: 0, width: 1210, height: 662), canvasHeight: 834)

    /// 預設參數＝小樣使用者看過的值（13 吋：A 764、T 0.03A、slot 145、d 1,600）
    @Test func defaultsMatchPreview() {
        let m = Self.pro13
        #expect(abs(m.cover - 764) < 0.5)
        #expect(abs(m.spine - 0.03 * 764) < 0.01)
        #expect(abs(m.slot - 145) < 1)   // A＝0.74×1032＝763.68，slot、d 按 A 等比例
        #expect(abs(m.perspective - 1600) < 1)
        #expect(m.center == CGPoint(x: 688, y: 430))
    }

    /// 瀏覽區太矮或太窄時封面縮小，不超出瀏覽區；slot、d 跟著 A 等比例
    @Test func coverClampsToBrowseArea() {
        let short = SpineCarouselMetrics(browse: CGRect(x: 0, y: 0, width: 1376, height: 600), canvasHeight: 1032)
        #expect(short.cover <= 600)
        #expect(abs(short.slot / short.cover - 145.0 / 764) < 1e-6)
        let narrow = SpineCarouselMetrics(browse: CGRect(x: 0, y: 0, width: 900, height: 860), canvasHeight: 1032)
        #expect(narrow.cover <= 0.6 * 900 + 1e-6)
    }

    @Test func positionIsStrictlyIncreasingAndOdd() {
        let m = Self.pro13
        var previous = -CGFloat.infinity
        for step in -80...80 {
            let u = CGFloat(step) / 10
            let x = SpineCarousel.x(u: u, metrics: m)
            #expect(x > previous)
            #expect(abs(x + SpineCarousel.x(u: -u, metrics: m)) < 1e-9)
            previous = x
        }
        // 越往外間距越大（p > 1）
        let gap1 = SpineCarousel.x(u: 2, metrics: m) - SpineCarousel.x(u: 1, metrics: m)
        let gap5 = SpineCarousel.x(u: 6, metrics: m) - SpineCarousel.x(u: 5, metrics: m)
        #expect(gap5 > gap1)
    }

    @Test func sideOfZeroIsRight() {
        #expect(SpineCarousel.side(u: 0) == .right)
        #expect(SpineCarousel.side(u: -1e-9) == .left)
        #expect(SpineCarousel.side(u: 3) == .right)
    }

    @Test func rotationStaysBetweenEdgeAngleAndNinety() {
        let m = Self.pro13
        for step in -60...60 {
            let u = CGFloat(step) / 10
            let r = SpineCarousel.rotationDegrees(u: u, metrics: m)
            #expect(abs(r) >= 76 - 1e-9 && abs(r) <= 90 + 1e-9)
        }
        #expect(abs(abs(SpineCarousel.rotationDegrees(u: 0, metrics: m)) - 90) < 1e-9)
        #expect(abs(abs(SpineCarousel.rotationDegrees(u: 2, metrics: m)) - 76) < 1e-9)
        #expect(abs(abs(SpineCarousel.rotationDegrees(u: 5, metrics: m)) - 76) < 1e-9)
    }

    /// 左側盒正面朝右（朝中心）、右側朝左；兩側書脊都朝使用者
    @Test func facesPointTheRightWay() {
        let m = Self.pro13
        let projection = BoxProjection(metrics: m)
        for u: CGFloat in [-3, -1, -0.4, 0.4, 1, 3] {
            let pose = SpineCarousel.pose(u: u, metrics: m)
            let front = projection.normal(.front, pose: pose)
            let spine = projection.normal(.spine, pose: pose)
            if u < 0 { #expect(front.x > 0) } else { #expect(front.x < 0) }
            #expect(spine.z > 0)
        }
    }

    /// 書脊印在外側邊：左側盒的書脊在正面左邊、右側盒在右邊
    @Test func spineSitsOnTheOuterEdge() {
        let m = Self.pro13
        let projection = BoxProjection(metrics: m)
        for u: CGFloat in [-4, -1.5, -0.6, 0.6, 1.5, 4] {
            let pose = SpineCarousel.pose(u: u, metrics: m)
            let spine = projection.bounds(.spine, pose: pose)
            let front = projection.bounds(.front, pose: pose)
            if u < 0 { #expect(spine.midX < front.midX) } else { #expect(spine.midX > front.midX) }
        }
    }

    /// 跨過中央時書脊不跳位
    @Test func spineIsContinuousAcrossCenter() {
        let m = Self.pro13
        let projection = BoxProjection(metrics: m)
        let center = projection.bounds(.spine, pose: SpineCarousel.pose(u: 0, metrics: m))
        for u: CGFloat in [-1e-6, 1e-6] {
            let near = projection.bounds(.spine, pose: SpineCarousel.pose(u: u, metrics: m))
            #expect(abs(near.minX - center.minX) <= 0.5 && abs(near.maxX - center.maxX) <= 0.5)
            #expect(abs(near.minY - center.minY) <= 0.5 && abs(near.maxY - center.maxY) <= 0.5)
        }
    }

    @Test func nearerBoxesDrawOnTop() {
        #expect(SpineCarousel.zIndex(u: 0) > SpineCarousel.zIndex(u: 0.5))
        #expect(SpineCarousel.zIndex(u: -0.5) > SpineCarousel.zIndex(u: -1.5))
        #expect(SpineCarousel.zIndex(u: 2) == SpineCarousel.zIndex(u: -2))
    }

    /// 中央盒只露書脊：投影寬 ≈ T（±10%），13 吋與 11 吋
    @Test func centerBoxShowsOnlyTheSpine() {
        for m in [Self.pro13, Self.pro11] {
            let projection = BoxProjection(metrics: m)
            let pose = SpineCarousel.pose(u: 0, metrics: m)
            let spine = projection.bounds(.spine, pose: pose)
            #expect(abs(spine.width - m.spine) <= 0.1 * m.spine)
            #expect(abs(spine.midX - m.center.x) <= 0.5)
            #expect(!projection.isFacingViewer(.front, pose: pose) || projection.bounds(.front, pose: pose).width < 1)
        }
    }

    @Test func slotPositionFollowsOffset() {
        let m = Self.pro13
        #expect(SpineCarousel.u(index: 0, offset: 0, metrics: m) == 0)
        #expect(abs(SpineCarousel.u(index: 3, offset: m.slot, metrics: m) - 2) < 1e-9)
        #expect(abs(SpineCarousel.u(index: 0, offset: m.slot / 2, metrics: m) + 0.5) < 1e-9)
    }

    @Test func visibleRangeCoversOnlyBoxesOnScreen() {
        let m = Self.pro13
        #expect(SpineCarousel.visibleRange(offset: 0, count: 0, metrics: m).isEmpty)
        #expect(SpineCarousel.visibleRange(offset: 0, count: 1, metrics: m) == 0..<1)
        let offset = 500 * m.slot
        let range = SpineCarousel.visibleRange(offset: offset, count: 1000, metrics: m)
        #expect(range.contains(500) && range.count < 60)
        let projection = BoxProjection(metrics: m)
        // 範圍外第一張已完全在瀏覽區外；範圍內最外一張（扣緩衝）仍有一部分在內
        for index in [range.lowerBound - 1, range.upperBound] {
            let pose = SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: offset, metrics: m), metrics: m)
            let frame = projection.bounds(.front, pose: pose).union(projection.bounds(.spine, pose: pose))
            #expect(!frame.intersects(m.browse))
        }
        for index in [range.lowerBound + 1, range.upperBound - 2] {
            let pose = SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: offset, metrics: m), metrics: m)
            let frame = projection.bounds(.front, pose: pose).union(projection.bounds(.spine, pose: pose))
            #expect(frame.intersects(m.browse))
        }
        // 頭尾夾住
        #expect(SpineCarousel.visibleRange(offset: 0, count: 1000, metrics: m).lowerBound == 0)
        #expect(SpineCarousel.visibleRange(offset: 999 * m.slot, count: 1000, metrics: m).upperBound == 1000)
    }

    /// 開啟時其他盒的外滑方向：以被點那張為界左左右右，被點那張不在其中
    @Test func outwardSplitsAtTheTarget() {
        let albums = (0..<10).map { AlbumSummary(id: "\($0)", title: "", artist: "", trackCount: 1, artworkToken: nil) }
        let out = SpineCarousel.outward(albums: albums, visible: 2..<8, target: 4)
        #expect(out == ["2": -1, "3": -1, "5": 1, "6": 1, "7": 1])
        #expect(SpineCarousel.outward(albums: albums, visible: 0..<3, target: 0) == ["1": 1, "2": 1])
    }
}
