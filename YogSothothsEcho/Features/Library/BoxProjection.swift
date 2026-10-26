import CoreGraphics
import QuartzCore

/// 方盒兩面的投影（sprint-6-detail.md §4.2「投影」、D5）：世界座標原點＝瀏覽區中心、x 右 y 下 z 朝使用者。
/// 每個面的 view 都擺在瀏覽區左上角，`transform` 把面的本地座標一路送到瀏覽區座標：
/// 面 → 盒（正面前移 T；書脊以原點那條邊為軸轉 ±90°）→ 整盒 R_y(θ) → T(x) → 透視 P(d)（共用消失點）→ T(瀏覽區中心)。
/// CATransform3D 是列向量慣例（p' = p·M），`CATransform3DConcat(a, b)`＝先 a 後 b
struct BoxProjection {
    enum Face: CaseIterable, Sendable { case front, spine }
    let metrics: SpineCarouselMetrics

    func size(of face: Face) -> CGSize {
        switch face {
        case .front: CGSize(width: metrics.cover, height: metrics.cover)
        case .spine: CGSize(width: metrics.spine, height: metrics.cover)
        }
    }

    /// 面 → 世界（未透視）
    func worldTransform(_ face: Face, pose: BoxPose) -> CATransform3D {
        let a = metrics.cover, t = metrics.spine
        let faceToBox: CATransform3D
        switch (face, pose.side) {
        case (.front, .left): faceToBox = CATransform3DMakeTranslation(0, -a / 2, t)
        case (.front, .right): faceToBox = CATransform3DMakeTranslation(-a, -a / 2, t)
        case (.spine, .left):
            faceToBox = CATransform3DConcat(Self.rotationY(-90), CATransform3DMakeTranslation(0, -a / 2, 0))
        case (.spine, .right):
            faceToBox = [CATransform3DMakeTranslation(-t, 0, 0), Self.rotationY(90), CATransform3DMakeTranslation(0, -a / 2, 0)]
                .reduce(CATransform3DIdentity, CATransform3DConcat)
        }
        return [faceToBox, CATransform3DMakeScale(pose.scale, pose.scale, pose.scale), Self.rotationY(pose.rotationDegrees),
                CATransform3DMakeTranslation(pose.x, pose.y, 0)]
            .reduce(CATransform3DIdentity, CATransform3DConcat)
    }

    /// 面 → 瀏覽區座標；交給 `projectionEffect(ProjectionTransform(_:))`（z＝0 的平面，丟掉 z 列不失真）
    func transform(_ face: Face, pose: BoxPose) -> CATransform3D {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / metrics.perspective
        let toScreen = CATransform3DMakeTranslation(metrics.center.x, metrics.center.y, 0)
        return [worldTransform(face, pose: pose), perspective, toScreen].reduce(CATransform3DIdentity, CATransform3DConcat)
    }

    func project(_ local: CGPoint, face: Face, pose: BoxPose) -> CGPoint {
        Self.screen(local, transform(face, pose: pose))
    }

    /// 四角（本地左上、右上、右下、左下）的投影；矩陣每面只建一次（捲動中每幀每盒都要算）
    func quad(_ face: Face, pose: BoxPose) -> [CGPoint] {
        let t = transform(face, pose: pose)
        return corners(of: face).map { Self.screen($0, t) }
    }

    func bounds(_ face: Face, pose: BoxPose) -> CGRect {
        let points = quad(face, pose: pose)
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// 面的外法向量（世界座標）：本地 x × 本地 y（x 右 y 下 z 朝使用者為右手系，未轉的面法向量＝+z）
    func normal(_ face: Face, pose: BoxPose) -> SIMD3<Double> {
        Self.normal(worldTransform(face, pose: pose))
    }

    /// 背面不畫：相機在 (0, 0, d)，面上一點指向相機的向量與法向量同向才看得到
    func isFacingViewer(_ face: Face, pose: BoxPose) -> Bool {
        let t = worldTransform(face, pose: pose)
        let point = Self.world(.zero, t)
        let toCamera = SIMD3(-point.x, -point.y, Double(metrics.perspective) - point.z)
        return (toCamera * Self.normal(t)).sum() > 1e-9
    }

    private static func normal(_ t: CATransform3D) -> SIMD3<Double> {
        let o = world(.zero, t)
        let ex = world(CGPoint(x: 1, y: 0), t) - o
        let ey = world(CGPoint(x: 0, y: 1), t) - o
        return SIMD3(ex.y * ey.z - ex.z * ey.y, ex.z * ey.x - ex.x * ey.z, ex.x * ey.y - ex.y * ey.x)
    }

    private static func world(_ p: CGPoint, _ t: CATransform3D) -> SIMD3<Double> {
        let h = apply(t, to: p)
        return SIMD3(h.x / h.w, h.y / h.w, h.z / h.w)
    }

    private static func screen(_ p: CGPoint, _ t: CATransform3D) -> CGPoint {
        let h = apply(t, to: p)
        return CGPoint(x: h.x / h.w, y: h.y / h.w)
    }

    private func corners(of face: Face) -> [CGPoint] {
        let s = size(of: face)
        return [.zero, CGPoint(x: s.width, y: 0), CGPoint(x: s.width, y: s.height), CGPoint(x: 0, y: s.height)]
    }

    /// 與 CSS rotateY 相同：x' = x·cos + z·sin，z' = −x·sin + z·cos
    static func rotationY(_ degrees: Double) -> CATransform3D {
        let r = degrees * .pi / 180
        var m = CATransform3DIdentity
        m.m11 = cos(r); m.m13 = -sin(r)
        m.m31 = sin(r); m.m33 = cos(r)
        return m
    }

    private static func apply(_ m: CATransform3D, to p: CGPoint) -> (x: Double, y: Double, z: Double, w: Double) {
        (p.x * m.m11 + p.y * m.m21 + m.m41, p.x * m.m12 + p.y * m.m22 + m.m42,
         p.x * m.m13 + p.y * m.m23 + m.m43, p.x * m.m14 + p.y * m.m24 + m.m44)
    }
}
