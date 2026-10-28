import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// CR-034 增補 A T5（yse-1.0.1-skin-picker.md §4.4）：選擇器畫出來的樣子——格子底是一致的中性灰、預覽圖來自共用 renderer、
// 轉場中只淡內容、預覽失敗畫後備符號（皮膚照樣列出）

/// 每層一個純色（唱臂＝綠）：在格子裡找得到綠＝預覽圖確實畫上去
private struct SolidPreviewSource: SkinPreviewImageSource {
    let failing: Bool

    func image(_ kind: SkinPreviewLayer.Kind, skin: ResolvedTurntableSkin, maxPixelSize: Int) async -> CGImage? {
        guard !failing else { return nil }
        let (r, g, b): (CGFloat, CGFloat, CGFloat) = kind == .arm ? (0, 1, 0) : (0.6, 0.6, 0.6)
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: r, green: g, blue: b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()
    }
}

@MainActor
struct TurntableSkinPickerRenderTests {
    let nowPlaying = NowPlayingViewModel(now: ManualNow().now, sleep: { _ in })
    static let size = CGSize(width: TurntableSkinPicker.threeColumnWidth, height: 260)

    private func makeModel(failing: Bool = false, transitionSleep: @escaping @Sendable (Duration) async -> Void = { _ in }) throws
        -> TurntableViewModel {
        TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: InMemorySettingsStore(), displayScale: 1, artwork: { _ in nil },
                           palette: { _ in .fallback }, sleep: { _ in }, transitionSleep: transitionSleep,
                           catalog: TurntableSkinCatalog(skins: [.classic, try SpriteSkinFixture.bundled()]),
                           spriteDecode: { _ in nil }, previewSource: SolidPreviewSource(failing: failing))
    }

    /// 先把每格預覽載好（ImageRenderer 不跑 .task），再畫
    private func render(_ model: TurntableViewModel) async throws -> CGImage {
        for skin in model.availableSkins {
            await model.previews.load(skin, crop: .wholeArm, pixelSize: TurntableSkinPicker.artSize)
        }
        // 靠上對齊：格子的 y 從 0 起算
        let view = TurntableSkinPicker(model: model).frame(width: Self.size.width, height: Self.size.height, alignment: .top)
            .environment(\.colorScheme, .dark).environment(\.displayScale, 1)
        return try #require(PixelProbe.image(view, size: Self.size))
    }

    /// 第 index 格的預覽區（格子內距 10、預覽 96×150 置中）
    private func artRect(_ index: Int, in image: CGImage) -> CGRect {
        let columns = 3, spacing = TurntableSkinPicker.spacing
        let width = (CGFloat(image.width) - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let x = CGFloat(index) * (width + spacing) + (width - TurntableSkinPicker.artSize.width) / 2
        return CGRect(x: x, y: 10, width: TurntableSkinPicker.artSize.width, height: TurntableSkinPicker.artSize.height)
    }

    private func greenest(_ image: CGImage, in rect: CGRect) -> RGBColor {
        var best = RGBColor(r: 0, g: 0, b: 0)
        for y in stride(from: rect.minY, to: rect.maxY, by: 3) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 3) {
                let c = PixelProbe.color(image, at: CGPoint(x: x, y: y))
                if c.g - c.r > best.g - best.r { best = c }
            }
        }
        return best
    }

    @Test func eachTileShowsItsPreviewOnTheNeutralBackground() async throws {
        let image = try await render(try makeModel())
        for index in 0..<2 {
            let art = artRect(index, in: image)
            let green = greenest(image, in: art)
            #expect(green.g > 0.9 && green.r < 0.1, "第 \(index) 格看得到唱臂（\(green)）")
            // 格子左上內側（預覽與框線之外）＝中性灰 0.34
            let background = PixelProbe.color(image, at: CGPoint(x: art.minX - 4, y: art.minY + 4))
            #expect(abs(background.r - 0.34) < 0.03 && abs(background.g - background.r) < 0.01, "\(background)")
        }
    }

    /// 轉場中：內容變淡（唱臂不再是純綠），但格子仍在
    @Test func blockedTilesFadeTheirContent() async throws {
        let model = try makeModel(transitionSleep: { _ in await withCheckedContinuation { _ in } })
        model.open(reduceMotion: false)
        #expect(model.skinApplyBlock != nil)
        let image = try await render(model)
        let green = greenest(image, in: artRect(0, in: image))
        #expect(green.g < 0.75 && green.g - green.r > 0.1, "淡了但看得到（\(green)）")
    }

    /// 預覽失敗：格子裡沒有唱臂圖（後備符號），皮膚仍列出可選（r1-3）
    @Test func previewFailureDrawsTheFallbackButKeepsTheSkin() async throws {
        let model = try makeModel(failing: true)
        let image = try await render(model)
        let green = greenest(image, in: artRect(1, in: image))
        #expect(green.g - green.r < 0.2, "沒有預覽圖（\(green)）")
        #expect(model.previews.isUnavailable("s-arm-1200") && model.canSelectSkin)
    }
}
