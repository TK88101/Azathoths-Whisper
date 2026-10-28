import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-034 增補 B T2（yse-1.0.1-skin-technics.md §4.1）：可選的第三層底座 base_middle（唱片之上、唱臂之下）。
// 沒有中層的 skin.json（Pioneer、Rega）必須照舊解得開、結果逐值不變

/// 與 import_tonearm_skin.py 輸出同形的三層 skin.json（數值為最小示意）
private let threeLayerJSON = """
{
 "schema": 1, "skin_id": "technics-sl1200g", "px_per_unit": 4, "frame_count": 35,
 "layers": {
  "arm": {"size_px": [418, 1836], "pivot_px": [163, 370], "file_pattern": "arm_%03d.png", "outline_u": [[10, 30]]},
  "arm_shadow": {"size_px": [439, 1882], "pivot_px": [134, 375], "file_pattern": "arm_shadow_%03d.png", "outline_u": [[10, 30]]},
  "base": {"size_px": [619, 622], "pivot_px": [303, 308], "file": "base_underlay.png"},
  "base_middle": {"size_px": [8, 3], "pivot_px": [4, 0], "file": "base_middle.png",
                  "hit_runs_px": [[], [[0, 2], [5, 8]], [[1, 3]]]},
  "base_overlay": {"size_px": [456, 476], "pivot_px": [170, 95], "file": "base_overlay.png"}
 },
 "kinematics": {"stylus_at_rest_u": [6.0, 365.0], "rest_degrees": 0},
 "outline_band_u": 4, "hit_margin_u": 4
}
"""

private func threeLayerManifest(_ json: String = threeLayerJSON) throws -> SpriteSkinManifest {
    try SpriteSkinManifest.decode(Data(json.utf8))
}

private let probe = SpriteSkinDefinition(id: "technics-sl1200g", placement: .classic)

struct MiddleLayerSkinTests {
    @Test func manifestDecodesTheOptionalMiddleLayer() throws {
        let middle = try #require(try threeLayerManifest().layers.baseMiddle)
        #expect(middle.file == "base_middle.png" && middle.sizePx == [8, 3] && middle.pivotPx == [4, 0])
        #expect(middle.hitRunsPx == [[], [[0, 2], [5, 8]], [[1, 3]]])
    }

    @Test func middleLayerWithoutHitRunsIsRejected() {
        let json = threeLayerJSON.replacingOccurrences(of: ",\n                  \"hit_runs_px\": [[], [[0, 2], [5, 8]], [[1, 3]]]", with: "")
        #expect(json != threeLayerJSON)
        #expect(throws: SkinError.invalidManifest) { try threeLayerManifest(json) }
    }

    @Test func middleFileNameMustBeTheContractConstant() throws {
        let json = threeLayerJSON.replacingOccurrences(of: "\"file\": \"base_middle.png\"", with: "\"file\": \"x.png\"")
        #expect(throws: SkinError.invalidManifest) { try TurntableSkin.sprite(probe, manifest: threeLayerManifest(json)) }
    }

    @Test func spriteSkinCarriesTheMiddleFrameAndHitMask() throws {
        let skin = try TurntableSkin.sprite(probe, manifest: threeLayerManifest())
        #expect(skin.baseMiddle == ArtworkFrame(size: CGSize(width: 2, height: 0.75), localPivot: CGPoint(x: 1, y: 0)))
        #expect(skin.middleHitMask == PixelRuns(rows: [[], [0..<2, 5..<8], [1..<3]]))
        #expect(skin.spriteLayers?.middle == skin.baseMiddle)
        _ = try TurntableSkinResolver.resolve(skin).get()
    }

    /// 遮罩只認逐像素列：半開區間、同列多段
    @Test func pixelRunsContainOnlyTheirOwnPixels() {
        let mask = PixelRuns(rows: [[], [0..<2, 5..<8], [1..<3]])
        #expect(mask.contains(x: 0, y: 1) && mask.contains(x: 7, y: 1) && mask.contains(x: 2, y: 2))
        #expect(!mask.contains(x: 2, y: 1) && !mask.contains(x: 4, y: 1), "同列兩段之間的透明處")
        #expect(!mask.contains(x: 0, y: 0) && !mask.contains(x: 1, y: 3) && !mask.contains(x: -1, y: 1))
    }

    @Test func middleWithoutHitMaskIsAnInvalidOutline() throws {
        let skin = try TurntableSkin.sprite(probe, manifest: threeLayerManifest()).replacing(middleHitMask: nil)
        #expect(throws: SkinError.invalidOutline) { try TurntableSkinResolver.resolve(skin).get() }
    }

    @Test(arguments: [
        PixelRuns(rows: [[], [0..<2]]),                 // 列數 ≠ 中層像素高 3
        PixelRuns(rows: [[], [0..<9], []]),             // 超出寬 8
        PixelRuns(rows: [[], [3..<5, 4..<6], []]),      // 同列重疊
        PixelRuns(rows: [[], [5..<6, 0..<2], []]),      // 同列不遞增
    ])
    func hitMaskMustFitTheMiddleFrame(mask: PixelRuns) throws {
        let skin = try TurntableSkin.sprite(probe, manifest: threeLayerManifest()).replacing(middleHitMask: mask)
        #expect(throws: SkinError.invalidOutline) { try TurntableSkinResolver.resolve(skin).get() }
    }

    /// 兩層 golden（Codex r1-8）：Pioneer 現檔原封不動照樣解得開，沒有中層、必備圖層解包不受影響、preflight 檔清單只有 72 檔
    @Test func twoLayerSkinIsUnchanged() throws {
        let skin = try SpriteSkinFixture.bundled(.sArm1200).spec
        #expect(skin.baseMiddle == nil && skin.middleHitMask == nil)
        let layers = try #require(skin.spriteLayers)
        #expect(layers.middle == nil)
        let files = TurntableSkinCatalog.assetFiles(of: skin, layers: layers).map(\.name)
        #expect(files.count == 72 && !files.contains(SpriteSkinAssets.middleFile))
        #expect(files.suffix(2) == [SpriteSkinAssets.baseFile, SpriteSkinAssets.overlayFile])
    }
}
