import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import YogSothothsEcho

/// CR-039 §11.4（事先登錄，實作後不改）：正式合成路徑（VinylRecordView：labelView＋旋轉＋drawingGroup，classic）
/// 「遮罩路徑」vs「即時路徑（現行 LabelRing）」；角度 0°／37°；三組配色；只比標籤圓內；RGBA 8-bit；
/// 每通道差 ≤ 2 的像素 ≥ 99.9%，且沒有任何像素任一通道差 > 8
@MainActor
struct LabelPrintRenderTests {
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
        let image = try #require(renderer.cgImage)
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width)
    }

    private static func record(_ colors: AlbumColors, angle: Double, store: LabelPrintStore) -> VinylRecordView {
        var view = VinylRecordView(side: side, style: .classic, splash: .style1, colors: colors,
                                   label: .init(title: "Title", artist: "Artist"), angle: angle)
        view.labelPrints = store
        return view
    }

    @Test(arguments: [0.0, 37.0])
    func maskPathMatchesLivePath(angle: Double) throws {
        let key = LabelPrintKey.make(recordSide: Self.side, displayScale: Self.scale, digits: VinylAssetsEasterEgg.digits)
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
            let within = Double(compared - over2) / Double(compared)
            print("§11.4 angle=\(angle) \(palette.name): compared=\(compared) over2=\(over2) maxDiff=\(maxDiff)")
            #expect(within >= 0.999, "\(palette.name) angle \(angle): \(over2)/\(compared) px differ > 2")
            #expect(maxDiff <= 8, "\(palette.name) angle \(angle): max channel diff \(maxDiff)")
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
