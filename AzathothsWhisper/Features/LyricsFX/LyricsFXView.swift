import SwiftUI

/// 把 `FramePlan` 畫進 Canvas（View 與離屏渲染共用，A2 計劃 §3.6）。
/// 逐字取外框路徑；painter order 上**連續、同鍵**（色槽, 量化透明度）的字併成一條 Path、一次 fill（B1 計劃 §3.2）。
/// 不跨 run 合併：否則 A(0.2)、B(0.5)、A(0.2) 的第三個 A 會跑到 B 底下（計劃評審 R1-1）
enum LyricsFXCanvas {
    /// 透明度量化的階數：0.05 一階（mono 的 1 與 0.55 恰在階上；誤差 ≤ 1/40）
    static let opacityLevels = 20

    struct Run: Equatable {
        let color: ColorSlot
        let level: Int
        let range: Range<Int>
    }

    static func opacityLevel(_ opacity: Double) -> Int {
        Int((FXEasing.clamp01(opacity) * Double(opacityLevels)).rounded())
    }

    static func opacity(ofLevel level: Int) -> Double {
        Double(level) / Double(opacityLevels)
    }

    /// 連續同鍵的字切成一段；量化後為 0 的字不畫、也不打斷前後
    static func runs(of glyphs: [GlyphDraw]) -> [Run] {
        var runs: [Run] = []
        for (index, glyph) in glyphs.enumerated() {
            let level = opacityLevel(glyph.opacity)
            guard level > 0 else { continue }
            if let last = runs.last, last.color == glyph.color, last.level == level {
                runs[runs.count - 1] = Run(color: last.color, level: level, range: last.range.lowerBound..<(index + 1))
            } else {
                runs.append(Run(color: glyph.color, level: level, range: index..<(index + 1)))
            }
        }
        return runs
    }

    /// 字形外框（快取字級）→ 畫布：先縮放到字級、以外框中心旋轉與縮放，再移到 origin
    static func transform(for glyph: GlyphDraw, entry: GlyphPathCache.Entry) -> CGAffineTransform {
        let ratio = glyph.fontSize / entry.size
        let base = CGAffineTransform(scaleX: ratio, y: ratio)
        guard glyph.rotation != 0 || glyph.scaleX != 1 || glyph.scaleY != 1 else {
            return base.concatenating(CGAffineTransform(translationX: glyph.origin.x, y: glyph.origin.y))
        }
        let pivot = CGPoint(x: entry.center.x * ratio, y: entry.center.y * ratio)
        return base
            .concatenating(CGAffineTransform(translationX: -pivot.x, y: -pivot.y))
            .concatenating(CGAffineTransform(scaleX: glyph.scaleX, y: glyph.scaleY))
            .concatenating(CGAffineTransform(rotationAngle: glyph.rotation))
            .concatenating(CGAffineTransform(translationX: glyph.origin.x + pivot.x, y: glyph.origin.y + pivot.y))
    }

    static func draw(_ plan: FramePlan, in context: GraphicsContext, size: CGSize, paths: GlyphPathCache) {
        let palette = plan.palette
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(Path(bounds), with: .color(palette.bg.color))
        var shaken = context
        shaken.translateBy(x: plan.shake.width, y: plan.shake.height)
        for layer in plan.back { draw(layer, in: shaken, bounds: bounds) }
        fill(plan.ghosts, in: shaken, palette: palette, paths: paths)
        for box in plan.boxes { draw(box, in: shaken, palette: palette) }
        fill(plan.glyphs, in: shaken, palette: palette, paths: paths)
        for layer in plan.front { draw(layer, in: context, bounds: bounds) }
    }

    private static func fill(_ glyphs: [GlyphDraw], in context: GraphicsContext, palette: FXPalette, paths: GlyphPathCache) {
        for run in runs(of: glyphs) {
            let path = CGMutablePath()
            for glyph in glyphs[run.range] where opacityLevel(glyph.opacity) > 0 {
                let entry = paths.entry(for: glyph)
                path.addPath(entry.path, transform: transform(for: glyph, entry: entry))
            }
            var layer = context
            layer.opacity = opacity(ofLevel: run.level)
            layer.fill(Path(path), with: .color(palette[run.color].color))
        }
    }

    private static func draw(_ box: GlyphBox, in context: GraphicsContext, palette: FXPalette) {
        let rect = CGRect(x: -box.size.width / 2, y: -box.size.height / 2, width: box.size.width, height: box.size.height)
        let transform = CGAffineTransform(rotationAngle: box.rotation).concatenating(CGAffineTransform(translationX: box.center.x, y: box.center.y))
        var layer = context
        layer.opacity = box.opacity
        layer.fill(Path(rect).applying(transform), with: .color(palette[box.color].color))
    }

    private static func draw(_ layer: LayerDraw, in context: GraphicsContext, bounds: CGRect) {
        switch layer {
        case .fill(let color, let opacity):
            var fill = context
            fill.opacity = opacity
            fill.fill(Path(bounds), with: .color(color.color))
        case .linearGradient(let top, let bottom):
            context.fill(Path(bounds), with: .linearGradient(
                Gradient(colors: [top.color, bottom.color]), startPoint: CGPoint(x: bounds.midX, y: 0), endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))
        case .radialGlow(let center, let radius, let stops):
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color.opacity($0.opacity), location: $0.location) }),
                center: CGPoint(x: center.x * bounds.width, y: center.y * bounds.height), startRadius: 0, endRadius: radius * bounds.width))
        case .lightShafts(let xs, let width, let color, let opacity):
            for x in xs {
                let left = x * bounds.width, right = left + width * bounds.width
                context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: bounds.height)), with: .linearGradient(
                    Gradient(colors: [color.color.opacity(0), color.color.opacity(opacity), color.color.opacity(0)]),
                    startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0)))
            }
        case .particles(let particles, let color, let opacity):
            let path = CGMutablePath()
            for particle in particles { path.addRect(CGRect(x: particle.x, y: particle.y, width: particle.size, height: particle.size)) }
            var dots = context
            dots.opacity = opacity
            dots.fill(Path(path), with: .color(color.color))
        case .vignette(let strength):
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(strength)]),
                center: CGPoint(x: bounds.midX, y: bounds.midY),
                startRadius: min(bounds.width, bounds.height) * 0.35, endRadius: max(bounds.width, bounds.height) * 0.75))
        case .grain(let opacity, let frame, let overlay):
            guard let noise = BundleAssets.noise else { return }
            // 每格換一個平鋪起點，噪點才會動（原型每幀重抽噪點）
            let shift = CGPoint(x: CGFloat((frame &* 37) % 128), y: CGFloat((frame &* 91) % 128))
            var grain = context
            grain.opacity = opacity
            grain.blendMode = overlay ? .overlay : .screen
            grain.fill(Path(bounds), with: .tiledImage(Image(nsImage: noise), origin: shift, scale: 1))
        case .scratches(let xs, let opacity):
            let path = CGMutablePath()
            for x in xs {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: bounds.height))
            }
            var lines = context
            lines.opacity = opacity
            lines.stroke(Path(path), with: .color(.white), lineWidth: 1)
        }
    }
}

extension RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// 升起層的歌詞特效畫面（母計劃 §2.7；A2 計劃 §3.4）。只有 mono。
/// 不可見時只畫背景、不建定時器；沒有詞可畫時畫背景＋既有狀態字（overlay，不進 Canvas）
struct LyricsFXView: View {
    let model: LyricsFXViewModel
    let reduceMotion: Bool

    @State private var measurer = CoreTextMeasurer()
    @State private var glyphPaths = GlyphPathCache()

    /// mono 的淡入淡出只有 0.35 s，60 fps 足夠；ProMotion 螢幕不必以 120 Hz 重繪整首歌
    private static let frameInterval = 1.0 / 60

    private var motion: LyricsFXMotion { reduceMotion ? .reduced : .full }

    var body: some View {
        // 讀 observable 的 anchor：暫停／恢復、拖進度時 body 會重算
        let isRunning: Bool = if case .running = model.positionClock.anchor { true } else { false }
        let schedule = LyricsFXSchedule.resolve(isVisible: model.isVisible, isRunning: isRunning, reduceMotion: reduceMotion)
        ZStack {
            Theme.background
            if model.isVisible {
                switch schedule {
                case .none:
                    frame(at: .now)
                case .animation:
                    TimelineView(.animation(minimumInterval: Self.frameInterval)) { _ in frame(at: .now) }
                case .periodic:
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in frame(at: .now) }
                }
            }
            statusOverlay
        }
    }

    private func frame(at now: ContinuousClock.Instant) -> some View {
        let time = model.positionClock.position(at: now)
        let timeline = model.timeline
        let recipe = model.recipe
        let motion = motion
        let measurer = measurer
        let glyphPaths = glyphPaths
        return Canvas { context, size in
            #if DEBUG
            let started = ContinuousClock.now
            #endif
            let plan = LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: motion, recipe: recipe, measurer: measurer)
            LyricsFXCanvas.draw(plan, in: context, size: size, paths: glyphPaths)
            #if DEBUG
            let elapsed = ContinuousClock.now - started
            MainActor.assumeIsolated { LyricsFXFrameMeter.shared.record(elapsed, plan: plan) }
            #endif
        }
        .accessibilityHidden(true)
        // 無障礙：VoiceOver 只讀當前行。用一枚看不見的文字承載——macOS 上文字的內容才穩定出現在 AX value
        // （Canvas 上的 accessibilityValue 實測讀到空字串，2026-10-06 UI 測試）
        .overlay(alignment: .topLeading) {
            Text(verbatim: LyricsFXFrame.currentLineText(timeline: timeline, time: time) ?? " ")
                .font(.system(size: 1))
                .foregroundStyle(Color.clear)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityIdentifier(AccessibilityID.lyricsFXLayer)
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            AccessibilityProbe(id: AccessibilityID.lyricsFXRecipeProbe, value: Self.recipeProbeValue(recipe, reduceMotion: motion == .reduced))
        }
        #endif
    }

    /// 減少動態效果時畫的是 mono，探針跟著回 mono
    static func recipeProbeValue(_ recipe: SessionRecipe, reduceMotion: Bool) -> String {
        guard !reduceMotion, case .composed(let composed) = recipe else { return "mono" }
        return composed.font
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let text = model.statusText {
            Text(verbatim: text)
                .font(Theme.Fonts.mono(11))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Gray.g400)
        } else if model.identity != nil, model.status != .present {
            LyricsStatusLabel(status: model.status)
        }
    }
}
