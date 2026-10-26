import CoreGraphics
import Testing

@testable import YogSothothsEcho

// §4.2b v1.4：點擊依實際 z-order 判定——常態＝唱臂→唱片→封套→空白；全封面＝封套最先；封套用逆旋轉判定（不用外接框）

struct TurntableHitTestTests {
    let layout = TurntableLayout(container: CGRect(x: 0, y: 0, width: 1376, height: 1032), fullCover: false, skin: .classic)
    let resting = CoverSleeveState()

    private func hit(_ point: CGPoint, layout: TurntableLayout? = nil, sleeve: CoverSleeveState? = nil, arm: Double = 20)
        -> TurntableHitTest.Target {
        TurntableHitTest.classify(point, layout: layout ?? self.layout, sleeve: sleeve ?? resting, armAngle: arm)
    }

    @Test func recordCoverAndElsewhere() {
        #expect(hit(CGPoint(x: layout.record.midX, y: layout.record.midY + 100)) == .record)
        #expect(hit(CGPoint(x: layout.cover.midX - 200, y: layout.cover.midY)) == .cover)
        #expect(hit(CGPoint(x: 1370, y: 1020)) == .overlayToggle)
    }

    /// 常態：唱片蓋在封套上，重疊區＝唱片
    @Test func overlapBelongsToTheRecord() {
        let point = CGPoint(x: layout.record.minX + 40, y: layout.record.midY)
        #expect(hit(point) == .record)
    }

    /// 唱臂蓋在唱片上：點唱臂＝切換浮層（CR-019 起沒有唱臂操作）
    @Test func armOverRecordTogglesTheOverlay() {
        let head = TonearmGeometry.rotate(CGPoint(x: layout.arm.minX + 0.5 * layout.arm.width, y: layout.arm.minY + 372 * layout.scale),
                                          about: layout.armPivot, degrees: 20)
        #expect(layout.record.contains(head))
        #expect(hit(head, arm: 20) == .overlayToggle)
    }

    /// 封套旋轉後外接框的角落（透明區）不算封套
    @Test func coverCornersOutsideTheRotatedSquareAreNotCover() {
        let box = layout.coverBoundingBox
        let corner = CGPoint(x: box.minX + 3, y: box.maxY - 3)
        #expect(box.contains(corner))
        #expect(hit(corner) == .overlayToggle)
    }

    /// 全封面：封套蓋過唱片與唱臂
    @Test func fullCoverPutsTheSleeveOnTop() {
        let full = TurntableLayout(container: layout.container, fullCover: true, skin: .classic)
        var sleeve = CoverSleeveState()
        _ = sleeve.tap()
        sleeve.midwayFinished()
        let overlap = CGPoint(x: full.record.minX + 60, y: full.record.midY)
        #expect(full.cover.contains(overlap))
        #expect(hit(overlap, layout: full, sleeve: sleeve) == .cover)
    }

    /// 封套抽出中（M 階段向左位移半個寬度）：命中區跟著封套走
    @Test func midwaySlideMovesTheCoverHitArea() {
        var sleeve = CoverSleeveState()
        _ = sleeve.tap()
        let shiftedCenter = CGPoint(x: layout.cover.midX + layout.cover.width * sleeve.offsetFraction, y: layout.cover.midY)
        #expect(hit(shiftedCenter, sleeve: sleeve) == .cover)
        #expect(hit(CGPoint(x: layout.cover.maxX - 30, y: layout.cover.minY + 60), sleeve: sleeve) != .cover)
    }

    /// 唱片點擊半徑＝畫面上的唱片（0.96R）：框內但在可見唱片外的外圈不算唱片
    @Test func recordHitRadiusFollowsTheVisibleRecord() {
        let inside = CGPoint(x: layout.record.midX, y: layout.record.midY + layout.record.height / 2 * 0.95)
        let rim = CGPoint(x: layout.record.midX, y: layout.record.midY + layout.record.height / 2 * 0.98)
        #expect(hit(inside, arm: 0) == .record)
        #expect(hit(rim, arm: 0) != .record)
    }
}
