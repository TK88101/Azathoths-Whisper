import CoreGraphics
import Testing

@testable import YogSothothsEcho

// S6 T1（sprint-6-detail.md §4.2「投影」）：共用消失點的方盒投影
struct BoxProjectionTests {
    let m = SpineCarouselTests.pro13

    /// 正對（0°）的右側盒：正面左上角＝(x − A, −A/2, T)，透視比例 d/(d − T)
    @Test func frontFacingCornerMatchesHandCalculation() {
        let projection = BoxProjection(metrics: m)
        let pose = BoxPose(x: 100, rotationDegrees: 0, side: .right)
        let k = m.perspective / (m.perspective - m.spine)
        let expected = CGPoint(x: m.center.x + (100 - m.cover) * k, y: m.center.y - m.cover / 2 * k)
        let actual = projection.project(.zero, face: .front, pose: pose)
        #expect(abs(actual.x - expected.x) <= 0.5 && abs(actual.y - expected.y) <= 0.5)
    }

    /// 轉 90° 的左側盒：正面右緣 (A, 0) → 盒座標 (A, −A/2, T) → 轉後 (T, ·, −A)，透視比例 d/(d + A)
    @Test func rotatedCornerMatchesHandCalculation() {
        let projection = BoxProjection(metrics: m)
        let pose = BoxPose(x: -200, rotationDegrees: 90, side: .left)
        let k = m.perspective / (m.perspective + m.cover)
        let expected = CGPoint(x: m.center.x + (-200 + m.spine) * k, y: m.center.y - m.cover / 2 * k)
        let actual = projection.project(CGPoint(x: m.cover, y: 0), face: .front, pose: pose)
        #expect(abs(actual.x - expected.x) <= 0.5 && abs(actual.y - expected.y) <= 0.5)
    }

    /// project 與 transform 一致：以 CATransform3D 齊次座標算同一點
    @Test func transformAgreesWithProject() {
        let projection = BoxProjection(metrics: m)
        let pose = SpineCarousel.pose(u: -1.3, metrics: m)
        for face in BoxProjection.Face.allCases {
            let t = projection.transform(face, pose: pose)
            let size = projection.size(of: face)
            for local in [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)] {
                let w = local.x * t.m14 + local.y * t.m24 + t.m44
                let x = (local.x * t.m11 + local.y * t.m21 + t.m41) / w
                let y = (local.x * t.m12 + local.y * t.m22 + t.m42) / w
                let p = projection.project(local, face: face, pose: pose)
                #expect(abs(p.x - x) < 1e-6 && abs(p.y - y) < 1e-6)
            }
        }
    }

    /// 共用消失點：同角度、不同 x 的兩盒投影形狀不同（各自透視的話只會平移）
    @Test func sharedVanishingPointChangesShapeWithPosition() {
        let projection = BoxProjection(metrics: m)
        let nearPose = BoxPose(x: 50, rotationDegrees: -76, side: .right)
        let farPose = BoxPose(x: 450, rotationDegrees: -76, side: .right)
        #expect(abs(projection.bounds(.front, pose: nearPose).width - projection.bounds(.front, pose: farPose).width) > 5)
        // 四角相對第一角的位移不同＝不只是平移（同深度的垂直範圍相同，故只比水平）
        let near = projection.quad(.front, pose: nearPose), far = projection.quad(.front, pose: farPose)
        #expect(abs((near[1].x - near[0].x) - (far[1].x - far[0].x)) > 5)
    }

    @Test func quadIsTheFourProjectedCorners() {
        let projection = BoxProjection(metrics: m)
        let pose = SpineCarousel.pose(u: 1.2, metrics: m)
        let quad = projection.quad(.spine, pose: pose)
        #expect(quad.count == 4)
        let size = projection.size(of: .spine)
        #expect(quad[2] == projection.project(CGPoint(x: size.width, y: size.height), face: .spine, pose: pose))
        #expect(size == CGSize(width: m.spine, height: m.cover))
        #expect(projection.size(of: .front) == CGSize(width: m.cover, height: m.cover))
    }

    /// 背面不畫（CSS backface-visibility: hidden 的對應）：側盒兩面都朝向使用者；轉到背對時判為不可見
    @Test func backfacesAreDetected() {
        let projection = BoxProjection(metrics: m)
        let side = SpineCarousel.pose(u: 2, metrics: m)
        #expect(projection.isFacingViewer(.front, pose: side) && projection.isFacingViewer(.spine, pose: side))
        let turnedAway = BoxPose(x: 300, rotationDegrees: 150, side: .right)
        #expect(!projection.isFacingViewer(.front, pose: turnedAway))
    }
}
