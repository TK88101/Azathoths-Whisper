import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// B2 計劃 T3：renderer 對比指標。同一幀渲染兩次（有字／沒字），在「兩張圖不同」的像素上取平均色：
// 有字那張＝字的顏色，沒字那張＝字後面的背景（含背景層與顆粒、暈影）。以 WCAG 相對亮度公式算比值，主字要 ≥ 4.5:1。
// 這是影像平均色的代理指標（受反鋸齒與紋理影響），不宣稱符合 WCAG。歌詞為編造句
@MainActor
@Suite("LyricsFX contrast")
struct LyricsFXContrastTests {
    static let canvas = CGSize(width: 640, height: 400)
    static let minimum = 4.5
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 1, end: 9, text: "lanterns over the quiet water", isChorus: false),
    ], source: .embeddedLRC, duration: 20)
    /// 停穩的時刻（fadeUp 進場最長 0.6 s）
    static let settled = 5.0

    private static func render(_ recipe: ComposedRecipe, withGlyphs: Bool) -> CGImage? {
        let measurer = CoreTextMeasurer()
        let paths = GlyphPathCache()
        let view = Canvas { context, size in
            var plan = LyricsFXFrame.plan(timeline: timeline, time: settled, size: size, motion: .full, recipe: .composed(recipe), measurer: measurer)
            if !withGlyphs { plan.glyphs = [] }
            LyricsFXCanvas.draw(plan, in: context, size: size, paths: paths)
        }
        .frame(width: canvas.width, height: canvas.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// 字像素＝兩張圖任一通道差 > 48 的像素；回傳（比值, 字像素數）
    static func contrast(_ recipe: ComposedRecipe) -> (ratio: Double, pixels: Int)? {
        guard let lit = render(recipe, withGlyphs: true), let bare = render(recipe, withGlyphs: false) else { return nil }
        let a = rgba(lit), b = rgba(bare)
        var text = (0.0, 0.0, 0.0), back = (0.0, 0.0, 0.0), count = 0
        for i in stride(from: 0, to: a.count, by: 4) where (0..<3).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > 48 }) {
            text = (text.0 + Double(a[i]), text.1 + Double(a[i + 1]), text.2 + Double(a[i + 2]))
            back = (back.0 + Double(b[i]), back.1 + Double(b[i + 1]), back.2 + Double(b[i + 2]))
            count += 1
        }
        guard count > 0 else { return nil }
        let n = Double(count) * 255
        let l1 = RGB(red: text.0 / n, green: text.1 / n, blue: text.2 / n).relativeLuminance
        let l2 = RGB(red: back.0 / n, green: back.1 / n, blue: back.2 / n).relativeLuminance
        return ((max(l1, l2) + 0.05) / (min(l1, l2) + 0.05), count)
    }

    static func recipe(backdrop: String, palette: String) -> ComposedRecipe {
        ComposedRecipe(font: "Bebas", backdrop: backdrop, enter: "fadeUp", exit: "up", fx1: "none", fx2: "none", palette: palette, seed: 5,
                       profile: SongProfile(axes: [.aggression: 0.3], tags: [.britpop]))
    }

    /// B1 使用者簽字的配色，字本身就是低對比（緋紅字＋深紫黑底，比值約 1.6–2.0）。B2 不回頭改，釘住；改它要使用者重新簽字。
    /// 例外不是豁免：仍要高於地板，新背景不得把它壓到看不見
    static let signedLowContrastPalettes: Set<String> = ["crimsonVelvet"]
    static let signedLowContrastFloor = 1.5

    /// 實際會被同一個樂團一起抽到的（背景, 配色）：兩者對該團 fit > 0，且亮暗相容
    static let reachablePairs: [(backdrop: String, palette: String)] = {
        var pairs = Set<String>()
        for band in SongProfileResolver.bandTable {
            let fits = { (slot: FXSlot) in LyricsFXCatalog.components(in: slot).filter { Composer.fit($0, band.profile) > 0 } }
            let palettes = fits(.palette)
            for backdrop in fits(.backdrop) {
                guard case .backdrop(let kind) = backdrop.payload else { continue }
                for palette in palettes {
                    guard case .palette(let colors) = palette.payload else { continue }
                    if let tone = kind.tone, !tone.accepts(colors) { continue }
                    pairs.insert("\(backdrop.id)|\(palette.id)")
                }
            }
        }
        return pairs.sorted().map { pair in
            let parts = pair.split(separator: "|").map(String.init)
            return (parts[0], parts[1])
        }
    }()

    @Test func mainTextStaysReadableOnEveryReachableBackdrop() {
        var failures: [String] = []
        for pair in Self.reachablePairs {
            guard let result = Self.contrast(Self.recipe(backdrop: pair.backdrop, palette: pair.palette)) else {
                failures.append("\(pair.palette)＋\(pair.backdrop)：量不到字"); continue
            }
            let floor = Self.signedLowContrastPalettes.contains(pair.palette) ? Self.signedLowContrastFloor : Self.minimum
            if result.ratio < floor { failures.append("\(pair.palette)＋\(pair.backdrop)：\(String(format: "%.2f", result.ratio))") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    @Test func theSignedLowContrastPaletteIsStillReachable() {
        #expect(Self.reachablePairs.contains { $0.palette == "crimsonVelvet" }, "沒有團抽得到就該從例外清單拿掉")
    }
}
