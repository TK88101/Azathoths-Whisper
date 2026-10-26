import Testing

@testable import YogSothothsEcho

// S5 T4（sprint-5-detail.md D7；spec「颜色取自封面主色」）：近似 Palette——主色＝人口最多、文字色＝白對比 ≥ 4.5 用白否則黑、
// 柔和色依 Target.MUTED 選；取不到的項各自回退（BLUR 主題值）。全部用合成圖（不用真封面）

private typealias Pixel = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

private func image(_ parts: [(Pixel, Int)]) -> [UInt8] {
    parts.flatMap { pixel, count in Array(repeating: [pixel.r, pixel.g, pixel.b, pixel.a], count: count).flatMap { $0 } }
}

private func near(_ c: RGBColor, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
    abs(c.r * 255 - Double(r)) < 1 && abs(c.g * 255 - Double(g)) < 1 && abs(c.b * 255 - Double(b)) < 1
}

struct AlbumPaletteTests {
    @Test func singleSaturatedColor() {
        let colors = AlbumPalette.extract(rgba: image([((200, 30, 30, 255), 100)]))
        #expect(near(colors.primary, 200, 30, 30))
        #expect(colors.text == .white)
        #expect(colors.secondary == AlbumColors.fallback.secondary)   // 飽和度 0.74，不在 MUTED 範圍
    }

    @Test func majorityColorWins() {
        let colors = AlbumPalette.extract(rgba: image([((20, 60, 160, 255), 70), ((230, 200, 40, 255), 30)]))
        #expect(near(colors.primary, 20, 60, 160))
    }

    @Test func mutedSwatchIsPicked() {
        // 主色鮮紅；另有低飽和中亮度灰藍（HSL s≈0.2、l≈0.5）與太暗的灰（l≈0.1）
        let colors = AlbumPalette.extract(rgba: image([((220, 20, 20, 255), 60), ((102, 115, 153, 255), 25),
                                                       ((30, 25, 25, 255), 15)]))
        #expect(near(colors.secondary, 102, 115, 153))
    }

    @Test func lightPrimaryGetsBlackText() {
        let colors = AlbumPalette.extract(rgba: image([((240, 236, 220, 255), 10)]))
        #expect(colors.text == .black)
    }

    @Test func transparentOrEmptyFallsBack() {
        #expect(AlbumPalette.extract(rgba: image([((255, 0, 0, 0), 50)])) == .fallback)
        #expect(AlbumPalette.extract(rgba: []) == .fallback)
        #expect(AlbumPalette.extract(rgba: [1, 2, 3]) == .fallback)   // 不足一個像素
    }

    /// 同人口時取量化格較小者，結果不隨像素順序而變
    @Test func deterministicTieBreak() {
        let a = AlbumPalette.extract(rgba: image([((10, 10, 200, 255), 5), ((200, 10, 10, 255), 5)]))
        let b = AlbumPalette.extract(rgba: image([((200, 10, 10, 255), 5), ((10, 10, 200, 255), 5)]))
        #expect(a == b)
    }

    @Test func contrastRatio() {
        #expect(abs(AlbumPalette.contrast(.white, .black) - 21) < 1e-9)
        #expect(AlbumPalette.contrast(.white, .white) == 1)
    }
}

/// v2.1 T11：黑主色的 TRANSPARENT 改取封面上最多的鮮豔色相（MCR 黑底血跡被 MUTED 挑成膚色豆沙粉）。
/// 只看飽和 ≥ 0.35、明度 0.2–0.75 的像素，30° 一箱（0° 置中），最多的箱 ≥ 全部不透明像素 1% 才算
struct AlbumVividTests {
    @Test func bloodRedOnBlackWinsAcrossZeroDegrees() throws {
        // 近黑 900、低飽和膚色 80（不入選）、鮮紅 20 = 色相 354° 與 6° 各 10（同一箱）
        let rgba = image([((10, 10, 12, 255), 900), ((200, 170, 160, 255), 80), ((200, 20, 40, 255), 10), ((210, 40, 20, 255), 10)])
        let vivid = try #require(AlbumPalette.vivid(rgba: rgba))
        #expect(near(vivid, 205, 30, 30))
        #expect(AlbumPalette.extract(rgba: rgba).vivid == vivid)
    }

    @Test func tooFewVividPixelsGiveNothing() {
        #expect(AlbumPalette.vivid(rgba: image([((10, 10, 12, 255), 995), ((200, 20, 40, 255), 5)])) == nil)
    }

    @Test func transparentOrGreyGivesNothing() {
        #expect(AlbumPalette.vivid(rgba: image([((200, 20, 40, 0), 100)])) == nil)
        #expect(AlbumPalette.vivid(rgba: image([((128, 128, 128, 255), 100)])) == nil)
        #expect(AlbumColors.fallback.vivid == nil)
    }

    /// 同票取箱號小者（紅 0 號箱 vs 綠 4 號箱）
    @Test func tieGoesToTheLowerBin() throws {
        let vivid = try #require(AlbumPalette.vivid(rgba: image([((40, 200, 40, 255), 50), ((200, 30, 30, 255), 50)])))
        #expect(near(vivid, 200, 30, 30))
    }
}
