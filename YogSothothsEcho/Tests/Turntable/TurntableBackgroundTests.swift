import Testing
import UIKit

@testable import YogSothothsEcho

// S5 T8（sprint-5-detail.md §4.7；spec「BLUR 主題背景」）：封面縮到 1/8 → 高斯 σ 10.6（縮圖像素）→ 疊黑 20%；
// 取色從 UIImage 縮到 64×64 再算（大圖不整張解碼進記憶體）

private func solid(_ color: UIColor, _ size: CGFloat) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        .image { context in color.setFill(); context.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
}

struct TurntableBackgroundTests {
    @Test func parametersMatchSpec() {
        #expect(TurntableBackground.downscale == 8)
        #expect(abs(TurntableBackground.sigma - (0.4 * 25 + 0.6)) < 1e-9)
        #expect(TurntableBackground.dimOpacity == 0.2)
    }

    @Test func blurredImageIsOneEighthSize() throws {
        let blurred = try #require(TurntableBackground.blurred(solid(.red, 800)))
        #expect(blurred.cgImage?.width == 100 && blurred.cgImage?.height == 100)
    }

    @Test func tinyImageStillProducesAtLeastOnePixel() {
        #expect(TurntableBackground.blurred(solid(.red, 4))?.cgImage.map { $0.width >= 1 } == true)
    }

    @Test func paletteFromImage() {
        let colors = AlbumPalette.extract(from: solid(UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1), 600))
        #expect(abs(colors.primary.r - 0.8) < 0.02 && colors.primary.g < 0.15 && colors.text == .white)
    }
}
