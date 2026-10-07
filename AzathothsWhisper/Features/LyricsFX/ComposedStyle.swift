import CoreGraphics
import Foundation

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
        let hold: [(HoldTemplate, Double)] = effects.contains(.breathe)
            ? [(.breathe, 3), (.still, 2)]
            : (aggression > 0.7 ? [(.still, 5), (.twitch, 1)] : [(.still, 3), (.drift, 1), (.float, 1)])
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
    /// 每字右側多留的間距（em 比例）
    static let spacing: CGFloat = 0.08
    static let wordGap: CGFloat = 0.3
    static let maxWidthRatio: CGFloat = 0.86
    static let baseYRatio: CGFloat = 0.5
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
    /// 詞首後多久內整屏抖
    static let shakeWindow = 0.07
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
        if style.effects.contains(.shake), let current = visible.first(where: { $0.exit == 0 && $0.trail == nil }) {
            frame.shake = shake(current.line, time: time)
        }
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
        let row: Int
    }

    /// 一行排好的版面：字、各列寬、各詞的（起點 x, 寬）——彈片堆用，免得每字重掃整行
    private struct LineLayout {
        let glyphs: [LaidGlyph]
        let rowWidths: [CGFloat]
        let words: [(x: CGFloat, width: CGFloat)]
    }

    private static func draw(
        _ entry: VisibleLine, time: Double, size: CGSize, style: ResolvedStyle, measurer: any TextMeasuring,
        into frame: inout FramePlan, specks: inout [(Particle, Double)]
    ) {
        let em = size.height * emRatio
        var indexMixer = SplitMix64(seed: UInt64(entry.index))
        let lineSeed = FXHash.fnv1a64(entry.line.text) ^ style.seed ^ indexMixer.next()
        let personalities = LinePersonalities.make(line: entry.line, seed: lineSeed, style: style.personality)
        let laid = layout(entry.line, personalities: personalities, em: em, maxWidth: size.width * maxWidthRatio, face: style.face, measurer: measurer)
        let rowHeight = em * lineHeight
        let baseY = size.height * baseYRatio - CGFloat(laid.rowWidths.count) * rowHeight / 2 + rowHeight * 0.8
        let misregistered = style.effects.contains(.misreg)
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
            let advance = glyph.width - spacing * em
            let base = GlyphDraw(
                text: glyph.character, face: style.face, fontSize: fontSize,
                origin: CGPoint(x: center.x - advance / 2, y: center.y - measurer.ascent(face: style.face, fontSize: fontSize)),
                rotation: CGFloat(personality.rotation) + baseRotation + transform.rotation,
                scaleX: transform.scale * transform.scaleX, scaleY: transform.scale * transform.scaleY, opacity: alpha, color: .fg
            )
            var random = SplitMix64(seed: lineSeed &+ UInt64(glyph.index) &* 7919)
            if transform.specks > 0 {
                specks += speckParticles(around: center, em: fontSize, strength: transform.specks, alpha: alpha, random: &random)
            }
            emit(base, glyphWidth: glyph.width, center: center, transform: transform, misregistered: misregistered, random: &random, into: &frame)
        }
    }

    /// 進場（進度 0…1）＋落定後的停留＋退場三段合成；還沒出場或已過壽命（彈片硬切）＝nil
    private static func glyphTransform(
        _ glyph: LaidGlyph, personality: GlyphPersonality, entry: VisibleLine, time: Double, size: CGSize, em: CGFloat,
        style: ResolvedStyle, rowWidth: CGFloat
    ) -> GlyphTransform? {
        let progress = FXEasing.clamp01((time - personality.start) / max(personality.duration, 1e-6))
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

    /// 依效果把一個字放進繪製指令：殘影（只畫副本、不畫本體）、負片（色塊＋底色字）、影印錯位（黑影＋白光＋本體）或本體
    private static func emit(
        _ base: GlyphDraw, glyphWidth: CGFloat, center: CGPoint, transform: GlyphTransform, misregistered: Bool,
        random: inout SplitMix64, into frame: inout FramePlan
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
            frame.glyphs.append(base.shifted(dx: 0, dy: 0, opacity: alpha, color: .bg))
        } else {
            if misregistered {
                frame.ghosts.append(base.shifted(dx: 2.5, dy: 2.5, opacity: alpha * 0.6, color: .black))
                frame.ghosts.append(base.shifted(dx: -1, dy: -1, opacity: alpha * 0.08, color: .white))
            }
            frame.glyphs.append(base)
        }
    }

    /// 以詞為單位貪婪折行（原型 `layout`）：字寬依個性字級量、每字加 spacing、詞間 0.3 em
    private static func layout(
        _ line: TimedLine, personalities: [GlyphPersonality], em: CGFloat, maxWidth: CGFloat, face: FontFace, measurer: any TextMeasuring
    ) -> LineLayout {
        var glyphs: [LaidGlyph] = []
        var rowWidths: [CGFloat] = [0]
        var words: [(x: CGFloat, width: CGFloat)] = []
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
            for (character, width) in zip(characters, widths) {
                glyphs.append(LaidGlyph(character: character, wordIndex: wordIndex, index: index, x: rowWidths[row], width: width, row: row))
                rowWidths[row] += width
                index += 1
            }
        }
        return LineLayout(glyphs: glyphs, rowWidths: rowWidths, words: words)
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

    /// 詞首 70 ms 內整屏抖（原型 html:1009-1010）；以 1/60 s 為一格取亂數
    private static func shake(_ line: TimedLine, time: Double) -> CGSize {
        let hit = line.words.reduce(0.0) { strongest, word in
            let since = time - word.start
            return since >= 0 && since < shakeWindow ? max(strongest, 1 - since / shakeWindow) : strongest
        }
        guard hit > 0 else { return .zero }
        var random = SplitMix64(seed: UInt64(max(time * 60, 0)))
        return CGSize(width: (random.unit() - 0.5) * 12 * hit, height: (random.unit() - 0.5) * 8 * hit)
    }
}

extension GlyphDraw {
    func shifted(dx: CGFloat, dy: CGFloat, opacity: Double, color: ColorSlot) -> GlyphDraw {
        GlyphDraw(
            text: text, face: face, fontSize: fontSize, origin: CGPoint(x: origin.x + dx, y: origin.y + dy),
            rotation: rotation, scaleX: scaleX, scaleY: scaleY, opacity: opacity, color: color
        )
    }
}
