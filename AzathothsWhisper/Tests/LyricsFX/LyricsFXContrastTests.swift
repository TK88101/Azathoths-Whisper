import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// 讀得到的檢查 G1（docs/plans/2026-10-20-lyrics-fx-readability-gate.md；改寫自 B2 計劃 T3 的平均色指標）：
// 同一 plan、同一時刻畫三張——全部、去掉主字（glyphs＋unlit）、純背景（再去掉 ghosts 與 boxes）。
// 主字核心像素＝「全部」與「去掉主字」任一通道差 > 48、且與配色 fg 每通道差 ≤ 24（字的內部）；每個核心像素算「全部」該像素與「純背景」同座標的 WCAG 相對亮度比，
// 取 5 百分位，要 ≥ 4.5（字完全顯示的定格；出退場另由 G2／G3 管）。代理指標，不宣稱符合 WCAG。歌詞為編造句
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

    enum Layers { case all, withoutMainText, backgroundOnly }

    private static func render(_ recipe: ComposedRecipe, layers: Layers) -> CGImage? {
        let measurer = CoreTextMeasurer()
        let paths = GlyphPathCache()
        let view = Canvas { context, size in
            var plan = LyricsFXFrame.plan(timeline: timeline, time: settled, size: size, motion: .full, recipe: .composed(recipe), measurer: measurer)
            if layers != .all { plan.glyphs = []; plan.unlit = [] }
            if layers == .backgroundOnly { plan.ghosts = []; plan.boxes = [] }
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

    static let percentile = 0.05
    /// 核心像素與字色的每通道容差（0–255）
    static let coreTolerance = 24

    private static func luminance(_ p: [UInt8], _ i: Int) -> Double {
        RGB(red: Double(p[i]) / 255, green: Double(p[i + 1]) / 255, blue: Double(p[i + 2]) / 255).relativeLuminance
    }

    /// 回傳（核心像素對比的 5 百分位, 核心像素數）
    static func contrast(_ recipe: ComposedRecipe) -> (ratio: Double, pixels: Int)? {
        guard let full = render(recipe, layers: .all), let withoutMain = render(recipe, layers: .withoutMainText),
              let background = render(recipe, layers: .backgroundOnly) else { return nil }
        let a = rgba(full), m = rgba(withoutMain), b = rgba(background)
        guard let fg = LyricsFXCatalog.palette(recipe.palette)?.fg else { return nil }
        let ink = [fg.red, fg.green, fg.blue].map { Int(($0 * 255).rounded()) }
        var ratios: [Double] = []
        // 核心＝有字才不同、且顏色接近字色（排除反鋸齒邊緣與光暈、描邊的發光像素）
        for i in stride(from: 0, to: a.count, by: 4)
        where (0..<3).contains(where: { abs(Int(a[i + $0]) - Int(m[i + $0])) > 48 }) && (0..<3).allSatisfy({ abs(Int(a[i + $0]) - ink[$0]) <= coreTolerance }) {
            let l1 = luminance(a, i), l2 = luminance(b, i)
            ratios.append((max(l1, l2) + 0.05) / (min(l1, l2) + 0.05))
        }
        guard !ratios.isEmpty else { return nil }
        ratios.sort()
        return (ratios[Int(Double(ratios.count - 1) * percentile)], ratios.count)
    }

    static func recipe(backdrop: String, palette: String, fx: String = "none") -> ComposedRecipe {
        ComposedRecipe(font: "Bebas", backdrop: backdrop, enter: "fadeUp", exit: "up", fx1: fx, fx2: "none", palette: palette, seed: 5,
                       profile: SongProfile(axes: [.aggression: 0.3], tags: [.britpop]))
    }


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
    static func readabilityFailure(backdrop: String, palette: String, fx: String = "none", who: [String] = []) -> String? {
        let label = "\(palette)＋\(backdrop)" + (fx == "none" ? "" : "＋\(fx)") + (who.isEmpty ? "" : "（\(who.joined(separator: "、"))）")
        guard let result = contrast(recipe(backdrop: backdrop, palette: palette, fx: fx)) else { return "\(label)：量不到字" }
        return result.ratio < minimum ? "\(label)：\(String(format: "%.2f", result.ratio))" : nil
    }

    @Test func mainTextStaysReadableOnEveryReachableBackdrop() {
        let failures = Self.reachablePairs.compactMap { Self.readabilityFailure(backdrop: $0.backdrop, palette: $0.palette) }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    /// 會改變字本身顏色或邊緣的效果：每組抽得到的（背景, 配色）各加一個量一次
    @Test(arguments: ["glow", "neonstroke", "rgbsplit", "misreg", "reflect"])
    func mainTextStaysReadableWithEffectsThatTouchTheText(fx: String) {
        let failures = Self.reachablePairs.compactMap { Self.readabilityFailure(backdrop: $0.backdrop, palette: $0.palette, fx: fx) }
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
        for band in SongProfileResolver.batchThree + SongProfileResolver.batchFour + SongProfileResolver.batchFive {
            for (backdrop, palettes) in PlayableSpace.of(band.profile)?.paletteByBackdrop ?? [:] {
                guard case .backdrop(let kind)? = LyricsFXCatalog.component(backdrop)?.payload, let tone = kind.tone else { continue }
                for palette in palettes {
                    #expect(LyricsFXCatalog.palette(palette).map(tone.accepts) == true, "\(band.name)：\(backdrop) 配到不相容的 \(palette)")
                }
            }
        }
    }

    /// crimsonVelvet 原本是 B1 簽字的低對比例外（字 #8A1C2B，約 2.1）。2026-10-20 使用者同意「只調亮字色、例外拿掉」，看新舊並排後選 #FF6E6E（實測 4.92–5.47）：
    /// 交響類曲風每兩次抽到一次，讀不清楚不行。每個背景都要達標、沒有例外
    @Test func crimsonVelvetMeetsTheMinimumOnEveryBackdropWithoutAnException() {
        let backdrops = Self.reachablePairs.filter { $0.palette == "crimsonVelvet" }.map(\.backdrop)
        #expect(!backdrops.isEmpty)
        for backdrop in backdrops {
            #expect(Self.readabilityFailure(backdrop: backdrop, palette: "crimsonVelvet") == nil, "\(backdrop)")
        }
    }
}
