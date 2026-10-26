import CoreGraphics
import Testing

@testable import YogSothothsEcho

// S5 T1（sprint-5-detail.md §4.2b v1.6／v1.8；A1-XL4 為底＋#5-1 第 2 項使用者在 Pencil 擺定＋Codex 審美評審）：以唱片直徑 R 與
// 唱片圓心為錨；可見唱片 0.96R、封套＝1.0475 × 可見唱片、斜 −7.88°，只許往左出框；全封面＝唱片不動、封套擺正移過去蓋住唱片一半；
// 唱片、唱臂（全角度）、底座任何 iPad 橫屏都完整在畫面內

private let landscapeSizes: [CGSize] = [
    CGSize(width: 1024, height: 768), CGSize(width: 1080, height: 810), CGSize(width: 1180, height: 820),
    CGSize(width: 1194, height: 834), CGSize(width: 1210, height: 834), CGSize(width: 1366, height: 1024),
    CGSize(width: 1376, height: 1032),
]

/// 典型 safe area：上 24、下 20（橫屏無瀏海、底部有 home indicator）
private func safeRect(_ size: CGSize) -> CGRect {
    CGRect(x: 0, y: 24, width: size.width, height: size.height - 44)
}

struct TurntableLayoutTests {
    @Test(arguments: landscapeSizes, [false, true])
    func recordArmAndBaseStayInside(size: CGSize, fullCover: Bool) {
        let container = safeRect(size)
        let layout = TurntableLayout(container: container, fullCover: fullCover, skin: .classic)
        let slack = container.insetBy(dx: -0.5, dy: -0.5)
        #expect(slack.contains(layout.record) && slack.contains(layout.armBase))
        for angle in stride(from: 0.0, through: ResolvedTurntableSkin.classic.endDegrees, by: 0.5) {
            #expect(slack.contains(layout.armBoundingBox(angle: angle)), "angle \(angle)")
        }
        // 封套只許往左出框；上下右都在畫面內
        let box = layout.coverBoundingBox
        #expect(box.maxX <= container.maxX && box.minY >= container.minY && box.maxY <= container.maxY)
    }

    /// 13 吋畫布 1376×1032：R＝800、唱片圓心 (888, 526)、封套 804.5 見方（縮小封套）、斜 −7.88°、中心 (323.3, 516.5)
    /// （使用者在 Pencil 擺的角度與高度；水平依 Codex「左下角明確出框 20」——封套縮小後重新對齊這個角）
    @Test func matchesThePencilPlacement() {
        let layout = TurntableLayout(container: CGRect(x: 0, y: 0, width: 1376, height: 1032), fullCover: false, skin: .classic)
        let r = layout.record.width
        #expect(abs(r - 800) < 1)
        #expect(abs(layout.record.midX - 888) < 1.5 && abs(layout.record.midY - 526) < 1.5)
        #expect(abs(layout.cover.width - 1.0475 * 0.96 * r) < 1e-6 && layout.cover.width == layout.cover.height)
        #expect(abs(layout.cover.midX - 323.3) < 0.5 && abs(layout.cover.midY - 516.5) < 0.5)
        #expect(TurntableMetrics.coverTiltDegrees == -7.88)
        #expect(abs(layout.scale - r / TurntableMetrics.recordSize) < 1e-9)
        // 斜放封套四角：左下角明確出框約 20、上下留白約 63／62
        let center = CGPoint(x: layout.cover.midX, y: layout.cover.midY)
        func corner(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            TonearmGeometry.rotate(CGPoint(x: x, y: y), about: center, degrees: TurntableMetrics.coverTiltDegrees)
        }
        let bottomLeft = corner(layout.cover.minX, layout.cover.maxY)
        let topRight = corner(layout.cover.maxX, layout.cover.minY)
        #expect(abs(bottomLeft.x - (-20)) < 1)
        #expect(abs(topRight.y - 63) < 1 && abs(1032 - bottomLeft.y - 62) < 1)
    }

    /// 較寬的 iPad 由高度決定（R＝0.775H），唱片圓心距右緣 0.61R
    @Test func widerScreensAreLimitedByHeight() {
        let container = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let layout = TurntableLayout(container: container, fullCover: false, skin: .classic)
        #expect(abs(layout.record.width - 0.775 * 820) < 1e-6)
        #expect(abs(container.maxX - layout.record.midX - 0.61 * layout.record.width) < 1e-6)
    }

    /// 全封面（點封套；#5-1 第 2 項使用者回饋）：唱片原地不動（照轉、唱頭不離開唱片），封套擺正、與唱片同高、
    /// 右緣對齊唱片圓心＝唱片一半裝進封套；唱臂與底座不動；封套完整在畫面內
    @Test(arguments: landscapeSizes)
    func fullCoverSleeveCoversHalfTheRecordInPlace(size: CGSize) {
        let container = safeRect(size)
        let normal = TurntableLayout(container: container, fullCover: false, skin: .classic)
        let full = TurntableLayout(container: container, fullCover: true, skin: .classic)
        #expect(full.record == normal.record && full.arm == normal.arm && full.armBase == normal.armBase)
        #expect(full.cover.size == normal.cover.size)
        #expect(abs(full.cover.maxX - full.record.midX) < 1e-6 && abs(full.cover.midY - full.record.midY) < 1e-6)
        let box = full.coverBoundingBox
        #expect([box.minX - full.cover.minX, box.minY - full.cover.minY, box.maxX - full.cover.maxX, box.maxY - full.cover.maxY]
            .allSatisfy { abs($0) < 1e-9 })
        #expect(container.insetBy(dx: -0.5, dy: -0.5).contains(full.cover))
    }

    /// 唱臂相對唱片的幾何與原版相同：支點到唱片圓心約 269s（spec「起止角」自洽校驗）
    @Test func armKeepsItsRelationToTheRecord() {
        let layout = TurntableLayout(container: CGRect(x: 0, y: 0, width: 1376, height: 1032), fullCover: false, skin: .classic)
        let s = layout.scale
        let center = CGPoint(x: layout.record.midX, y: layout.record.midY)
        #expect(abs(hypot(layout.armPivot.x - center.x, layout.armPivot.y - center.y) / s - 269.3) < 0.5)
        #expect(abs(layout.armBase.minY - layout.record.minY - 11 * s) < 1e-6)
    }

    /// G7 唱片位置（v2.1 T6）：唱盤＝現位置；封套內＝唱片圓心對齊「讓開後」的封套中心
    @Test(arguments: landscapeSizes, [false, true])
    func recordSlots(size: CGSize, fullCover: Bool) {
        let layout = TurntableLayout(container: safeRect(size), fullCover: fullCover, skin: .classic)
        #expect(layout.recordOrigin(.platter) == layout.record.origin)
        let sleeve = center(layout.recordOrigin(.sleeve), layout)
        #expect(abs(sleeve.x - (layout.cover.midX + layout.sleeveAsideOffset.dx)) < 1e-6)
        #expect(abs(sleeve.y - (layout.cover.midY + layout.sleeveAsideOffset.dy)) < 1e-6)
    }

    /// 封套沿自身斜軸讓開（Codex R4：不做法線校正）；唱片對軸點 A 在封套斜軸上；A→封套內的位移平行斜軸（唱片沿斜角進出）
    @Test(arguments: landscapeSizes, [false, true])
    func recordTravelsAlongTheSleeveAxis(size: CGSize, fullCover: Bool) {
        let layout = TurntableLayout(container: safeRect(size), fullCover: fullCover, skin: .classic)
        let u = layout.coverAxis
        #expect(abs(cross(layout.sleeveAsideOffset, u)) < 1e-6)
        #expect(layout.sleeveAsideOffset.dx * u.dx + layout.sleeveAsideOffset.dy * u.dy < 0)
        let a = center(layout.recordOrigin(.aligned), layout)
        let coverCenter = CGPoint(x: layout.cover.midX, y: layout.cover.midY)
        #expect(abs(cross(CGVector(dx: a.x - coverCenter.x, dy: a.y - coverCenter.y), u)) < 0.5)
        let inside = center(layout.recordOrigin(.sleeve), layout)
        #expect(abs(cross(CGVector(dx: inside.x - a.x, dy: inside.y - a.y), u)) < 1e-6)
    }

    /// 全封面（封套擺正、與唱片同高）：斜軸水平、唱片本來就在軸上——對軸位移退化為 0
    @Test(arguments: landscapeSizes)
    func fullCoverNeedsNoAlignment(size: CGSize) {
        let layout = TurntableLayout(container: safeRect(size), fullCover: true, skin: .classic)
        let a = layout.recordOrigin(.aligned), platter = layout.recordOrigin(.platter)
        #expect(abs(a.x - platter.x) < 1e-6 && abs(a.y - platter.y) < 1e-6)
        #expect(abs(layout.coverAxis.dy) < 1e-12)
    }

    /// 換層的兩個瞬間（clearing→sheathing、drawing→placing）：唱片在 A、封套讓開——可見圓與旋轉後封套方形相距 ≥ 3 pt（−0.5 容差）
    @Test(arguments: landscapeSizes, [false, true])
    func layerSwapMomentsDoNotOverlap(size: CGSize, fullCover: Bool) {
        let layout = TurntableLayout(container: safeRect(size), fullCover: fullCover, skin: .classic)
        let a = center(layout.recordOrigin(.aligned), layout)
        let gap = distanceFromSquare(a, layout, asideOffset: layout.sleeveAsideOffset) - visibleRadius(layout)
        #expect(gap >= TurntableLayout.sleeveAsideMargin - 0.5, "\(gap)")
    }

    /// 收進封套時唱片整張藏在讓開後的封套裡（可見圓在旋轉後方形內）
    @Test(arguments: landscapeSizes, [false, true])
    func recordHidesCompletelyInsideTheSleeve(size: CGSize, fullCover: Bool) {
        let layout = TurntableLayout(container: safeRect(size), fullCover: fullCover, skin: .classic)
        let inside = center(layout.recordOrigin(.sleeve), layout)
        let local = toCoverLocal(inside, layout, asideOffset: layout.sleeveAsideOffset)
        let half = layout.cover.width / 2
        #expect(abs(local.x) + visibleRadius(layout) <= half + 1e-6 && abs(local.y) + visibleRadius(layout) <= half + 1e-6)
    }

    /// 對軸點 A：可見唱片完整在容器內；讓開後的封套只從左側出框
    @Test(arguments: landscapeSizes, [false, true])
    func alignedRecordAndAsideSleeveStayInFrame(size: CGSize, fullCover: Bool) {
        let container = safeRect(size)
        let layout = TurntableLayout(container: container, fullCover: fullCover, skin: .classic)
        let a = center(layout.recordOrigin(.aligned), layout), r = visibleRadius(layout)
        #expect(a.y - r >= container.minY - 0.5 && a.y + r <= container.maxY + 0.5 && a.x + r <= container.maxX + 0.5)
        let box = layout.coverBoundingBox.offsetBy(dx: layout.sleeveAsideOffset.dx, dy: layout.sleeveAsideOffset.dy)
        #expect(box.maxX <= container.maxX && box.minY >= container.minY - 0.5 && box.maxY <= container.maxY + 0.5)
    }

    /// 唱片與封套的真實比例（#5-1 第 2 項，使用者實機比較後選「縮小封套」）：唱片畫 0.96R，封套＝1.0475×可見唱片
    @Test(arguments: landscapeSizes)
    func sleeveKeepsTheRealRatioToTheVisibleRecord(size: CGSize) {
        let layout = TurntableLayout(container: safeRect(size), fullCover: false, skin: .classic)
        #expect(layout.recordVisibleScale == 0.96)
        #expect(abs(layout.cover.width / (layout.record.width * layout.recordVisibleScale) - 1.0475) < 1e-9)
    }
}

// MARK: G7 幾何輔助（v2.1 T6）

private func center(_ origin: CGPoint, _ layout: TurntableLayout) -> CGPoint {
    CGPoint(x: origin.x + layout.record.width / 2, y: origin.y + layout.record.height / 2)
}

private func visibleRadius(_ layout: TurntableLayout) -> CGFloat { layout.record.width * layout.recordVisibleScale / 2 }

private func cross(_ a: CGVector, _ b: CGVector) -> CGFloat { a.dx * b.dy - a.dy * b.dx }

/// 點換到封套（讓開後、含傾角）的局部座標：原點＝封套中心、x 軸＝封套斜軸
private func toCoverLocal(_ point: CGPoint, _ layout: TurntableLayout, asideOffset: CGVector) -> CGPoint {
    let u = layout.coverAxis
    let dx = point.x - (layout.cover.midX + asideOffset.dx), dy = point.y - (layout.cover.midY + asideOffset.dy)
    return CGPoint(x: dx * u.dx + dy * u.dy, y: -dx * u.dy + dy * u.dx)
}

/// 點到封套方形（讓開後、含傾角）的最短距離；在方形內＝0
private func distanceFromSquare(_ point: CGPoint, _ layout: TurntableLayout, asideOffset: CGVector) -> CGFloat {
    let local = toCoverLocal(point, layout, asideOffset: asideOffset), half = layout.cover.width / 2
    let ex = max(abs(local.x) - half, 0), ey = max(abs(local.y) - half, 0)
    return (ex * ex + ey * ey).squareRoot()
}
