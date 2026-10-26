import CoreGraphics
import Testing

@testable import YogSothothsEcho

// S6 T2（sprint-6-detail.md D6、§4.2）：點 → 盒子 index；以投影四邊形判定，重疊取前者
struct CarouselHitTestTests {
    let m = SpineCarouselTests.pro13
    let offset: CGFloat = 10 * SpineCarouselTests.pro13.slot   // 中央＝第 10 張
    let count = 40

    private func centroid(_ quad: [CGPoint]) -> CGPoint {
        CGPoint(x: quad.map(\.x).reduce(0, +) / 4, y: quad.map(\.y).reduce(0, +) / 4)
    }

    private func pose(_ index: Int) -> BoxPose {
        SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: offset, metrics: m), metrics: m)
    }

    @Test func centerSpineHitsCenterAlbum() {
        let quad = BoxProjection(metrics: m).quad(.spine, pose: pose(10))
        #expect(CarouselHitTest.index(at: centroid(quad), offset: offset, count: count, metrics: m) == 10)
    }

    @Test func sideCoverHitsThatAlbum() {
        let projection = BoxProjection(metrics: m)
        for index in [7, 13] {
            // 正面上靠外側（書脊那邊）的一點：不會被更靠中央的盒子蓋住
            let local = CGPoint(x: index < 10 ? m.cover * 0.1 : m.cover * 0.9, y: m.cover / 2)
            let point = projection.project(local, face: .front, pose: pose(index))
            #expect(CarouselHitTest.index(at: point, offset: offset, count: count, metrics: m) == index)
        }
    }

    /// 兩張盒子都蓋到的點取較靠中央（z 序在前）的那張
    @Test func overlapPicksFrontMost() {
        let projection = BoxProjection(metrics: m)
        let inner = projection.quad(.front, pose: pose(11))
        let outer = projection.quad(.front, pose: pose(12))
        var candidates: [CGPoint] = []
        for fx in 0...20 {
            for fy in 2...8 {
                let local = CGPoint(x: m.cover * CGFloat(fx) / 20, y: m.cover * CGFloat(fy) / 10)
                candidates.append(projection.project(local, face: .front, pose: pose(12)))
            }
        }
        let shared = candidates.first { CarouselHitTest.contains(inner, $0) && CarouselHitTest.contains(outer, $0) }
        #expect(shared != nil, "測試前提：第 11、12 張要有重疊")
        if let shared {
            #expect(CarouselHitTest.index(at: shared, offset: offset, count: count, metrics: m) == 11)
        }
    }

    @Test func blankAreaHitsNothing() {
        #expect(CarouselHitTest.index(at: CGPoint(x: m.center.x, y: 5), offset: offset, count: count, metrics: m) == nil)
        #expect(CarouselHitTest.index(at: m.center, offset: offset, count: 0, metrics: m) == nil)
    }

    @Test func pointOnEdgeCounts() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        #expect(CarouselHitTest.contains(square, CGPoint(x: 10, y: 5)))
        #expect(CarouselHitTest.contains(square, CGPoint(x: 0, y: 0)))
        #expect(CarouselHitTest.contains(square, CGPoint(x: 5, y: 5)))
        #expect(!CarouselHitTest.contains(square, CGPoint(x: 10.5, y: 5)))
        // 逆時針排列也一樣
        #expect(CarouselHitTest.contains(square.reversed(), CGPoint(x: 5, y: 5)))
    }
}
