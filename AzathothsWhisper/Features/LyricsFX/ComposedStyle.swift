import CoreGraphics
import Foundation
import os

/// 組合配方解析成的繪製參數（移植原型 `styleFromRecipe`，html:997-1003）
struct ResolvedStyle: Sendable {
    let face: FontFace
    let palette: FXPalette
    let backdrop: BackdropKind
    let enter: EnterSpec
    let exit: ExitSpec
    let effects: Set<FXEffect>
    let personality: PersonalityStyle
    let seed: UInt64

    init?(_ recipe: ComposedRecipe) {
        guard case .font(let face)? = LyricsFXCatalog.component(recipe.font)?.payload,
              case .backdrop(let backdrop)? = LyricsFXCatalog.component(recipe.backdrop)?.payload,
              case .enter(let enter)? = LyricsFXCatalog.component(recipe.enter)?.payload,
              case .exit(let exit)? = LyricsFXCatalog.component(recipe.exit)?.payload,
              let palette = LyricsFXCatalog.palette(recipe.palette) else { return nil }
        let effects: [FXEffect] = [recipe.fx1, recipe.fx2].compactMap {
            if case .fx(let effect)? = LyricsFXCatalog.component($0)?.payload { effect } else { nil }
        }
        let aggression = recipe.profile.axes[.aggression] ?? 0
        let elegance = recipe.profile.axes[.elegance] ?? 0
        // 停留的優先序照原型：bob → wobble → flicker → jitter → tilt → breathe → 依侵略度
        let hold: [(HoldTemplate, Double)] =
            if effects.contains(.bob) { [(.bob, 3), (.still, 2)] }
            else if effects.contains(.wobble) { [(.wobble, 2), (.still, 3)] }
            else if effects.contains(.flicker) { [(.flicker, 3), (.still, 2)] }
            else if effects.contains(.jitter) { [(.jitter, 3), (.still, 2)] }
            else if effects.contains(.tilt) { [(.tilt, 1)] }
            else if effects.contains(.breathe) { [(.breathe, 3), (.still, 2)] }
            else { aggression > 0.7 ? [(.still, 5), (.twitch, 1)] : [(.still, 3), (.drift, 1), (.float, 1)] }
        self.face = face
        self.palette = palette
        self.backdrop = backdrop
        self.enter = enter
        self.exit = exit
        self.effects = Set(effects)
        self.seed = recipe.seed
        personality = PersonalityStyle(
            enter: enter.weights, enterDuration: enter.duration, hold: hold, exit: exit.weights,
            vary: .init(size: 0.1 + aggression * 0.1, dy: 0.08 + elegance * 0.1, rotation: 0.03 + aggression * 0.05, scatter: 0.02 + elegance * 0.06),
            wordLevel: enter.wordLevel
        )
    }
}

/// 組合風格的 plan（移植原型 `renderLines`／`visibleLines`／組合模式 paint，html:300-342,1110-1120,1033-1046）。
/// B1 不含：サビ換色、熱詞放大與血漬、glow／neon 類濾鏡（B1 計劃 §3.8、§3.9）
enum ComposedStyle {
    static let emRatio: CGFloat = 0.12
    static let lineHeight: CGFloat = 1.2
    /// 每字右側多留的間距（em 比例）的預設值；字型可覆寫（`FontFace.spacing`）
    static let spacing: CGFloat = 0.08
    static let wordGap: CGFloat = 0.3
    static let maxWidthRatio: CGFloat = 0.86
    /// 折行寬：每列排版寬的上限（批 4 遺留計劃 §2.1 契約 A）
    static func wrapWidth(_ size: CGSize) -> CGFloat { size.width * maxWidthRatio }
    static let baseYRatio: CGFloat = 0.5
    /// 長句縮字（T7 修正計劃 §2.6）：主字形安全區＝歌詞區上下各留 2%；最小縮到 0.5 倍
    static let fitMargin: CGFloat = 0.02
    static let minimumFitRatio: CGFloat = 0.5

    /// 二分搜尋次數：6 次＝在 0.5 倍的範圍內細到原 em 的 0.8%
    static let fitSteps = 6
    /// 停留小動作的上限（`HoldTemplate`；`LongLineFitTests` 掃全部模板把關兩邊一致）：float 的 0.12 em 位移、twitch 的 0.1 rad、breathe 的 1.04 倍、jitter 的 1 點
    static let holdReach: CGFloat = 0.12
    static let holdRotation: CGFloat = 0.1
    static let holdScale: CGFloat = 1.04
    static let holdJitter: CGFloat = 1

    /// 測試用：這一句的縮字結果（em、比例、是否斷詞、各列寬、每個字所屬的詞與列）
    struct FitReport {
        let em: CGFloat
        let ratio: CGFloat
        let breaksLongWords: Bool
        let rowWidths: [CGFloat]
        let glyphs: [(text: String, wordIndex: Int, row: Int)]
        /// 每字的排版寬（含字距）、字本身的寬、字級
        let metrics: [(width: CGFloat, advance: CGFloat, fontSize: CGFloat)]
    }

    static func fitReport(line: TimedLine, index: Int, recipe: ComposedRecipe, size: CGSize, measurer: any TextMeasuring) -> FitReport? {
        guard let style = ResolvedStyle(recipe) else { return nil }
        let (_, personalities) = linePersonalities(line: line, index: index, style: style)
        let fit = fitted(line, personalities: personalities, size: size, style: style, measurer: measurer, index: index)
        return FitReport(
            em: fit.em, ratio: fit.em / baseEm(size: size, style: style), breaksLongWords: fit.breaksLongWords, rowWidths: fit.laid.rowWidths,
            glyphs: fit.laid.glyphs.map { ($0.character, $0.wordIndex, $0.row) },
            metrics: fit.laid.glyphs.map { ($0.width, $0.advance, fit.em * CGFloat(personalities[$0.index].size)) }
        )
    }

    /// 測試用：這一句實際用的 em 相對原 em 的比例（1＝沒縮）
    static func fittedEmRatio(line: TimedLine, index: Int, recipe: ComposedRecipe, size: CGSize, measurer: any TextMeasuring) -> CGFloat {
        fitReport(line: line, index: index, recipe: recipe, size: size, measurer: measurer)?.ratio ?? 1
    }
    /// 殘影（原型組合模式 smoke：5 份、alpha×0.25、散佈 0.14 em，不畫本體）
    static let ghostCopies = 5
    static let ghostAlpha = 0.25
    static let ghostSpread: CGFloat = 0.14
    /// 殘留（fade／dissolve 退場）：trailHold 秒內降到 0.3，再以 trailFade 秒淡掉。
    /// 原型為 0.7／2.4（TONE.speed 0.6 推得），P12 縮短 40%（使用者：「漸入漸出稍長，字發虛」）
    static let trailHold = 0.4
    static let trailFade = 1.4
    static let trailAlpha = 0.3
    /// 每幀粒子上限（G0 定案）；超過先砍字旁的冰屑
    static let maxParticles = 300
    /// thump：詞首 0.12 s 內整屏放大到 1.04（原型）
    static let thumpWindow = 0.12
    static let thumpScale: CGFloat = 0.04
    /// 光暈：原型 shadowBlur 18 × glowAmt(polish 0.4)≈14.8；Canvas 的 blur 約為 SwiftUI shadow 半徑的 2 倍
    static let glowRadius: CGFloat = 7.4
    /// 霓虹描邊寬（em 比例）
    static let strokeRatio: CGFloat = 0.06
    /// 倒影：在字下方 0.95 em、4% 透明度
    static let reflectionOffset: CGFloat = 0.95
    /// 0.16 → 0.08 → 0.04：使用者 2026-10-14 T7「倒影和下一行的正字重疊……讓這個倒影淡一些」（全域，使用者選 A），看過 0.08 後「再淺一些」
    static let reflectionAlpha = 0.04
    /// 詞首後多久內整屏抖
    static let shakeWindow = 0.07
    /// 速度線：行首 0.35 s 內 24 道、由 0.35 淡到 0，每 1/30 s 換一組位置（原型 speedLines）
    static let speedLineWindow = 0.35
    static let speedLineCount = 24
    static let speedLineAlpha = 0.35
    /// 勒索信：四種紙色（各配一種相反的字色）、紙比字寬 10%、高 1.05 em、中心在基線上方 0.325 em、每張再歪 ±0.15 rad（原型 paper）
    static let paperStock: [(paper: ColorSlot, ink: ColorSlot)] = [(.black, .white), (.white, .black), (.paperRed, .white), (.paperYellow, .black)]
    static let paperSize = CGSize(width: 1.1, height: 1.05)
    static let paperLift: CGFloat = 0.325
    static let paperTilt = 0.3
    static let specksPerGlyph = 10

    struct VisibleLine {
        let line: TimedLine
        let index: Int
        /// 退場進度 0…1；0＝還在唱或在殘留
        let exit: Double
        /// 殘留透明度；nil＝不是殘留
        let trail: Double?
    }

    static func visibleLines(_ lines: [TimedLine], time: Double, exit: ExitSpec) -> [VisibleLine] {
        lines.enumerated().compactMap { index, line in
            // 先比時間（便宜）再判空白：每幀不必逐字掃整首歌
            guard time >= line.start else { return nil }
            let entry: VisibleLine?
            if time < line.end {
                entry = VisibleLine(line: line, index: index, exit: 0, trail: nil)
            } else if exit.trail {
                let since = time - line.end
                let dimmed = 1 + (trailAlpha - 1) * FXEasing.clamp01(since / trailHold)
                entry = since < trailHold + trailFade
                    ? VisibleLine(line: line, index: index, exit: 0, trail: dimmed * (1 - FXEasing.clamp01((since - trailHold) / trailFade)))
                    : nil
            } else {
                let since = time - line.end
                entry = exit.duration > 0 && since < exit.duration ? VisibleLine(line: line, index: index, exit: since / exit.duration, trail: nil) : nil
            }
            guard let entry, !line.text.allSatisfy(\.isWhitespace) else { return nil }
            return entry
        }
    }

    static func plan(timeline: LyricsTimeline, time: Double, size: CGSize, style: ResolvedStyle, measurer: any TextMeasuring) -> FramePlan {
        var frame = FramePlan(palette: style.palette)
        frame.back = ComposedBackdrop.back(style.backdrop, palette: style.palette, size: size, time: time)
        frame.front = ComposedBackdrop.front(style.backdrop, size: size, time: time)
        let visible = visibleLines(timeline.lines, time: time, exit: style.exit)
        var specks: [(Particle, Double)] = []
        for entry in visible {
            draw(entry, time: time, size: size, style: style, measurer: measurer, into: &frame, specks: &specks)
        }
        // 先減粒子不減字：冰屑只用剩下的預算
        frame.back += ComposedBackdrop.particleLayers(specks.prefix(max(maxParticles - particleCount(frame.back), 0)), color: style.palette.fg)
        let current = visible.first(where: { $0.exit == 0 && $0.trail == nil })
        if style.effects.contains(.shake), let current {
            frame.shake = shake(current.line, time: time)
        }
        if style.effects.contains(.thump), let current {
            frame.zoom = 1 + thumpScale * CGFloat(wordHit(current.line, time: time, window: thumpWindow))
        }
        if style.effects.contains(.speedlines), let current, time - current.line.start < speedLineWindow {
            frame.back.append(speedLines(size: size, time: time, color: style.palette.fg, fade: 1 - (time - current.line.start) / speedLineWindow))
        }
        if style.effects.contains(.glow) || style.effects.contains(.neonstroke) { frame.glow = glowRadius }
        return frame
    }

    // MARK: 逐行

    private struct LaidGlyph {
        let character: String
        let wordIndex: Int
        let index: Int
        /// 列內 x（左緣）與寬（含 spacing）
        let x: CGFloat
        let width: CGFloat
        /// 字本身的寬（不含 spacing）：畫字時以它置中，字距只在排版這一處讀
        let advance: CGFloat
        let row: Int
    }

    /// 一行排好的版面：字、各列寬、各詞的（起點 x, 寬）——彈片堆用，免得每字重掃整行
    private struct LineLayout {
        let glyphs: [LaidGlyph]
        let rowWidths: [CGFloat]
        let words: [(x: CGFloat, width: CGFloat)]
        /// 有沒有把超寬的詞斷到多列
        let brokeWords: Bool
    }

    private static func draw(
        _ entry: VisibleLine, time: Double, size: CGSize, style: ResolvedStyle, measurer: any TextMeasuring,
        into frame: inout FramePlan, specks: inout [(Particle, Double)]
    ) {
        let (lineSeed, personalities) = linePersonalities(line: entry.line, index: entry.index, style: style)
        let fit = fitted(entry.line, personalities: personalities, size: size, style: style, measurer: measurer, index: entry.index)
        let (em, laid) = (fit.em, fit.laid)
        // 霓虹描邊寬跟著這一句實際的 em（含字型字級與縮字；原型 `st.em × 0.06`）。原型另隨逐字縮放，app 在畫布座標描邊、不隨（既有差異）
        let stroke = style.effects.contains(.neonstroke) ? em * strokeRatio : 0
        let rowHeight = em * lineHeight
        let baseY = size.height * baseYRatio - CGFloat(laid.rowWidths.count) * rowHeight / 2 + rowHeight * 0.8
        let misregistered = style.effects.contains(.misreg)
        let reflected = style.effects.contains(.reflect)
        let papered = style.effects.contains(.ransom)
        let split = style.effects.contains(.rgbsplit)
        let weeping = style.effects.contains(.weep)
        var weeps: [GlyphDraw] = []
        let firstGhost = frame.ghosts.count
        for glyph in laid.glyphs {
            let personality = personalities[glyph.index]
            guard let transform = glyphTransform(glyph, personality: personality, entry: entry, time: time, size: size, em: em, style: style, rowWidth: laid.rowWidths[glyph.row]) else { continue }
            let (anchor, baseRotation) = style.enter.pile
                ? (pileAnchor(glyph, word: laid.words[glyph.wordIndex], personality: personality, size: size), CGFloat(personality.wordRotation))
                : (CGPoint(x: (size.width - laid.rowWidths[glyph.row]) / 2 + glyph.x + glyph.width / 2, y: baseY + rowHeight * CGFloat(glyph.row)), 0)
            let fontSize = em * CGFloat(personality.size)
            let center = CGPoint(
                x: anchor.x + transform.dx + CGFloat(personality.scatterX) * em,
                y: anchor.y + CGFloat(personality.dy) * em + transform.dy + CGFloat(personality.scatterY) * em
            )
            let alpha = FXEasing.clamp01(transform.alpha * (entry.trail ?? 1))
            let advance = glyph.advance
            let base = GlyphDraw(
                text: glyph.character, face: style.face, fontSize: fontSize,
                origin: CGPoint(x: center.x - advance / 2, y: center.y - measurer.ascent(face: style.face, fontSize: fontSize)),
                rotation: CGFloat(personality.rotation) + baseRotation + transform.rotation,
                scaleX: transform.scale * transform.scaleX, scaleY: transform.scale * transform.scaleY, opacity: alpha, color: .fg, stroke: stroke
            )
            let glyphSeed = lineSeed &+ UInt64(glyph.index) &* 7919
            var random = SplitMix64(seed: glyphSeed)
            if transform.specks > 0 {
                specks += speckParticles(around: center, em: fontSize, strength: transform.specks, alpha: alpha, random: &random)
            }
            emit(
                base, glyphWidth: glyph.width, center: center, transform: transform, misregistered: misregistered, reflected: reflected,
                paper: papered ? paperScrap(seed: glyphSeed, width: advance) : nil,
                split: split ? splitOffset(enterProgress: enterProgress(personality, time: time)) : 0,
                weep: weeping ? weepAmount(age: time - personality.start) : 0, weeps: &weeps, random: &random, into: &frame
            )
        }
        if split { groupSplitCopies(from: firstGhost, in: &frame) }
        frame.ghosts += groupedByOpacityLevel(weeps)
    }

    /// 繪製端相鄰同色、同量化透明度才合成一次填色。暈開的副本同色但每字透明度可能不同（燭火閃爍讓每個字各自明滅），
    /// 照量化階排在一起，一行最多填「階數」次（副本很淡又只稍微重疊，重排後畫面差異可忽略）
    static func groupedByOpacityLevel(_ copies: [GlyphDraw]) -> [GlyphDraw] {
        let levels = Dictionary(grouping: copies) { LyricsFXCanvas.opacityLevel($0.opacity) }
        return levels.keys.sorted(by: >).flatMap { levels[$0] ?? [] }
    }

    /// 往下暈開（原型 weep）：字出現 0.25 秒後開始，再 1.6 秒拉到最開；兩份副本各往下 0.06 字級、越下面越淡
    /// 3 份／0.1 → 2 份／0.06：使用者 2026-10-14 T7「層數減少一些，不要暈開那麼大」
    static let weepCopies = 2
    static let weepStep: CGFloat = 0.06
    static let weepAlpha = 0.18
    static let weepDelay = 0.25
    static let weepSpan = 1.6

    static func weepAmount(age: Double) -> Double {
        FXEasing.clamp01((age - weepDelay) / weepSpan)
    }

    /// 第 `level` 份副本相對本體的透明度：越下面越淡（2 份時 0.12、0.06）
    static func weepOpacity(level: Int) -> Double {
        weepAlpha * (1 - Double(level) / Double(weepCopies + 1))
    }

    /// 紅、藍副本逐字交錯時，繪製端相鄰同色才合成一次填色，會退化成每份副本各填一次；
    /// 本行的副本改成「其他殘影 → 全部紅 → 全部藍」（副本只稍微重疊，畫面差異可忽略）
    private static func groupSplitCopies(from start: Int, in frame: inout FramePlan) {
        let line = frame.ghosts[start...]
        frame.ghosts.replaceSubrange(start..., with: line.filter { $0.color != .splitRed && $0.color != .splitBlue }
            + line.filter { $0.color == .splitRed } + line.filter { $0.color == .splitBlue })
    }

    /// 進場（進度 0…1）＋落定後的停留＋退場三段合成；還沒出場或已過壽命（彈片硬切）＝nil
    private static func glyphTransform(
        _ glyph: LaidGlyph, personality: GlyphPersonality, entry: VisibleLine, time: Double, size: CGSize, em: CGFloat,
        style: ResolvedStyle, rowWidth: CGFloat
    ) -> GlyphTransform? {
        let progress = enterProgress(personality, time: time)
        guard progress > 0 else { return nil }
        if style.enter.expires, time > personality.start + personality.lifetime { return nil }
        let context = GlyphContext(
            em: em, width: size.width, height: size.height, radius: max(size.width, size.height) * 0.55, dir: personality.dir,
            side: glyph.x + glyph.width / 2 < rowWidth / 2 ? -1 : 1, phase: personality.phase, angle: personality.angle, bend: personality.bend
        )
        var transform = personality.enter.transform(progress: progress, context: context)
        if progress >= 1 { transform = transform.combined(with: personality.hold.transform(time: time, context: context)) }
        if entry.exit > 0 { transform = transform.combined(with: personality.exit.transform(progress: entry.exit, context: context)) }
        return transform
    }

    static func enterProgress(_ personality: GlyphPersonality, time: Double) -> Double {
        FXEasing.clamp01((time - personality.start) / max(personality.duration, 1e-6))
    }

    /// RGB 分離：進場前半段左右各偏 6 點、到一半時合攏（原型 rgbsplit，`6*(1-p*2)`）；之後不畫
    static let splitReach: CGFloat = 6
    static let splitOpacity = 0.9

    static func splitOffset(enterProgress p: Double) -> CGFloat {
        p < 0.5 ? splitReach * CGFloat(1 - p * 2) : 0
    }

    /// 依效果把一個字放進繪製指令：殘影（只畫副本、不畫本體）、負片（色塊＋底色字）、影印錯位（黑影＋白光＋本體）或本體
    private static func emit(
        _ base: GlyphDraw, glyphWidth: CGFloat, center: CGPoint, transform: GlyphTransform, misregistered: Bool, reflected: Bool,
        paper: PaperScrap?, split: CGFloat, weep: Double, weeps: inout [GlyphDraw], random: inout SplitMix64, into frame: inout FramePlan
    ) {
        let alpha = base.opacity
        if transform.ghost > 0 {
            let spread = CGFloat(transform.ghost) * base.fontSize * ghostSpread
            for _ in 0..<ghostCopies {
                let dx = CGFloat(random.unit() - 0.5) * spread * 2
                let dy = CGFloat(random.unit() - 0.5) * spread * 2
                frame.ghosts.append(base.shifted(dx: dx, dy: dy, opacity: alpha * ghostAlpha, color: .fg))
            }
        } else if transform.negative {
            let offset = CGPoint(x: sin(base.rotation) * 0.35 * base.fontSize, y: -cos(base.rotation) * 0.35 * base.fontSize)
            frame.boxes.append(GlyphBox(
                center: CGPoint(x: center.x + offset.x, y: center.y + offset.y),
                size: CGSize(width: glyphWidth + 0.16 * base.fontSize, height: 1.2 * base.fontSize), rotation: base.rotation, color: .fg, opacity: alpha
            ))
            frame.glyphs.append(base.shifted(dx: 0, dy: 0, opacity: alpha, color: .bg, stroke: base.stroke))
        } else if let paper {
            // 勒索信：紙片墊在字後，字用與紙相反的黑或白；不再疊錯位與倒影（原型 ransom 提前 return）
            frame.boxes.append(GlyphBox(
                center: CGPoint(x: center.x + sin(base.rotation) * paperLift * base.fontSize, y: center.y - cos(base.rotation) * paperLift * base.fontSize),
                size: CGSize(width: paper.width * paperSize.width, height: base.fontSize * paperSize.height),
                rotation: base.rotation + paper.tilt, color: paper.color, opacity: alpha
            ))
            frame.glyphs.append(base.shifted(dx: 0, dy: 0, opacity: alpha, color: paper.ink, stroke: base.stroke))
        } else {
            if misregistered {
                frame.ghosts.append(base.shifted(dx: 2.5, dy: 2.5, opacity: alpha * 0.6, color: .black))
                frame.ghosts.append(base.shifted(dx: -1, dy: -1, opacity: alpha * 0.08, color: .white))
            }
            if reflected {
                var mirror = base.shifted(dx: 0, dy: base.fontSize * reflectionOffset, opacity: alpha * reflectionAlpha, color: .fg)
                mirror.scaleY = -base.scaleY
                frame.ghosts.append(mirror)
            }
            // 原型以 lighter 疊在字上；這裡畫成字下方的兩份半透明副本（沒有加亮混色）
            if split > 0 {
                frame.ghosts.append(base.shifted(dx: -split, dy: 0, opacity: alpha * splitOpacity, color: .splitRed))
                frame.ghosts.append(base.shifted(dx: split, dy: 0, opacity: alpha * splitOpacity, color: .splitBlue))
            }
            if weep > 0 {
                for level in 1...weepCopies {
                    weeps.append(base.shifted(dx: 0, dy: base.fontSize * weepStep * CGFloat(level) * CGFloat(weep), opacity: alpha * weepOpacity(level: level), color: .fg))
                }
            }
            frame.glyphs.append(base)
        }
    }

    /// 以詞為單位貪婪折行（原型 `layout`）：字寬依個性字級量、每字加該字型的 spacing、詞間 0.3 em。
    /// `breakLongWords`：比折行寬還寬的詞按字（Swift `Character`＝extended grapheme cluster）斷到多列，仍是同一個詞（同 wordIndex、同時間）——只在縮到下限仍放不下時用
    private static func layout(
        _ line: TimedLine, personalities: [GlyphPersonality], em: CGFloat, maxWidth: CGFloat, face: FontFace, measurer: any TextMeasuring,
        breakLongWords: Bool = false
    ) -> LineLayout {
        var glyphs: [LaidGlyph] = []
        var rowWidths: [CGFloat] = [0]
        var words: [(x: CGFloat, width: CGFloat)] = []
        let spacing = face.spacing
        var brokeWords = false
        var index = 0
        for (wordIndex, word) in line.words.enumerated() {
            let characters = word.text.filter { !$0.isWhitespace }.enumerated().map { offset, character in
                display(character, isLineStart: wordIndex == 0 && offset == 0, face: face)
            }
            let widths = characters.enumerated().map { offset, character in
                (measurer.advances(of: character, face: face, fontSize: em * CGFloat(personalities[index + offset].size)).last ?? 0) + spacing * em
            }
            let wordWidth = widths.reduce(0, +)
            var row = rowWidths.count - 1
            if rowWidths[row] > 0, rowWidths[row] + wordGap * em + wordWidth > maxWidth {
                rowWidths.append(0)
                row += 1
            }
            if rowWidths[row] > 0 { rowWidths[row] += wordGap * em }
            words.append((rowWidths[row], wordWidth))
            let breaks = breakLongWords && wordWidth > maxWidth
            brokeWords = brokeWords || breaks
            for (character, width) in zip(characters, widths) {
                if breaks, rowWidths[row] > 0, rowWidths[row] + width > maxWidth {
                    rowWidths.append(0)
                    row += 1
                }
                glyphs.append(LaidGlyph(character: character, wordIndex: wordIndex, index: index, x: rowWidths[row], width: width, advance: width - spacing * em, row: row))
                rowWidths[row] += width
                index += 1
            }
        }
        return LineLayout(glyphs: glyphs, rowWidths: rowWidths, words: words, brokeWords: brokeWords)
    }

    private static func linePersonalities(line: TimedLine, index: Int, style: ResolvedStyle) -> (seed: UInt64, [GlyphPersonality]) {
        var indexMixer = SplitMix64(seed: UInt64(index))
        let lineSeed = FXHash.fnv1a64(line.text) ^ style.seed ^ indexMixer.next()
        return (lineSeed, LinePersonalities.make(line: line, seed: lineSeed, style: style.personality))
    }

    // MARK: 長句縮字（T7 修正計劃 §2.6；原型沒有，ACCEPTANCE I-45 ⚠️）

    /// 先照原 em 排；主字形放不下才在 [0.5, 1] 倍之間二分搜尋「放得下的最大 em」。彈片堆的詞錨點不隨 em 走，縮了也救不了 → 不縮
    /// 測試用：快取裡這一句的比例（nil＝沒算過或沒縮）
    static func cachedFitRatio(line: TimedLine, index: Int, recipe: ComposedRecipe, size: CGSize, measurer: any TextMeasuring) -> CGFloat? {
        guard let style = ResolvedStyle(recipe) else { return nil }
        let (_, personalities) = linePersonalities(line: line, index: index, style: style)
        return FitCache.ratio(for: FitCache.Key(line: line, personalities: personalities, size: size, style: style, measurer: measurer))
    }

    private static func baseEm(size: CGSize, style: ResolvedStyle) -> CGFloat {
        size.height * emRatio * style.face.sizeScale
    }

    /// 一句的縮字結果：用的 em、排好的版面（有沒有斷開超寬的詞由版面本身記錄）
    private struct Fitted {
        let em: CGFloat
        let laid: LineLayout
        var breaksLongWords: Bool { laid.brokeWords }
    }

    private static func fitted(
        _ line: TimedLine, personalities: [GlyphPersonality], size: CGSize, style: ResolvedStyle, measurer: any TextMeasuring, index: Int
    ) -> Fitted {
        let baseEm = baseEm(size: size, style: style)
        let lay = { (em: CGFloat, breaks: Bool) in
            layout(line, personalities: personalities, em: em, maxWidth: wrapWidth(size), face: style.face, measurer: measurer, breakLongWords: breaks)
        }
        if style.enter.pile { return Fitted(em: baseEm, laid: lay(baseEm, false)) }
        let key = FitCache.Key(line: line, personalities: personalities, size: size, style: style, measurer: measurer)
        if let ratio = FitCache.ratio(for: key) {
            // 只在下限才可能斷詞（`search`）；沒有超寬詞時斷詞排版與不斷完全相同，斷沒斷由排版結果記錄
            let em = baseEm * ratio
            return Fitted(em: em, laid: lay(em, ratio <= minimumFitRatio))
        }
        let full = lay(baseEm, false)
        if fits(full, em: baseEm, size: size, style: style, measurer: measurer) { return Fitted(em: baseEm, laid: full) }
        let fit = search(lay, baseEm: baseEm, size: size, style: style, measurer: measurer, line: line, index: index)
        FitCache.store(ratio: fit.em / baseEm, for: key)
        return fit
    }

    /// 回傳的 em 一律是實際跑過 `fits` 且通過的候選（或下限）：字寬對 em 只是近似線性時，最壞是比最大可行值略小，不會放不下
    private static func search(
        _ lay: (CGFloat, Bool) -> LineLayout, baseEm: CGFloat, size: CGSize, style: ResolvedStyle, measurer: any TextMeasuring, line: TimedLine, index: Int
    ) -> Fitted {
        var low = baseEm * minimumFitRatio, high = baseEm
        // 下限照斷詞排：超寬的詞（水平擋住）在這裡斷開；沒有超寬詞時與不斷完全相同
        var best = lay(low, true)
        let fitsAtFloor = fits(best, em: low, size: size, style: style, measurer: measurer)
        guard fitsAtFloor, !best.brokeWords else {
            // 斷了詞就停在下限（em 再大那個詞只會更寬）；下限仍放不下就照畫、記一次
            if !fitsAtFloor {
                FitLog.once(line: line, index: index, size: size, style: style, rows: best.rowWidths.count, breaksLongWords: best.brokeWords)
            }
            return Fitted(em: low, laid: best)
        }
        for _ in 0..<fitSteps {
            let middle = (low + high) / 2
            let candidate = lay(middle, false)
            if fits(candidate, em: middle, size: size, style: style, measurer: measurer) {
                (low, best) = (middle, candidate)
            } else {
                high = middle
            }
        }
        return Fitted(em: low, laid: best)
    }

    /// 水平（批 4 遺留計劃 §2.1 契約 A）：每列排版寬 ≤ 折行寬。多詞列由折行保證，所以只有比折行寬還寬的單一詞會讓它失敗
    private static func rowsFitWidth(_ laid: LineLayout, size: CGSize) -> Bool {
        let maxWidth = wrapWidth(size)
        return laid.rowWidths.allSatisfy { $0 <= maxWidth }
    }

    /// 主字形的保守包絡（只放大不縮小）是否落在上下各留 `fitMargin` 的安全區、且每列不比折行寬還寬；淡裝飾（暈開、倒影、錯位、RGB 分離、紙片）不算
    private static func fits(_ laid: LineLayout, em: CGFloat, size: CGSize, style: ResolvedStyle, measurer: any TextMeasuring) -> Bool {
        let rows = CGFloat(laid.rowWidths.count)
        let rowHeight = em * lineHeight
        let firstBaseline = size.height * baseYRatio - rows * rowHeight / 2 + rowHeight * 0.8
        let lastBaseline = firstBaseline + rowHeight * (rows - 1)
        let vary = style.personality.vary
        let largest = em * CGFloat(1 + vary.size * LinePersonalities.rawness) * holdScale
        // 字寬已含各字的 size 變化；呼吸的放大在旋轉前，一併算進去
        let widest = laid.glyphs.reduce(0) { max($0, $1.width) } * holdScale
        let reach = CGFloat(vary.dy + vary.scatter) * em + holdReach * em + holdJitter
            + widest * 0.5 * sin(CGFloat(vary.rotation) + holdRotation)
        let top = firstBaseline - measurer.ascent(face: style.face, fontSize: largest) - reach
        let bottom = lastBaseline + measurer.descent(face: style.face, fontSize: largest) + reach
        let margin = size.height * fitMargin
        return top >= margin && bottom <= size.height - margin && rowsFitWidth(laid, size: size)
    }

    /// 原型 `displayChar`：大寫字型整行轉大寫；否則只有行首字母大寫
    private static func display(_ character: Character, isLineStart: Bool, face: FontFace) -> String {
        face.uppercase || isLineStart ? String(character).uppercased() : String(character)
    }

    /// 彈片堆：每個詞自己的錨點與傾斜（原型 html:316-318）
    private static func pileAnchor(_ glyph: LaidGlyph, word: (x: CGFloat, width: CGFloat), personality: GlyphPersonality, size: CGSize) -> CGPoint {
        let local = glyph.x - word.x + glyph.width / 2 - word.width / 2
        let anchor = CGPoint(x: size.width * (0.5 + CGFloat(personality.wordX)), y: size.height * (0.5 + CGFloat(personality.wordY)))
        return CGPoint(x: anchor.x + cos(personality.wordRotation) * local, y: anchor.y + sin(personality.wordRotation) * local)
    }

    // MARK: 效果

    /// 冰屑（原型 `specks`，html:351）：字周圍 10 顆
    private static func speckParticles(around center: CGPoint, em: CGFloat, strength: Double, alpha: Double, random: inout SplitMix64) -> [(Particle, Double)] {
        let opacity = alpha < 0.05 ? 0.8 : 0.8 * (1 - alpha)
        let spread = 1.4 * strength
        return (0..<specksPerGlyph).map { _ in
            let distance = spread * (0.4 + random.unit())
            let angle = random.unit() * 2 * .pi
            let x = center.x + CGFloat(cos(angle) * distance) * em
            let y = center.y - 0.35 * em + CGFloat(sin(angle) * distance) * em
            return (Particle(x: x, y: y, size: 1.5), opacity)
        }
    }

    static func particleCount(_ layers: [LayerDraw]) -> Int {
        layers.reduce(0) { count, layer in
            if case .particles(let dots, _, _) = layer { count + dots.count } else { count }
        }
    }

    /// 最近一個詞首的衝擊強度：詞首當下 1，`window` 秒內線性降到 0
    private static func wordHit(_ line: TimedLine, time: Double, window: Double) -> Double {
        line.words.reduce(0.0) { strongest, word in
            let since = time - word.start
            return since >= 0 && since < window ? max(strongest, 1 - since / window) : strongest
        }
    }

    /// 勒索信的一張紙：紙色、額外的歪斜角、字寬
    private struct PaperScrap {
        let color: ColorSlot
        /// 字色：與紙相反的黑或白
        let ink: ColorSlot
        let tilt: CGFloat
        let width: CGFloat
    }

    /// 紙色與歪斜只依這個字的種子，不隨幀變
    private static func paperScrap(seed: UInt64, width: CGFloat) -> PaperScrap {
        var random = SplitMix64(seed: seed ^ 0x7061_7065)
        let stock = paperStock[min(Int(random.unit() * Double(paperStock.count)), paperStock.count - 1)]
        return PaperScrap(color: stock.paper, ink: stock.ink, tilt: CGFloat((random.unit() - 0.5) * paperTilt), width: width)
    }

    /// 行首的速度線：24 道 1 點高的橫線，長度是畫布寬的 10–50%
    private static func speedLines(size: CGSize, time: Double, color: RGB, fade: Double) -> LayerDraw {
        var random = SplitMix64(seed: UInt64(max(time * 30, 0)) &+ 5)
        let lines = (0..<speedLineCount).map { _ in
            let y = CGFloat(random.unit()) * size.height
            let length = size.width * CGFloat(0.1 + random.unit() * 0.4)
            return CGRect(x: CGFloat(random.unit()) * size.width, y: y, width: length, height: 1)
        }
        return .rects(lines, color, opacity: speedLineAlpha * fade)
    }

    /// 詞首 70 ms 內整屏抖（原型 html:1009-1010）；以 1/60 s 為一格取亂數
    private static func shake(_ line: TimedLine, time: Double) -> CGSize {
        let hit = wordHit(line, time: time, window: shakeWindow)
        guard hit > 0 else { return .zero }
        var random = SplitMix64(seed: UInt64(max(time * 60, 0)))
        return CGSize(width: (random.unit() - 0.5) * 12 * hit, height: (random.unit() - 0.5) * 8 * hit)
    }
}

extension GlyphDraw {
    /// 位移、換色、換透明度的副本。描邊預設 0（殘影天生不描）；主字換色時明確傳 `stroke: base.stroke`
    func shifted(dx: CGFloat, dy: CGFloat, opacity: Double, color: ColorSlot, stroke: CGFloat = 0) -> GlyphDraw {
        GlyphDraw(
            text: text, face: face, fontSize: fontSize, origin: CGPoint(x: origin.x + dx, y: origin.y + dy),
            rotation: rotation, scaleX: scaleX, scaleY: scaleY, opacity: opacity, color: color, stroke: stroke
        )
    }
}

/// 縮到下限仍放不下的句子：同一句、同一畫布、同一配方只記一次；只記行號與列數，不記歌詞
private enum FitLog {
    private static let log = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "lyricsFXFit")
    private struct Key: Hashable {
        let text: UInt64
        let index: Int
        let face: String
        let width: Int
        let height: Int
        let seed: UInt64
    }

    /// 拖動視窗會一直產生新尺寸：超過就整個清掉（只影響會不會重記一次）
    private static let capacity = 256
    private static let seen = OSAllocatedUnfairLock(initialState: Set<Key>())

    static func once(line: TimedLine, index: Int, size: CGSize, style: ResolvedStyle, rows: Int, breaksLongWords: Bool) {
        let key = Key(text: FXHash.fnv1a64(line.text), index: index, face: style.face.id, width: Int(size.width), height: Int(size.height), seed: style.seed)
        let isNew = seen.withLock { seen in
            if seen.count >= capacity { seen.removeAll(keepingCapacity: true) }
            return seen.insert(key).inserted
        }
        guard isNew else { return }
        log.info("line \(index, privacy: .public) still overflows at minimum fit ratio: \(rows, privacy: .public) rows, broken words: \(breaksLongWords, privacy: .public)")
    }
}

/// 縮過的句子的比例（T7 第 3 次每幀：每幀重算讓 Courier 由過變超）。放得下的句子不進來，所以一般句只多一次查表。
/// 鍵＝`fits` 與 `layout` 真正讀的東西：歌詞、各字的大小（性格亂數依配方各槽而變，只記種子不夠）、畫布、字型、變異幅度、量測器型別。
/// 不變條件：`TimedLine` 唯一的 init 由 `TimedWord.split(text)` 產生詞界，所以歌詞雜湊就決定了詞界（日後若加外部詞界的 init，鍵要加詞界）；
/// app 的量測器只有 `CoreTextMeasurer` 一種，型別即可區分
private enum FitCache {
    struct Key: Hashable {
        let text: UInt64
        let sizes: [Double]
        let width: CGFloat
        let height: CGFloat
        let face: FontFace
        let vary: [Double]
        let measurer: ObjectIdentifier

        init(line: TimedLine, personalities: [GlyphPersonality], size: CGSize, style: ResolvedStyle, measurer: any TextMeasuring) {
            let vary = style.personality.vary
            text = FXHash.fnv1a64(line.text)
            sizes = personalities.map(\.size)
            width = size.width
            height = size.height
            face = style.face
            self.vary = [vary.size, vary.dy, vary.rotation, vary.scatter]
            self.measurer = ObjectIdentifier(type(of: measurer))
        }
    }

    /// 拖動視窗會一直產生新尺寸：超過就整個清掉（之後重算一次而已）
    private static let capacity = 512
    /// 只存比例：斷不斷詞由比例是否在下限決定，排版時自然重現（遺留收尾計劃 §2.3 ③c）
    private static let entries = OSAllocatedUnfairLock(initialState: [Key: CGFloat]())

    static func ratio(for key: Key) -> CGFloat? {
        entries.withLock { $0[key] }
    }

    static func store(ratio: CGFloat, for key: Key) {
        entries.withLock { cache in
            if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
            cache[key] = ratio
        }
    }
}
