import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-034 增補 A T3（yse-1.0.1-skin-picker.md §4.5）：rega-rb330 採預設構圖（唱片位置＝classic），
// 版面、點擊、8 種橫屏不出框、封套投影、真素材記憶體閘門。素材取自 app bundle（Resources/Skins/rega-rb330）

private let landscapeSizes: [CGSize] = [
    CGSize(width: 1024, height: 768), CGSize(width: 1080, height: 810), CGSize(width: 1133, height: 744),
    CGSize(width: 1180, height: 820), CGSize(width: 1194, height: 834), CGSize(width: 1210, height: 834),
    CGSize(width: 1366, height: 1024), CGSize(width: 1376, height: 1032),
]

private func screen(_ size: CGSize) -> CGRect { CGRect(origin: .zero, size: size) }
private func safeArea(_ size: CGSize) -> CGRect { CGRect(x: 0, y: 24, width: size.width, height: size.height - 44) }

struct RegaSkinTests {
    private func rega() throws -> ResolvedTurntableSkin { try SpriteSkinFixture.bundled(.regaRB330) }

    /// 預設構圖：唱片圓心、支點螢幕位置都與 classic 相同；起止角與 classic 差 ≤ 0.05°（針尖與支點契約相同）
    @Test(arguments: landscapeSizes)
    func defaultCompositionMatchesClassic(size: CGSize) throws {
        let skin = try rega()
        let r = TurntableLayout(container: screen(size), fullCover: false, skin: skin)
        let c = TurntableLayout(container: screen(size), fullCover: false, skin: .classic)
        #expect(skin.spec.placement == .classic)
        #expect(abs(r.record.midX - c.record.midX) < 1e-6 && abs(r.record.midY - c.record.midY) < 1e-6)
        #expect(abs(r.armPivot.x - c.armPivot.x) < 1e-6 && abs(r.armPivot.y - c.armPivot.y) < 1e-6)
        #expect(abs(skin.startDegrees - ResolvedTurntableSkin.classic.startDegrees) <= 0.05)
        #expect(abs(skin.endDegrees - ResolvedTurntableSkin.classic.endDegrees) <= 0.05)
    }

    /// 35 幀：每一列輪廓中點都命中；外擴 margin 再外 1 u 不命中
    @Test func rowSpansHitTheArmAtEveryFrameAngle() throws {
        let skin = try rega()
        let layout = TurntableLayout(container: screen(CGSize(width: 1376, height: 1032)), fullCover: false, skin: skin)
        guard case .rowSpans(let margin) = skin.spec.hitShape, let outline = skin.spec.armOutline else { Issue.record("不是 rowSpans"); return }
        let s = layout.scale
        for angle in 0...34 {
            for (row, span) in outline.spans.enumerated() {
                guard let span else { continue }
                let y = layout.arm.minY + (CGFloat(row) + 0.5) * outline.bandHeight * s
                func screenPoint(_ xu: CGFloat) -> CGPoint {
                    TonearmGeometry.rotate(CGPoint(x: layout.arm.minX + xu * s, y: y), about: layout.armPivot,
                                           degrees: skin.armRotation(forAngle: Double(angle)))
                }
                #expect(TurntableHitTest.hitsArm(screenPoint((span.lowerBound + span.upperBound) / 2), layout: layout, angle: Double(angle)),
                        "\(angle)° 列 \(row)")
                if span.upperBound + margin + 1 < skin.spec.arm.size.width {
                    #expect(!TurntableHitTest.hitsArm(screenPoint(span.upperBound + margin + 1), layout: layout, angle: Double(angle)))
                }
            }
        }
    }

    @Test func theRecordCenterDoesNotHitTheArm() throws {
        let layout = TurntableLayout(container: screen(CGSize(width: 1376, height: 1032)), fullCover: false, skin: try rega())
        #expect(!TurntableHitTest.hitsArm(CGPoint(x: layout.record.midX, y: layout.record.midY), layout: layout, angle: 0))
    }

    @Test(arguments: landscapeSizes, [false, true])
    func everyLayerStaysInsideTheSafeArea(size: CGSize, fullCover: Bool) throws {
        let skin = try rega()
        let layout = TurntableLayout(container: screen(size), fullCover: fullCover, skin: skin)
        let safe = safeArea(size).insetBy(dx: -0.5, dy: -0.5)
        #expect(safe.contains(layout.record) && safe.contains(layout.armBase), "\(size)")
        if let overlay = layout.armBaseOverlay { #expect(safe.contains(overlay), "上層底座 \(size)") }
        if let middle = layout.armBaseMiddle { #expect(safe.contains(middle), "中層底座 \(size)") }
        for angle in stride(from: 0.0, through: skin.endDegrees, by: 0.5) {
            #expect(safe.contains(layout.armBoundingBox(angle: angle)), "唱臂 \(size) \(angle)°")
            if let shadow = layout.shadowBoundingBox(angle: angle) { #expect(safe.contains(shadow), "唱臂投影 \(size) \(angle)°") }
        }
    }

    /// 增補 B（r6 交件）：臂夾、夾爪、支柱與刻度板在中層；上層沒有零件（匯入成支點上 1×1 透明像素）
    @Test func r6MovesTheClipToTheMiddleLayer() throws {
        let spec = try rega().spec
        let middle = try #require(spec.baseMiddle)
        let mask = try #require(spec.middleHitMask)
        #expect(mask.rows.count == Int((middle.size.height * 4).rounded()) && mask.rows.contains { !$0.isEmpty })
        #expect(spec.baseOverlay == ArtworkFrame(size: CGSize(width: 0.25, height: 0.25), localPivot: .zero))
    }

    /// 臂夾壓在唱片邊緣（使用者 2026-10-28 核准的例外）：點在那裡＝切換浮層，不切播放
    @Test func clipOverTheRecordTogglesTheOverlay() throws {
        let layout = TurntableLayout(container: screen(CGSize(width: 1376, height: 1032)), fullCover: false, skin: try rega())
        let rect = try #require(layout.armBaseMiddle)
        let mask = try #require(layout.skin.spec.middleHitMask)
        let unit = CGFloat(mask.rows.count) / rect.height
        let radius = layout.record.width / 2 * layout.recordVisibleScale - 1
        var found: CGPoint?
        for (y, row) in mask.rows.enumerated() where found == nil {
            for run in row where found == nil {
                for x in run {
                    let point = CGPoint(x: rect.minX + (CGFloat(x) + 0.5) / unit, y: rect.minY + (CGFloat(y) + 0.5) / unit)
                    if hypot(point.x - layout.record.midX, point.y - layout.record.midY) < radius,
                       !TurntableHitTest.hitsArm(point, layout: layout, angle: 14) {
                        found = point
                        break
                    }
                }
            }
        }
        let point = try #require(found, "r6 的臂夾有一段壓在唱片上")
        #expect(TurntableHitTest.classify(point, layout: layout, sleeve: CoverSleeveState(), armAngle: 14) == .overlayToggle)
    }

    /// 封套位置與 classic 相同 → 投影（含 G7 讓開的已知超出）與 classic 一致
    @Test(arguments: landscapeSizes)
    func sleeveShadowMatchesClassic(size: CGSize) throws {
        let skin = try rega()
        for fullCover in [false, true] {
            let r = TurntableLayout(container: screen(size), fullCover: fullCover, skin: skin)
            let c = TurntableLayout(container: screen(size), fullCover: fullCover, skin: .classic)
            #expect(r.coverBoundingBox == c.coverBoundingBox && r.sleeveAsideOffset == c.sleeveAsideOffset, "\(size) \(fullCover)")
        }
    }

    /// 記憶體閘門（v0.3 §4.4，≤ 200 MiB）：真素材、真解碼器，13 吋與 mini
    @MainActor
    @Test(arguments: [800.0, 576.6])
    func realAssetsDecodeWithinTheMemoryBudget(recordDiameter: Double) async throws {
        let cache = TonearmSpriteCache(onFailure: { _, _ in Issue.record("解碼失敗") })
        cache.load(try rega(), pixelScale: recordDiameter / TurntableMetrics.recordSize * 2)
        // 以時間為上限（真素材解碼在背景執行緒，機器忙時讓出次數不夠等）
        let deadline = ContinuousClock.now + .seconds(60)
        while !cache.isComplete, ContinuousClock.now < deadline { await Task.yield() }
        #expect(cache.isComplete && cache.pairs.count == SpriteSkinAssets.frameCount)
        let mib = Double(cache.residentBytes) / 1_048_576
        #expect(mib <= 200, "常駐 \(mib) MiB")
        print("CR-034 rega memory: R=\(recordDiameter) → \(String(format: "%.1f", mib)) MiB")
    }
}
