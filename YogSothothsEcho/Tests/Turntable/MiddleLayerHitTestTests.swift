import CoreGraphics
import Testing

@testable import YogSothothsEcho

// CR-034 增補 B T5（yse-1.0.1-skin-technics.md §4.5）：唱片上被中層（刻度環）蓋住的地方點下去＝切換浮層、不切播放；
// 順序照畫面由上而下：全封面封套 → 唱臂 → 中層 → 唱片 → 封套 → 空白。點位取自 Technics 真素材的遮罩

struct MiddleLayerHitTestTests {
    private let container = CGRect(x: 0, y: 0, width: 1376, height: 1032)

    private func layout(_ definition: SpriteSkinDefinition = .technicsSL1200G, fullCover: Bool = false) throws -> TurntableLayout {
        TurntableLayout(container: container, fullCover: fullCover, skin: try SpriteSkinFixture.bundled(definition))
    }

    /// 中層素材像素的中心 → 畫面座標
    private func screenPoint(_ x: Int, _ y: Int, in layout: TurntableLayout) throws -> CGPoint {
        let rect = try #require(layout.armBaseMiddle)
        let unit = CGFloat(try #require(layout.skin.spec.middleHitMask).rows.count) / rect.height
        return CGPoint(x: rect.minX + (CGFloat(x) + 0.5) / unit, y: rect.minY + (CGFloat(y) + 0.5) / unit)
    }

    private func onVisibleRecord(_ point: CGPoint, _ layout: TurntableLayout) -> Bool {
        hypot(point.x - layout.record.midX, point.y - layout.record.midY) < layout.record.width / 2 * layout.recordVisibleScale - 1
    }

    /// 遮罩內／外、在可見唱片上、不碰唱臂（停臂 0°）的像素，各取一個
    private func samples(_ layout: TurntableLayout) throws -> (covered: CGPoint, uncovered: CGPoint) {
        let mask = try #require(layout.skin.spec.middleHitMask)
        let width = (mask.rows.flatMap { $0 }.map(\.upperBound).max() ?? 0) + 1
        var covered: CGPoint?, uncovered: CGPoint?
        for y in stride(from: 0, to: mask.rows.count, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let point = try screenPoint(x, y, in: layout)
                guard onVisibleRecord(point, layout), !TurntableHitTest.hitsArm(point, layout: layout, angle: 0) else { continue }
                if mask.contains(x: x, y: y) { covered = covered ?? point } else { uncovered = uncovered ?? point }
            }
        }
        return (try #require(covered, "刻度環要蓋到唱片"), try #require(uncovered, "唱片上要有中層透明處"))
    }

    @Test func ringOverTheRecordTogglesTheOverlay() throws {
        let technics = try layout()
        let point = try samples(technics).covered
        #expect(TurntableHitTest.hitsMiddle(point, layout: technics))
        #expect(TurntableHitTest.classify(point, layout: technics, sleeve: CoverSleeveState(), armAngle: 0) == .overlayToggle)
        // 同一點換成沒有中層的 classic（唱片位置相同）＝唱片（Rega r6 起也有中層，改用 classic 對照）
        let classic = TurntableLayout(container: container, fullCover: false, skin: .classic)
        #expect(!TurntableHitTest.hitsMiddle(point, layout: classic))
        #expect(TurntableHitTest.classify(point, layout: classic, sleeve: CoverSleeveState(), armAngle: 0) == .record)
    }

    /// 中層畫框內、但遮罩外（透明或 alpha < 128 的淡影）＝唱片
    @Test func transparentPartOfTheMiddleFrameStillHitsTheRecord() throws {
        let technics = try layout()
        let point = try samples(technics).uncovered
        #expect(try #require(technics.armBaseMiddle).contains(point))
        #expect(!TurntableHitTest.hitsMiddle(point, layout: technics))
        #expect(TurntableHitTest.classify(point, layout: technics, sleeve: CoverSleeveState(), armAngle: 0) == .record)
    }

    /// 唱臂蓋在中層上：兩者都命中，唱臂先判（畫面上唱臂在中層之上）
    @Test func armAboveTheMiddleIsCheckedFirst() throws {
        let technics = try layout()
        let mask = try #require(technics.skin.spec.middleHitMask)
        var found: CGPoint?
        for (y, row) in mask.rows.enumerated() where found == nil {
            for run in row where found == nil {
                for x in stride(from: run.lowerBound, to: run.upperBound, by: 2) {
                    let point = try screenPoint(x, y, in: technics)
                    if TurntableHitTest.hitsArm(point, layout: technics, angle: 0) { found = point; break }
                }
            }
        }
        let point = try #require(found, "停臂時唱臂應壓在中層上")
        #expect(TurntableHitTest.hitsMiddle(point, layout: technics) && TurntableHitTest.hitsArm(point, layout: technics, angle: 0))
        #expect(TurntableHitTest.classify(point, layout: technics, sleeve: CoverSleeveState(), armAngle: 0) == .overlayToggle)
    }

    /// 全封面封套蓋過一切；它的右緣＝唱片圓心，碰不到中層——兩者不重疊就沒有可測的點，改為斷言不重疊
    @Test func fullCoverSleeveNeverReachesTheMiddle() throws {
        let technics = try layout(fullCover: true)
        let middle = try #require(technics.armBaseMiddle)
        #expect(!middle.intersects(technics.coverBoundingBox))
    }
}
