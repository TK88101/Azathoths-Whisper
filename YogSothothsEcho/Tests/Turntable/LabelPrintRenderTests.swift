import CoreGraphics
import CryptoKit
import Foundation
import SwiftUI
import Testing

@testable import YogSothothsEcho

/// CR-039 §11.4 v1.0「渲染漂移哨兵」：正式合成路徑（VinylRecordView：labelView＋旋轉＋drawingGroup，classic）
/// 「遮罩路徑」vs「即時路徑（現行 LabelRing）」；角度 0°／37°；三組配色；只比標籤圓內；RGBA 8-bit。
/// **不是外觀通過依據**（通過標準＝使用者 iPad 目視四格）：只防無意漂移。紅＝調查並重做目視，不自動判外觀失敗。
/// 基線＝計劃附錄 G.2（2681c6c、iPad Pro 13-inch (M5) 模擬器、iOS 27.0、條碼有）；只能隨程式變更＋原因紀錄＋重跑六格＋使用者目視簽核更新
@MainActor
struct LabelPrintRenderTests {
    private struct Baseline {
        let over2: Int
        let maxDiff: Int
    }

    /// 防漂移的營運值（不是品質門檻）
    private static let over2Factor = 1.1
    private static let maxDiffSlack = 8
    private static let baselines: [String: Baseline] = [
        "white-on-black@0": .init(over2: 562, maxDiff: 118),
        "black-on-white@0": .init(over2: 538, maxDiff: 118),
        "gray-on-fallback@0": .init(over2: 47, maxDiff: 40),
        "white-on-black@37": .init(over2: 19_921, maxDiff: 234),
        "black-on-white@37": .init(over2: 19_922, maxDiff: 234),
        "gray-on-fallback@37": .init(over2: 14_859, maxDiff: 80),
    ]

    /// 環境紀錄（寫進 log）；條碼只印模組序列 SHA-256 的前 8 碼——數字本身只在本機、不進 repo
    private static func environmentLine(_ key: LabelPrintKey) -> String {
        let env = ProcessInfo.processInfo.environment
        let barcode = key.barcode.map { modules in
            let bits = modules.map { $0 ? "1" : "0" }.joined()
            return SHA256.hash(data: Data(bits.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        } ?? "absent"
        let xcode = Bundle.main.infoDictionary?["DTXcodeBuild"] as? String ?? "?"
        return "§11.4 sentinel env: runtime=\(env["SIMULATOR_RUNTIME_VERSION"] ?? "?") model=\(env["SIMULATOR_MODEL_IDENTIFIER"] ?? "?") "
            + "xcodeBuild=\(xcode) barcode=\(barcode) diameterPt=\(key.diameter) scale=\(key.scale)"
    }
    private static let side: CGFloat = 700
    private static let scale: CGFloat = 2
    private static let palettes: [(name: String, colors: AlbumColors)] = [
        ("white-on-black", AlbumColors(primary: RGBColor(hex: 0x000000), text: .white, secondary: RGBColor(hex: 0x46403C))),
        ("black-on-white", AlbumColors(primary: RGBColor(hex: 0xFFFFFF), text: .black, secondary: RGBColor(hex: 0x46403C))),
        ("gray-on-fallback", AlbumColors(primary: RGBColor(hex: 0x1E1D1D), text: RGBColor(hex: 0x747474), secondary: RGBColor(hex: 0x46403C))),
    ]

    private static func pixels(_ view: some View) throws -> (data: [UInt8], width: Int) {
        let renderer = ImageRenderer(content: view.frame(width: side, height: side))
        renderer.scale = scale
        // 同 SpineBakeTests 的讀回（sRGB、premultipliedLast）；換讀回方式會動到 G.2 基線
        let pixels = SpineBakeTests.pixels(try #require(renderer.cgImage))
        return (pixels.data, pixels.width)
    }

    private static func record(_ colors: AlbumColors, angle: Double, store: LabelPrintStore) -> VinylRecordView {
        var view = VinylRecordView(side: side, style: .classic, splash: .style1, colors: colors,
                                   label: .init(title: "Title", artist: "Artist"), angle: angle)
        view.labelPrints = store
        return view
    }

    @Test(arguments: [0.0, 37.0])
    func maskPathStaysWithinDriftBaseline(angle: Double) throws {
        let key = LabelPrintKey.make(recordSide: Self.side, displayScale: Self.scale, digits: VinylAssetsEasterEgg.digits)
        print(Self.environmentLine(key))
        let cached = LabelPrintStore(renderer: ImageRendererLabelPrint())
        cached.request(key)
        guard case .ready = cached.lookup(key) else { Issue.record("mask not ready"); return }
        let live = LabelPrintStore(renderer: nil)
        for palette in Self.palettes {
            let a = try Self.pixels(Self.record(palette.colors, angle: angle, store: live))
            let b = try Self.pixels(Self.record(palette.colors, angle: angle, store: cached))
            #expect(a.width == b.width)
            let width = a.width, center = Double(width) / 2
            let radius = Double(key.diameter * Self.scale) / 2 - 1
            var compared = 0, over2 = 0, maxDiff = 0
            for y in 0..<width {
                for x in 0..<width {
                    let dx = Double(x) + 0.5 - center, dy = Double(y) + 0.5 - center
                    guard dx * dx + dy * dy < radius * radius else { continue }
                    compared += 1
                    let i = (y * width + x) * 4
                    let diff = (0..<4).map { abs(Int(a.data[i + $0]) - Int(b.data[i + $0])) }.max()!
                    if diff > 2 { over2 += 1 }
                    maxDiff = max(maxDiff, diff)
                }
            }
            print("§11.4 angle=\(angle) \(palette.name): compared=\(compared) over2=\(over2) maxDiff=\(maxDiff)")
            let name = "\(palette.name)@\(Int(angle))"
            let baseline = try #require(Self.baselines[name], "no baseline for \(name)")
            let over2Limit = Int((Double(baseline.over2) * Self.over2Factor).rounded(.down))
            #expect(over2 <= over2Limit, "drift \(name): over2 \(over2) > \(over2Limit)（基線 \(baseline.over2)）——調查並重做目視")
            #expect(maxDiff <= baseline.maxDiff + Self.maxDiffSlack,
                    "drift \(name): maxDiff \(maxDiff) > \(baseline.maxDiff + Self.maxDiffSlack)——調查並重做目視")
        }
    }

    /// 遮罩圖＝偶數邊長的畫布、不小於標籤像素直徑（置中後圓心落在整數像素，顯示不縮放）
    @Test func imageRendererProducesEvenCanvasCoveringTheLabel() throws {
        let key = LabelPrintKey.make(recordSide: Self.side, displayScale: Self.scale, digits: nil)
        let image = try #require(ImageRendererLabelPrint().render(key))
        #expect(image.width == key.canvasPixels && image.height == key.canvasPixels)
        #expect(key.canvasPixels.isMultiple(of: 2))
        #expect(Double(key.canvasPixels) >= Double(key.diameter * Self.scale))
        #expect(Double(key.canvasPixels) < Double(key.diameter * Self.scale) + 2)
    }
}
