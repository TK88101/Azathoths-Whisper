import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-034 T3／T4／T5（yse-1.0.1-skins.md §4.5、§6）：s-arm-1200 的方案 3 版面、逐列點擊外形、兩款皮膚在 8 種橫屏的不出框。
// 座標契約（r1-7）：版面以全螢幕當 container（與 TurntableView 的 ignoresSafeArea 相同），再檢查落在安全區（上 24、下 20）內。
// s-arm-1200 取自 app bundle 內真的 skin.json（Resources/Skins，import_tonearm_skin.py 產生）

private let landscapeSizes: [CGSize] = [
    CGSize(width: 1024, height: 768), CGSize(width: 1080, height: 810), CGSize(width: 1133, height: 744),
    CGSize(width: 1180, height: 820), CGSize(width: 1194, height: 834), CGSize(width: 1210, height: 834),
    CGSize(width: 1366, height: 1024), CGSize(width: 1376, height: 1032),
]

private func screen(_ size: CGSize) -> CGRect { CGRect(origin: .zero, size: size) }
private func safeArea(_ size: CGSize) -> CGRect { CGRect(x: 0, y: 24, width: size.width, height: size.height - 44) }

/// G7 讓開時封套投影超出**螢幕下緣**的已知上限（pt；投影 A 使用者 2026-10-26 選）。交接檔估 classic 7–10、s-arm-1200 19–27；
/// 本測試同公式實算 8 尺寸：classic 7.4–10.1、s-arm-1200 20.5–28.3（13 吋最大）→ 上限＝實測最大＋1
private let knownAsideShadowOverflow: [String: CGFloat] = ["classic": 10.1 + 1, "s-arm-1200": 28.3 + 1]

/// app bundle 內真的 skin.json → 已求解的序列圖皮膚（S-Arm 與 Rega 測試共用）
enum SpriteSkinFixture {
    static func bundled(_ definition: SpriteSkinDefinition = .sArm1200) throws -> ResolvedTurntableSkin {
        let url = try #require(Bundle.main.url(forResource: "skin", withExtension: "json", subdirectory: definition.folder))
        let skin = try TurntableSkin.sprite(definition, manifest: SpriteSkinManifest.decode(Data(contentsOf: url)))
        return try TurntableSkinResolver.resolve(skin).get()
    }
}

struct SpriteSkinLayoutTests {
    private func skins() throws -> [ResolvedTurntableSkin] { [.classic, try SpriteSkinFixture.bundled()] }

    // MARK: T3 版面

    /// 方案 3：唱片圓心照 placement；支點的螢幕位置與 classic 相同（每種尺寸）
    @Test(arguments: landscapeSizes)
    func planThreeMovesTheRecordButNotThePivot(size: CGSize) throws {
        let sArm = try SpriteSkinFixture.bundled()
        let a = TurntableLayout(container: screen(size), fullCover: false, skin: sArm)
        let c = TurntableLayout(container: screen(size), fullCover: false, skin: .classic)
        let r = a.record.width
        #expect(abs(size.width - a.record.midX - 0.636034 * r) < 1e-6 && abs(a.record.midY - (size.height / 2 + 0.0352 * r)) < 1e-6)
        #expect(abs(a.armPivot.x - c.armPivot.x) < 1e-6 && abs(a.armPivot.y - c.armPivot.y) < 1e-6)
        // 封套跟著唱片圓心走（相對位置不變）
        #expect(abs((a.cover.midX - a.record.midX) - (c.cover.midX - c.record.midX)) < 1e-6)
        #expect(abs((a.cover.midY - a.record.midY) - (c.cover.midY - c.record.midY)) < 1e-6)
    }

    /// 每一層各自的畫框：左上＝支點 − 框內支點；classic 沒有投影層與上層底座
    @Test func eachLayerHasItsOwnFrame() throws {
        let sArm = try SpriteSkinFixture.bundled()
        let layout = TurntableLayout(container: screen(CGSize(width: 1376, height: 1032)), fullCover: false, skin: sArm)
        let s = layout.scale
        let shadow = try #require(layout.armShadow), overlay = try #require(layout.armBaseOverlay)
        let spec = sArm.spec
        for (rect, frame) in [(layout.arm, spec.arm), (shadow, try #require(spec.armShadow)), (layout.armBase, spec.base),
                              (overlay, try #require(spec.baseOverlay))] {
            #expect(abs(rect.minX + frame.localPivot.x * s - layout.armPivot.x) < 1e-6)
            #expect(abs(rect.minY + frame.localPivot.y * s - layout.armPivot.y) < 1e-6)
            #expect(abs(rect.width - frame.size.width * s) < 1e-6 && abs(rect.height - frame.size.height * s) < 1e-6)
        }
        let classic = TurntableLayout(container: screen(CGSize(width: 1376, height: 1032)), fullCover: false, skin: .classic)
        #expect(classic.armShadow == nil && classic.armBaseOverlay == nil && classic.shadowBoundingBox(angle: 20) == nil)
    }

    // MARK: T4 點擊

    /// 35 幀（0…34°）：每一列輪廓的中點都命中唱臂；輪廓外擴 margin 再外 1 u 不命中
    @Test func rowSpansHitTheArmAtEveryFrameAngle() throws {
        let sArm = try SpriteSkinFixture.bundled()
        let layout = TurntableLayout(container: screen(CGSize(width: 1376, height: 1032)), fullCover: false, skin: sArm)
        guard case .rowSpans(let margin) = sArm.spec.hitShape, let outline = sArm.spec.armOutline else { Issue.record("不是 rowSpans"); return }
        let band = outline.bandHeight, spans = outline.spans
        let s = layout.scale
        for angle in 0...34 {
            for (row, span) in spans.enumerated() {
                guard let span else { continue }
                let y = layout.arm.minY + (CGFloat(row) + 0.5) * band * s
                func screenPoint(_ xu: CGFloat) -> CGPoint {
                    TonearmGeometry.rotate(CGPoint(x: layout.arm.minX + xu * s, y: y), about: layout.armPivot,
                                           degrees: sArm.armRotation(forAngle: Double(angle)))
                }
                let mid = (span.lowerBound + span.upperBound) / 2
                #expect(TurntableHitTest.hitsArm(screenPoint(mid), layout: layout, angle: Double(angle)), "\(angle)° 列 \(row)")
                if span.upperBound + margin + 1 < sArm.spec.arm.size.width {
                    #expect(!TurntableHitTest.hitsArm(screenPoint(span.upperBound + margin + 1), layout: layout, angle: Double(angle)))
                }
                // 取點離臂框邊 0.5 u：恰在框邊上會被旋轉往返的浮點誤差推出框外
                #expect(TurntableHitTest.hitsArm(screenPoint(min(span.upperBound + margin, sArm.spec.arm.size.width) - 0.5), layout: layout,
                                                 angle: Double(angle)), "外擴範圍內 \(angle)° 列 \(row)")
            }
        }
    }

    @Test func pointsOutsideTheArmFrameDoNotHitTheArm() throws {
        let sArm = try SpriteSkinFixture.bundled()
        let layout = TurntableLayout(container: screen(CGSize(width: 1376, height: 1032)), fullCover: false, skin: sArm)
        for point in [CGPoint(x: layout.arm.minX - 5, y: layout.arm.midY), CGPoint(x: layout.arm.midX, y: layout.arm.maxY + 5),
                      CGPoint(x: layout.record.midX, y: layout.record.midY)] {
            #expect(!TurntableHitTest.hitsArm(point, layout: layout, angle: 0), "\(point)")
        }
    }

    // MARK: T5 不出框

    @Test(arguments: landscapeSizes, [false, true])
    func everyLayerStaysInsideTheSafeArea(size: CGSize, fullCover: Bool) throws {
        for skin in try skins() {
            let layout = TurntableLayout(container: screen(size), fullCover: fullCover, skin: skin)
            let safe = safeArea(size).insetBy(dx: -0.5, dy: -0.5)
            let id = "\(skin.spec.id) \(size)"
            #expect(safe.contains(layout.record), "唱片 \(id)")
            #expect(safe.contains(layout.armBase), "底座 \(id)")
            if let overlay = layout.armBaseOverlay { #expect(safe.contains(overlay), "上層底座 \(id)") }
            for angle in stride(from: 0.0, through: skin.endDegrees, by: 0.5) {
                #expect(safe.contains(layout.armBoundingBox(angle: angle)), "唱臂 \(id) \(angle)°")
                if let shadow = layout.shadowBoundingBox(angle: angle) { #expect(safe.contains(shadow), "唱臂投影 \(id) \(angle)°") }
            }
            let box = layout.coverBoundingBox
            #expect(box.maxX <= size.width && box.minY >= safe.minY && box.maxY <= safe.maxY, "封套只許往左出框 \(id)")
        }
    }

    /// 封套投影：常態與全封面完整在畫面內（不被裁切）；G7 讓開時超出安全區下緣屬已知（投影 A），不超過已知上限
    @Test(arguments: landscapeSizes)
    func sleeveShadowStaysOnScreenExceptTheKnownAsideOverflow(size: CGSize) throws {
        for skin in try skins() {
            for fullCover in [false, true] {
                let layout = TurntableLayout(container: screen(size), fullCover: fullCover, skin: skin)
                let shadow = SleeveShadow.turntable(scale: layout.scale, containerWidth: size.width)
                let extent = shadow.extent(of: layout.coverBoundingBox)
                let id = "\(skin.spec.id) \(size) fullCover=\(fullCover)"
                #expect(extent.minY >= 0 && extent.maxY <= size.height && extent.maxX <= size.width, "常態投影 \(id) \(extent)")
                let aside = shadow.extent(of: layout.coverBoundingBox.offsetBy(dx: layout.sleeveAsideOffset.dx, dy: layout.sleeveAsideOffset.dy))
                let overflow = aside.maxY - size.height
                let limit = try #require(knownAsideShadowOverflow[skin.spec.id])
                #expect(overflow <= limit, "讓開投影超出 \(overflow) pt \(id)")
            }
        }
    }

    /// 全封面：封套擺正、右緣對齊唱片圓心（蓋住唱片一半），兩款皮膚都完整在安全區內
    @Test(arguments: landscapeSizes)
    func fullCoverStillCoversHalfTheRecord(size: CGSize) throws {
        for skin in try skins() {
            let full = TurntableLayout(container: screen(size), fullCover: true, skin: skin)
            #expect(abs(full.cover.maxX - full.record.midX) < 1e-6 && abs(full.cover.midY - full.record.midY) < 1e-6)
            #expect(safeArea(size).insetBy(dx: -0.5, dy: -0.5).contains(full.cover), "\(skin.spec.id) \(size)")
        }
    }
}
