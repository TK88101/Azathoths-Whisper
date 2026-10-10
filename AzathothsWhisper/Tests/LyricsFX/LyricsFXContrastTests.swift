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

    /// 量一組（背景, 配色）的主字對比；不及格回傳失敗說明（`who`＝抽得到它的團，可省）
    static func readabilityFailure(backdrop: String, palette: String, who: [String] = []) -> String? {
        let label = "\(palette)＋\(backdrop)" + (who.isEmpty ? "" : "（\(who.joined(separator: "、"))）")
        guard let result = contrast(recipe(backdrop: backdrop, palette: palette)) else { return "\(label)：量不到字" }
        let floor = signedLowContrastPalettes.contains(palette) ? signedLowContrastFloor : minimum
        return result.ratio < floor ? "\(label)：\(String(format: "%.2f", result.ratio))" : nil
    }

    @Test func mainTextStaysReadableOnEveryReachableBackdrop() {
        let failures = Self.reachablePairs.compactMap { Self.readabilityFailure(backdrop: $0.backdrop, palette: $0.palette) }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    /// 各團實際抽得到的（背景, 配色）——含 `compatiblePalettes` 找不到相容配色而回退時抽到的不相容組合，
    /// 那些不在 `reachablePairs` 裡（B2 批 2 計劃 V5）。值＝抽得到這一組的團
    static let playablePairs: [String: [String]] = SongProfileResolver.bandTable.reduce(into: [:]) { pairs, band in
        for (backdrop, palettes) in PlayableSpace.of(band.profile)?.paletteByBackdrop ?? [:] {
            for palette in palettes { pairs["\(backdrop)|\(palette)", default: []].append(band.name) }
        }
    }

    /// 上一條已量過的組合不重量（兩條共用同一份判定），這裡只補回退路徑才抽得到的那些
    @Test func everyPlayablePairStaysReadable() {
        let measured = Set(Self.reachablePairs.map { "\($0.backdrop)|\($0.palette)" })
        let failures = Self.playablePairs.filter { !measured.contains($0.key) }.sorted { $0.key < $1.key }.compactMap { pair, bands in
            let parts = pair.split(separator: "|").map(String.init)
            return Self.readabilityFailure(backdrop: parts[0], palette: parts[1], who: bands)
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    /// B2 批 2 起的團：抽得到的每組（背景, 配色）都亮暗相容——也就是沒有一組是靠回退抽到的
    @Test func batchThreeNeverFallsBackToAnIncompatiblePalette() {
        for band in SongProfileResolver.batchThree {
            for (backdrop, palettes) in PlayableSpace.of(band.profile)?.paletteByBackdrop ?? [:] {
                guard case .backdrop(let kind)? = LyricsFXCatalog.component(backdrop)?.payload, let tone = kind.tone else { continue }
                for palette in palettes {
                    #expect(LyricsFXCatalog.palette(palette).map(tone.accepts) == true, "\(band.name)：\(backdrop) 配到不相容的 \(palette)")
                }
            }
        }
    }

    @Test func theSignedLowContrastPaletteIsStillReachable() {
        #expect(Self.reachablePairs.contains { $0.palette == "crimsonVelvet" }, "沒有團抽得到就該從例外清單拿掉")
    }
}
