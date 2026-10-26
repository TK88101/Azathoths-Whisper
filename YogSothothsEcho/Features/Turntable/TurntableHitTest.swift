import CoreGraphics

/// 唱機場景的點擊命中（sprint-5-detail.md §4.2b v1.4；取代 TurntableTapTarget）：依畫面上實際的上下關係判定。
/// 常態＝唱臂（切換浮層，CR-019 起沒有唱臂操作）→ 唱片 → 封套 → 空白；全封面＝封套蓋過一切。浮層按鈕自己吃點擊，不經這裡
enum TurntableHitTest {
    enum Target: Equatable { case record, cover, overlayToggle }

    static func classify(_ point: CGPoint, layout: TurntableLayout, sleeve: CoverSleeveState, armAngle: Double) -> Target {
        let onCover = hitsCover(point, layout: layout, sleeve: sleeve)
        if sleeve.isFullCover, onCover { return .cover }
        if hitsArm(point, layout: layout, angle: armAngle) { return .overlayToggle }
        if hitsRecord(point, layout: layout) { return .record }
        return onCover ? .cover : .overlayToggle
    }

    private static func hitsRecord(_ point: CGPoint, layout: TurntableLayout) -> Bool {
        hypot(point.x - layout.record.midX, point.y - layout.record.midY) <= layout.record.width / 2 * layout.recordVisibleScale
    }

    /// 逆旋轉回封套的正方形再比對（不用外接框：旋轉後四角是透明區）；抽出中的位移跟著封套走
    private static func hitsCover(_ point: CGPoint, layout: TurntableLayout, sleeve: CoverSleeveState) -> Bool {
        let center = CGPoint(x: layout.cover.midX + sleeve.offsetFraction * layout.cover.width, y: layout.cover.midY)
        let local = TonearmGeometry.rotate(point, about: center, degrees: -sleeve.rotationDegrees)
        return abs(local.x - center.x) <= layout.cover.width / 2 && abs(local.y - center.y) <= layout.cover.height / 2
    }

    /// 依皮膚的點擊外形；先繞支點轉回素材的 rest 姿態
    private static func hitsArm(_ point: CGPoint, layout: TurntableLayout, angle: Double) -> Bool {
        let s = layout.scale
        let local = TonearmGeometry.rotate(point, about: layout.armPivot, degrees: -layout.skin.armRotation(forAngle: angle))
        let y = local.y - layout.arm.minY
        switch layout.skin.spec.hitShape {
        case .tubeStrip(let halfWidth, let headTop, let headBottom):
            // 臂管（支點 x 為中線的細條）＋唱頭區（臂圖寬）
            guard local.x >= layout.arm.minX, local.x <= layout.arm.maxX, y >= 0, y <= headBottom * s else { return false }
            return y >= headTop * s || abs(local.x - layout.armPivot.x) <= halfWidth * s
        }
    }
}
