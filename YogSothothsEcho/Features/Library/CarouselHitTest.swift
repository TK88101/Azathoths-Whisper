import CoreGraphics

/// 側封點擊命中（sprint-6-detail.md D6）：以可見盒子的投影四邊形（正面、書脊；背面不算）判定，取 z 序最前者。
/// 隱形槽位等寬、盒子非線性外擴，側盒的畫面位置與槽位不重合，所以不交給槽位
enum CarouselHitTest {
    static func index(at point: CGPoint, offset: CGFloat, count: Int, metrics: SpineCarouselMetrics) -> Int? {
        let projection = BoxProjection(metrics: metrics)
        let hits = SpineCarousel.visibleRange(offset: offset, count: count, metrics: metrics).filter { index in
            let pose = SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: offset, metrics: metrics), metrics: metrics)
            return BoxProjection.Face.allCases.contains { face in
                projection.isFacingViewer(face, pose: pose) && contains(projection.quad(face, pose: pose), point)
            }
        }
        return hits.max { a, b in
            SpineCarousel.zIndex(u: SpineCarousel.u(index: a, offset: offset, metrics: metrics))
                < SpineCarousel.zIndex(u: SpineCarousel.u(index: b, offset: offset, metrics: metrics))
        }
    }

    /// 點在凸四邊形內（含邊）：各邊外積同號或為 0；順、逆時針皆可
    static func contains(_ quad: [CGPoint], _ point: CGPoint) -> Bool {
        guard quad.count >= 3 else { return false }
        var sign: CGFloat = 0
        for i in quad.indices {
            let a = quad[i], b = quad[(i + 1) % quad.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if abs(cross) < 1e-9 { continue }
            if sign == 0 { sign = cross } else if (sign > 0) != (cross > 0) { return false }
        }
        return true
    }
}
