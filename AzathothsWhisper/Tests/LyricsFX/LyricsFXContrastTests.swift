import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// 讀得到的檢查 G1（docs/plans/2026-10-20-lyrics-fx-readability-gate.md；改寫自 B2 計劃 T3 的平均色指標）：
// 同一 plan、同一時刻畫四張——全部、純背景（去掉 glyphs／unlit／ghosts／boxes）、主字單獨（只留完全顯示的主字、不描邊、無光暈與圖層）、什麼都沒有。
// 主字核心像素＝「主字單獨」與「什麼都沒有」任一通道差 > 48 的字形，再內縮 1 像素（去掉反鋸齒邊緣）——只看字形、不看顏色，
// 效果把字內部改成什麼顏色都照量；每個核心像素算「全部」該像素與「純背景」同座標的 WCAG 相對亮度比，
// 取 5 百分位，要 ≥ 4.5（字完全顯示的定格；出退場另由 G2／G3 管）。代理指標，不宣稱符合 WCAG。歌詞為編造句
@MainActor
@Suite("LyricsFX contrast")
struct LyricsFXContrastTests {
    static let canvas = CGSize(width: 640, height: 400)
    static let minimum = 4.5
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 1, end: 9, text: "lanterns over the quiet water", isChorus: false),
    ], source: .embeddedLRC, duration: 20)
    /// ⑤ 中日韓字型計劃 §4.5：日文行（冬青黑體 W6，含全形標點與英文混排）
    static let japanese = LyricsTimeline(lines: [
        TimedLine(start: 1, end: 9, text: "「灯籠」が静かに流れる。lanterns", isChorus: false),
    ], source: .embeddedLRC, duration: 20)
    /// 停穩的時刻（fadeUp 進場最長 0.6 s）
    static let settled = 5.0

    enum Layers { case all, backgroundOnly, mainTextAlone, nothing }

    private static func render(_ recipe: ComposedRecipe, layers: Layers, at time: Double = settled, lyrics: LyricsTimeline = timeline) -> CGImage? {
        let measurer = CoreTextMeasurer()
        let paths = GlyphPathCache()
        let view = Canvas { context, size in
            var plan = LyricsFXFrame.plan(timeline: lyrics, time: time, size: size, motion: .full, recipe: .composed(recipe), measurer: measurer)
            if layers != .all { plan.ghosts = []; plan.boxes = [] }
            if layers == .mainTextAlone || layers == .nothing { plan.back = []; plan.underText = []; plan.front = []; plan.glow = 0 }
            // 只取完全顯示的主字（定格時句尾仍可能有字在淡入，那是 G2 的範圍）
            if layers == .mainTextAlone {
                plan.glyphs = plan.glyphs.filter { $0.opacity >= 1 }.map { var plain = $0; plain.stroke = 0; return plain }
                plan.unlit = []
            }
            if layers == .backgroundOnly || layers == .nothing { plan.glyphs = []; plan.unlit = [] }
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
    /// 「有字」的每通道差門檻（0–255）
    static let inkDifference = 48

    private static func luminance(_ p: [UInt8], _ i: Int) -> Double {
        RGB(red: Double(p[i]) / 255, green: Double(p[i + 1]) / 255, blue: Double(p[i + 2]) / 255).relativeLuminance
    }

    /// 主字字形內部：主字單獨畫與什麼都沒有的差異，八鄰都在字形裡才算（內縮 1 像素）。
    /// 判定式的可讀版本，只供等價測試對照；改判定時 `fastCore` 與它要一起改（docs/plans/2026-11-01-g1-contrast-timeout.md §5）
    static func referenceCore(text: [UInt8], empty: [UInt8], width: Int, height: Int) -> [Int] {
        let inside = stride(from: 0, to: text.count, by: 4).map { i in (0..<3).contains { abs(Int(text[i + $0]) - Int(empty[i + $0])) > inkDifference } }
        return (1..<max(1, height - 1)).flatMap { y in
            (1..<max(1, width - 1)).filter { x in
                (-1...1).allSatisfy { dy in (-1...1).allSatisfy { dx in inside[(y + dy) * width + x + dx] } }
            }.map { x in (y * width + x) * 4 }
        }
    }

    /// 與 `referenceCore` 同一判定、逐位相同的索引迴圈版。測試 target 是 Debug（-Onone），
    /// 閉包串接的逐像素寫法每次約 210 ms、這版約 10 ms——G1 4 條原本每條約 230 s、超過 120 s 上限（G1 計劃 §2 F4–F5）
    static func fastCore(text: [UInt8], empty: [UInt8], width: Int, height: Int) -> [Int] {
        let count = width * height
        guard width >= 3, height >= 3, text.count >= count * 4, empty.count >= count * 4 else { return [] }
        var inside = [Bool](repeating: false, count: count)
        inside.withUnsafeMutableBufferPointer { mask in
            text.withUnsafeBufferPointer { text in
                empty.withUnsafeBufferPointer { empty in
                    for pixel in 0..<count {
                        let i = pixel * 4
                        mask[pixel] = abs(Int(text[i]) - Int(empty[i])) > inkDifference
                            || abs(Int(text[i + 1]) - Int(empty[i + 1])) > inkDifference
                            || abs(Int(text[i + 2]) - Int(empty[i + 2])) > inkDifference
                    }
                }
            }
        }
        var result: [Int] = []
        inside.withUnsafeBufferPointer { mask in
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let c = y * width + x
                    if mask[c - width - 1], mask[c - width], mask[c - width + 1], mask[c - 1], mask[c], mask[c + 1],
                       mask[c + width - 1], mask[c + width], mask[c + width + 1] {
                        result.append(c * 4)
                    }
                }
            }
        }
        return result
    }

    static func contrast(_ recipe: ComposedRecipe, at time: Double = settled, lyrics: LyricsTimeline = timeline) -> (ratio: Double, pixels: Int)? {
        guard let full = render(recipe, layers: .all, at: time, lyrics: lyrics), let background = render(recipe, layers: .backgroundOnly, at: time, lyrics: lyrics),
              let alone = render(recipe, layers: .mainTextAlone, at: time, lyrics: lyrics), let nothing = render(recipe, layers: .nothing, at: time, lyrics: lyrics)
        else { return nil }
        let a = rgba(full), b = rgba(background)
        var ratios = fastCore(text: rgba(alone), empty: rgba(nothing), width: full.width, height: full.height).map { i in
            let l1 = luminance(a, i), l2 = luminance(b, i)
            return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
        guard !ratios.isEmpty else { return nil }
        ratios.sort()
        return (ratios[Int(Double(ratios.count - 1) * percentile)], ratios.count)
    }

    static func recipe(backdrop: String, palette: String, fx: String = "none") -> ComposedRecipe {
        ComposedRecipe(font: "Bebas", backdrop: backdrop, enter: "fadeUp", exit: "up", fx1: fx, fx2: "none", palette: palette, seed: 5,
                       profile: SongProfile(axes: [.aggression: 0.3], tags: [.britpop]))
    }


    /// 實際會被同一個 profile（樂團表＋曲風列）一起抽到的（背景, 配色）：兩者對該 profile fit > 0，且亮暗相容
    static let reachablePairs: [(backdrop: String, palette: String)] = {
        var pairs = Set<String>()
        for band in ReadabilityAudit.profiles {
            let fits = { (slot: FXSlot) in LyricsFXCatalog.components(in: slot).filter { Composer.fit($0, band.profile) > 0 } }
            let palettes = fits(.palette)
            for backdrop in fits(.backdrop) {
                guard case .backdrop(let kind) = backdrop.payload else { continue }
                for palette in palettes {
                    guard case .palette(let colors) = palette.payload else { continue }
                    if let tone = kind.tone, !tone.accepts(colors) { continue }
                    // ⑧：G1 不及格而硬禁止的配對畫面上不會出現（`everyBannedPairReallyFailsTheMinimum` 另外釘住它們確實不及格）
                    if ReadabilityPolicy.isUnreadable(backdrop: backdrop.id, palette: palette.id) { continue }
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
    static func readabilityFailure(
        backdrop: String, palette: String, fx: String = "none", who: [String] = [], at time: Double = settled, lyrics: LyricsTimeline = timeline
    ) -> String? {
        let label = "\(palette)＋\(backdrop)" + (fx == "none" ? "" : "＋\(fx)") + (who.isEmpty ? "" : "（\(who.joined(separator: "、"))）") + (time == settled ? "" : "@\(time)")
        guard let result = contrast(recipe(backdrop: backdrop, palette: palette, fx: fx), at: time, lyrics: lyrics) else { return "\(label)：量不到字" }
        return result.ratio < minimum ? "\(label)：\(String(format: "%.2f", result.ratio))" : nil
    }

    // MARK: 加速的等價證明（G1 計劃 §5）

    /// 分層具名選樣：`reachablePairs` 依背景 tone 分亮／暗／無三層，各層依 id 排序取 4 組，背景與配色先都不重複、
    /// 該層背景用完才允許重複背景（亮層只有 halftone、sunset）。2026-11-02 選定後寫死，元件增加不改選樣
    static let equivalencePairs: [(backdrop: String, palette: String)] = [
        ("halftone", "britRed"), ("sunset", "chalk"), ("halftone", "cream60"), ("halftone", "mancSky"),
        ("ampGlow", "acid"), ("bluehour", "bruise"), ("bokeh", "dusk"), ("genAmbBluehour", "genAmbDeep"),
        ("ash", "ampRed"), ("checker", "gigRed"), ("crimsonFog", "ashGrey"), ("embers", "bloodBlack"),
    ]
    static let equivalenceEffects = ["none", "glow", "neonstroke", "rgbsplit", "misreg", "reflect"]

    /// 12 組配對 × 英日兩行，效果依序輪流（24 個輸入，6 種效果各 4 次）：新舊兩版核心像素逐位相同
    @Test func fastCoreMatchesTheReferenceOnRenderedLines() {
        var index = 0
        for pair in Self.equivalencePairs {
            for lyrics in [Self.timeline, Self.japanese] {
                let fx = Self.equivalenceEffects[index % Self.equivalenceEffects.count]
                index += 1
                let recipe = Self.recipe(backdrop: pair.backdrop, palette: pair.palette, fx: fx)
                guard let alone = Self.render(recipe, layers: .mainTextAlone, lyrics: lyrics),
                      let nothing = Self.render(recipe, layers: .nothing, lyrics: lyrics)
                else {
                    Issue.record("\(pair.palette)＋\(pair.backdrop)＋\(fx)：畫不出來")
                    continue
                }
                let text = Self.rgba(alone), empty = Self.rgba(nothing)
                let fast = Self.fastCore(text: text, empty: empty, width: alone.width, height: alone.height)
                let reference = Self.referenceCore(text: text, empty: empty, width: alone.width, height: alone.height)
                #expect(!reference.isEmpty, "\(pair.palette)＋\(pair.backdrop)＋\(fx)：量不到字")
                #expect(fast == reference, "\(pair.palette)＋\(pair.backdrop)＋\(fx)")
            }
        }
        #expect(index == 24)
    }

    /// 合成遮罩（不渲染）：寬高邊界、3×3 內縮、通道差恰為門檻與門檻加一。預期索引寫死，新舊兩版都要等於它
    @Test func fastAndReferenceCoreAgreeOnSyntheticMasks() {
        struct Case {
            let name: String
            let width: Int
            let height: Int
            /// 每個像素（列優先）的通道差；其餘通道相同
            let difference: (_ x: Int, _ y: Int) -> UInt8
            let expected: [Int]
            /// 有差的通道（0 紅、1 綠、2 藍）：三個通道任一超過門檻都算字形
            var channel = 1
        }
        let cases = [
            Case(name: "全空 5×5", width: 5, height: 5, difference: { _, _ in 0 }, expected: []),
            Case(name: "全滿 5×5", width: 5, height: 5, difference: { _, _ in 255 },
                 expected: (1...3).flatMap { y in (1...3).map { x in (y * 5 + x) * 4 } }),
            Case(name: "1 像素寬直線", width: 5, height: 5, difference: { x, _ in x == 2 ? 255 : 0 }, expected: []),
            Case(name: "3×3 實心", width: 3, height: 3, difference: { _, _ in 255 }, expected: [16]),
            Case(name: "寬 2", width: 2, height: 5, difference: { _, _ in 255 }, expected: []),
            Case(name: "高 2", width: 5, height: 2, difference: { _, _ in 255 }, expected: []),
            Case(name: "差恰為 48 不算", width: 3, height: 3, difference: { _, _ in UInt8(Self.inkDifference) }, expected: []),
            Case(name: "差 49 算", width: 3, height: 3, difference: { _, _ in UInt8(Self.inkDifference + 1) }, expected: [16]),
            Case(name: "只有紅色差 49", width: 3, height: 3, difference: { _, _ in UInt8(Self.inkDifference + 1) }, expected: [16], channel: 0),
            Case(name: "只有藍色差 49", width: 3, height: 3, difference: { _, _ in UInt8(Self.inkDifference + 1) }, expected: [16], channel: 2),
        ]
        for item in cases {
            let empty = [UInt8](repeating: 0, count: item.width * item.height * 4)
            var text = empty
            for y in 0..<item.height {
                for x in 0..<item.width { text[(y * item.width + x) * 4 + item.channel] = item.difference(x, y) }
            }
            #expect(Self.fastCore(text: text, empty: empty, width: item.width, height: item.height) == item.expected, "\(item.name)")
            #expect(Self.referenceCore(text: text, empty: empty, width: item.width, height: item.height) == item.expected, "\(item.name)")
        }
    }

    @Test func mainTextStaysReadableOnEveryReachableBackdrop() {
        let failures = Self.reachablePairs.compactMap { Self.readabilityFailure(backdrop: $0.backdrop, palette: $0.palette) }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    /// ⑤ 中日韓字型計劃 §4.5：日文行（冬青黑體）在每組抽得到的（背景, 配色）上
    @Test func japaneseMainTextStaysReadableOnEveryReachableBackdrop() {
        let failures = Self.reachablePairs.compactMap { Self.readabilityFailure(backdrop: $0.backdrop, palette: $0.palette, lyrics: Self.japanese) }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    @Test(arguments: ["glow", "neonstroke", "rgbsplit", "misreg", "reflect"])
    func japaneseMainTextStaysReadableWithEffectsThatTouchTheText(fx: String) {
        let failures = Self.reachablePairs.compactMap { Self.readabilityFailure(backdrop: $0.backdrop, palette: $0.palette, fx: fx, lyrics: Self.japanese) }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    /// 會改變字本身顏色或邊緣的效果：每組抽得到的（背景, 配色）——含只有回退路徑才抽得到的——各加一個量一次
    @Test(arguments: ["glow", "neonstroke", "rgbsplit", "misreg", "reflect"])
    func mainTextStaysReadableWithEffectsThatTouchTheText(fx: String) {
        let measured = Set(Self.reachablePairs.map { "\($0.backdrop)|\($0.palette)" })
        let fallbacks = Self.playablePairs.keys.filter { !measured.contains($0) }.sorted().map { pair in
            let parts = pair.split(separator: "|").map(String.init)
            return (backdrop: parts[0], palette: parts[1])
        }
        let failures = (Self.reachablePairs + fallbacks).compactMap { Self.readabilityFailure(backdrop: $0.backdrop, palette: $0.palette, fx: fx) }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }

    /// 各團實際抽得到的（背景, 配色）——含 `compatiblePalettes` 找不到相容配色而回退時抽到的不相容組合，
    /// 那些不在 `reachablePairs` 裡（B2 批 2 計劃 V5）。值＝抽得到這一組的團（或曲風列）
    static let playablePairs: [String: [String]] = ReadabilityAudit.profiles.reduce(into: [:]) { pairs, band in
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

    /// ⑧ 計劃 §4.6：被禁的配對要真的不及格（日後元件改色讓它讀得到了，這條會紅、提醒解禁）。英文或日文行任一不及格即算
    @Test func everyBannedPairReallyFailsTheMinimum() {
        for pair in ReadabilityPolicy.unreadablePairs {
            let english = Self.readabilityFailure(backdrop: pair.backdrop, palette: pair.palette)
            let japanese = Self.readabilityFailure(backdrop: pair.backdrop, palette: pair.palette, lyrics: Self.japanese)
            #expect(english != nil || japanese != nil, "\(pair.palette)＋\(pair.backdrop) 已讀得到")
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

    /// 顆粒、刮痕與閃爍每格都不同：字下強暈影的兩個背景，抽得到的每個配色在三個不同顆粒格（film 第 90／95／100 格）各量一次。
    /// 其他背景的顆粒很淡（0.05–0.16），只量 settled 一格
    static let grainFrames = [settled, 5.3, 5.6]

    @Test(arguments: ["film", "crimsonFog"])
    func strongVignetteBackdropsStayReadableOnEveryGrainFrame(backdrop: String) {
        let palettes = Set(Self.reachablePairs.filter { $0.backdrop == backdrop }.map(\.palette)
            + Self.playablePairs.keys.compactMap { pair in pair.hasPrefix("\(backdrop)|") ? String(pair.dropFirst(backdrop.count + 1)) : nil })
        #expect(!palettes.isEmpty)
        let failures = palettes.sorted().flatMap { palette in Self.grainFrames.compactMap { Self.readabilityFailure(backdrop: backdrop, palette: palette, at: $0) } }
        #expect(failures.isEmpty, "\(failures.joined(separator: "；"))")
    }
}
