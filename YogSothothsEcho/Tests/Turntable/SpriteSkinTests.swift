import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-034 T2（yse-1.0.1-skins.md §4.1）：皮膚加唱片位置、投影層、上層底座、序列圖繪製、逐列點擊外形；
// skin.json（import_tonearm_skin.py 產生）→ TurntableSkin。classic 的既有數值一律不變（golden 另守）

/// 與 import_tonearm_skin.py 輸出同形的最小 skin.json（數值取自真素材的裁切結果）
private let sampleManifestJSON = """
{
 "schema": 1, "skin_id": "s-arm-1200", "px_per_unit": 4, "frame_count": 35,
 "layers": {
  "arm": {"size_px": [382, 1938], "pivot_px": [146, 447], "file_pattern": "arm_%03d.png",
          "outline_u": [[12.75, 30.25], null, [90, 95.5]]},
  "arm_shadow": {"size_px": [413, 1993], "pivot_px": [129, 451], "file_pattern": "arm_shadow_%03d.png",
                 "outline_u": [[20, 40], [52, 62.25]]},
  "base": {"size_px": [624, 701], "pivot_px": [305, 305], "file": "base_underlay.png"},
  "base_overlay": {"size_px": [313, 152], "pivot_px": [181, 86], "file": "base_overlay.png"}
 },
 "kinematics": {"stylus_at_rest_u": [6.0, 365.0], "rest_degrees": 0},
 "outline_band_u": 4, "hit_margin_u": 4
}
"""

private func sampleManifest() throws -> SpriteSkinManifest {
    try SpriteSkinManifest.decode(Data(sampleManifestJSON.utf8))
}

struct SpriteSkinTests {
    @Test func classicKeepsTheOriginalPlacementAndHasNoExtraLayers() {
        let classic = TurntableSkin.classic
        #expect(classic.placement == RecordPlacement(rightInset: 0.61, drop: 0.0125))
        #expect(classic.armShadow == nil && classic.baseOverlay == nil)
    }

    @Test func manifestDecodesTheImporterOutput() throws {
        let m = try sampleManifest()
        #expect(m.skinId == "s-arm-1200" && m.frameCount == 35 && m.pxPerUnit == 4)
        #expect(m.layers.arm.sizePx == [382, 1938] && m.layers.armShadow.pivotPx == [129, 451])
        #expect(m.layers.base.file == "base_underlay.png" && m.layers.baseOverlay.file == "base_overlay.png")
        #expect(m.layers.arm.outlineU.count == 3 && m.layers.arm.outlineU[1] == nil && m.outlineBandU == 4 && m.hitMarginU == 4)
    }

    @Test func manifestWithAnotherSchemaIsRejected() {
        let json = sampleManifestJSON.replacingOccurrences(of: "\"schema\": 1", with: "\"schema\": 2")
        #expect(throws: SkinError.invalidManifest) { try SpriteSkinManifest.decode(Data(json.utf8)) }
        #expect(throws: SkinError.invalidManifest) { try SpriteSkinManifest.decode(Data("{".utf8)) }
    }

    /// 畫框以 u 表示：px ÷ px_per_unit；序列圖的資料夾與每 u 像素數進 `.spriteSequence`（檔名由程式常數產生）
    @Test func spriteSkinTakesItsFramesFromTheManifest() throws {
        let skin = try TurntableSkin.sprite(.sArm1200, manifest: sampleManifest())
        #expect(skin.id == "s-arm-1200")
        #expect(skin.arm == ArtworkFrame(size: CGSize(width: 95.5, height: 484.5), localPivot: CGPoint(x: 36.5, y: 111.75)))
        #expect(skin.armShadow == ArtworkFrame(size: CGSize(width: 103.25, height: 498.25), localPivot: CGPoint(x: 32.25, y: 112.75)))
        #expect(skin.base == ArtworkFrame(size: CGSize(width: 156, height: 175.25), localPivot: CGPoint(x: 76.25, y: 76.25)))
        #expect(skin.baseOverlay == ArtworkFrame(size: CGSize(width: 78.25, height: 38), localPivot: CGPoint(x: 45.25, y: 21.5)))
        #expect(skin.rendering == .spriteSequence(SpriteSkinAssets(folder: "Skins/s-arm-1200", pixelsPerUnit: 4)))
        #expect(skin.spriteLayers != nil)
        #expect(SpriteSkinAssets.armFile(7) == "arm_007.png" && SpriteSkinAssets.shadowFile(34) == "arm_shadow_034.png")
        #expect(skin.armOutline == RowOutline(bandHeight: 4, spans: [12.75...30.25, nil, 90...95.5]))
        #expect(skin.shadowOutline == RowOutline(bandHeight: 4, spans: [20...40, 52...62.25]))
        // 點擊外形＝唱臂輪廓左右各外擴 4 u（判定時夾在臂框內）
        #expect(skin.hitShape == .rowSpans(margin: 4))
        #expect(skin.kinematics.stylusAtRest == CGVector(dx: 6, dy: 365) && skin.kinematics.restDegrees == 0)
        #expect(skin.kinematics.declaredTravel == nil)
    }

    /// 方案 3（使用者 2026-10-26 選）：唱片圓心距右緣 0.636034R、下移 0.0352R；支點的螢幕位置與 classic 相同（由構造保證）
    @Test func sArm1200UsesPlanThreeAndKeepsThePivotOnScreen() throws {
        let skin = try TurntableSkin.sprite(.sArm1200, manifest: sampleManifest())
        #expect(skin.placement == RecordPlacement(rightInset: 0.636034, drop: 0.0352))
        #expect(abs(skin.kinematics.pivot.x - 452.34) < 0.01 && abs(skin.kinematics.pivot.y - 49.24) < 0.01)
        let resolved = try TurntableSkinResolver.resolve(skin).get()
        #expect(abs(resolved.startDegrees - 13.813) < 0.01 && abs(resolved.endDegrees - 31.237) < 0.01)
        #expect(resolved.endDegrees < 34, "35 幀（0…34°）要涵蓋整段行程")
    }

    @Test func invalidPlacementIsRejected() {
        for placement in [RecordPlacement(rightInset: .nan, drop: 0), RecordPlacement(rightInset: 0, drop: 0),
                          RecordPlacement(rightInset: 1, drop: 0), RecordPlacement(rightInset: 0.6, drop: .infinity)] {
            #expect(TurntableSkinResolver.resolve(TurntableSkin.classic.replacing(placement: placement)) == .failure(.invalidPlacement),
                    "\(placement)")
        }
    }

    @Test func extraLayersAreValidatedLikeTheOthers() {
        let flat = ArtworkFrame(size: CGSize(width: 10, height: 0), localPivot: .zero)
        let outside = ArtworkFrame(size: CGSize(width: 10, height: 10), localPivot: CGPoint(x: 11, y: 5))
        #expect(TurntableSkinResolver.resolve(.classic.replacing(armShadow: flat)) == .failure(.invalidFrame))
        #expect(TurntableSkinResolver.resolve(.classic.replacing(baseOverlay: outside)) == .failure(.pivotOutsideFrame))
    }

    /// skin.json 的 skin_id、幀數、檔名須與定義及契約常數一致：不拿資料當格式字串或組路徑（安全評審 M-1／M-2）
    @Test(arguments: [("\"skin_id\": \"s-arm-1200\"", "\"skin_id\": \"classic\""),
                      ("\"frame_count\": 35", "\"frame_count\": 36"),
                      ("\"arm_%03d.png\"", "\"arm_%s.png\""),
                      ("\"arm_shadow_%03d.png\"", "\"../arm_shadow_%03d.png\""),
                      ("\"base_underlay.png\"", "\"/etc/base.png\"")])
    func manifestThatDisagreesWithTheDefinitionIsRejected(original: String, tampered: String) throws {
        let json = sampleManifestJSON.replacingOccurrences(of: original, with: tampered)
        #expect(json != sampleManifestJSON)
        #expect(throws: SkinError.invalidManifest) { try TurntableSkin.sprite(.sArm1200, manifest: SpriteSkinManifest.decode(Data(json.utf8))) }
    }

    @Test func invalidRowSpansAreRejected() throws {
        let skin = try TurntableSkin.sprite(.sArm1200, manifest: sampleManifest())
        let width = skin.arm.size.width
        let bad = [
            RowOutline(bandHeight: 0, spans: [0...1]),
            RowOutline(bandHeight: .nan, spans: [0...1]),
            RowOutline(bandHeight: 4, spans: []),
            RowOutline(bandHeight: 4, spans: [nil, nil]),
            RowOutline(bandHeight: 4, spans: [-1...2]),
            RowOutline(bandHeight: 4, spans: [0...(width + 1)]),
            RowOutline(bandHeight: 4, spans: Array(repeating: 0...1, count: Int(skin.arm.size.height / 4) + 2)),
        ]
        for outline in bad {
            #expect(TurntableSkinResolver.resolve(skin.replacing(armOutline: outline)) == .failure(.invalidOutline), "\(outline)")
        }
        for margin in [CGFloat.nan, -1, .infinity] {
            #expect(TurntableSkinResolver.resolve(skin.replacing(hitShape: .rowSpans(margin: margin))) == .failure(.invalidHitShape))
        }
        // 逐列點擊需要唱臂輪廓（classic 沒有）
        #expect(TurntableSkinResolver.resolve(.classic.replacing(hitShape: .rowSpans(margin: 4))) == .failure(.invalidHitShape))
    }

    @Test func rowOutlineLooksUpRows() {
        let outline = RowOutline(bandHeight: 4, spans: [2...5, nil, 0...10])
        #expect(outline.span(atY: 3.9) == 2...5 && outline.span(atY: 4) == nil && outline.span(atY: 8) == 0...10)
        #expect(outline.span(atY: -0.1) == nil && outline.span(atY: 12) == nil)
        #expect(outline.corners.count == 8 && outline.corners.contains(CGPoint(x: 10, y: 12)))
    }

    /// 序列圖皮膚必備：每 u 像素數為正、投影、上層底座、兩份輪廓（`spriteLayers` 據此解包）
    @Test func spriteSkinMustCarryEveryLayer() throws {
        let skin = try TurntableSkin.sprite(.sArm1200, manifest: sampleManifest())
        #expect(skin.spriteLayers != nil)
        let broken = [skin.replacing(rendering: .spriteSequence(SpriteSkinAssets(folder: "x", pixelsPerUnit: 0))),
                      skin.replacing(armShadow: nil), skin.replacing(baseOverlay: nil), skin.replacing(armOutline: nil)]
        for candidate in broken {
            #expect(TurntableSkinResolver.resolve(candidate) == .failure(.invalidRendering))
        }
        #expect(TurntableSkin.classic.spriteLayers == nil)
    }
}
