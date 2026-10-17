import SwiftUI

/// 把 `FramePlan` 畫進 Canvas（View 與離屏渲染共用，A2 計劃 §3.6）。
/// painter order 上**連續、同鍵**（色槽, 量化透明度）的字是一個 run（B1 計劃 §3.2）；run 內逐字貼快取的點陣（計劃 2026-10-16），描邊仍併成一條外框。
/// 不跨 run 合併：否則 A(0.2)、B(0.5)、A(0.2) 的第三個 A 會跑到 B 底下（計劃評審 R1-1）
enum LyricsFXCanvas {
    /// 字形怎麼畫（計劃 2026-10-16 §2.3）：`.raster` 是正式畫法；`.vectorReference`＝改版前的合併外框畫法，只給畫面一致性測試比對；
    /// `.rasterIgnoringOptOut`＝連 `FontFace.rasterizes == false` 的字型也走點陣（描邊仍走外框），只給測試量那些字型走點陣的樣子（計劃 2026-10-17 全螢幕缺口 §3.1）
    enum GlyphRendering {
        case raster
        case vectorReference
        case rasterIgnoringOptOut
    }

    /// 一個 run 的畫法：描邊要路徑、或有不走點陣的字型（`FontFace.rasterizes`）→ 合併外框；半透明且多字 → 群組圖層裡逐字貼點陣（整層一次套透明度，疊色語義同合併外框）；其餘逐字貼點陣
    enum GlyphRunStrategy: Equatable {
        case vectorMerged
        case rasterGrouped
        case rasterDirect
    }

    static func glyphRunStrategy(level: Int, count: Int, stroke: CGFloat, rasterizes: Bool = true) -> GlyphRunStrategy {
        if stroke > 0 || !rasterizes { return .vectorMerged }
        return level < opacityLevels && count > 1 ? .rasterGrouped : .rasterDirect
    }

    /// 透明度量化的階數：0.05 一階（mono 的 1 與 0.55 恰在階上；誤差 ≤ 1/40）
    static let opacityLevels = 20

    struct Run: Equatable {
        let color: ColorSlot
        let level: Int
        let range: Range<Int>
        var stroke: CGFloat = 0
    }

    static func opacityLevel(_ opacity: Double) -> Int {
        Int((FXEasing.clamp01(opacity) * Double(opacityLevels)).rounded())
    }

    static func opacity(ofLevel level: Int) -> Double {
        Double(level) / Double(opacityLevels)
    }

    /// 連續同鍵的字切成一段；量化後為 0 的字不畫、也不打斷前後
    static func runs(of glyphs: [GlyphDraw], stroking: Bool = false) -> [Run] {
        var runs: [Run] = []
        for (index, glyph) in glyphs.enumerated() {
            let level = opacityLevel(glyph.opacity)
            guard level > 0 else { continue }
            let stroke = stroking ? glyph.stroke : 0
            if let last = runs.last, last.color == glyph.color, last.level == level, last.stroke == stroke {
                runs[runs.count - 1] = Run(color: last.color, level: level, range: last.range.lowerBound..<(index + 1), stroke: stroke)
            } else {
                runs.append(Run(color: glyph.color, level: level, range: index..<(index + 1), stroke: stroke))
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

    static func draw(_ plan: FramePlan, in context: GraphicsContext, size: CGSize, paths: GlyphPathCache, rendering: GlyphRendering = .raster) {
        paths.rasters.beginFrame()
        let palette = plan.palette
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(Path(bounds), with: .color(palette.bg.color))
        var shaken = context
        shaken.translateBy(x: plan.shake.width, y: plan.shake.height)
        if plan.zoom != 1 {
            shaken.translateBy(x: bounds.midX, y: bounds.midY)
            shaken.scaleBy(x: plan.zoom, y: plan.zoom)
            shaken.translateBy(x: -bounds.midX, y: -bounds.midY)
        }
        for layer in plan.back { draw(layer, in: shaken, bounds: bounds) }
        fill(plan.ghosts, in: shaken, palette: palette, paths: paths, rendering: rendering)
        for box in plan.boxes { draw(box, in: shaken, palette: palette) }
        if plan.glow > 0 {
            // 濾鏡套在整層的合成結果上，只做一次模糊（不是每個透明度 run 各做一次）
            shaken.drawLayer { lit in
                lit.addFilter(.shadow(color: palette.acc.color, radius: plan.glow))
                fill(plan.glyphs, in: lit, palette: palette, paths: paths, stroking: true, rendering: rendering)
            }
        } else {
            fill(plan.glyphs, in: shaken, palette: palette, paths: paths, stroking: true, rendering: rendering)
        }
        for layer in plan.front { draw(layer, in: context, bounds: bounds) }
    }

    private static func fill(
        _ glyphs: [GlyphDraw], in context: GraphicsContext, palette: FXPalette, paths: GlyphPathCache, stroking: Bool = false, rendering: GlyphRendering
    ) {
        for run in runs(of: glyphs, stroking: stroking) {
            let members = glyphs[run.range].filter { opacityLevel($0.opacity) > 0 }
            var layer = context
            layer.opacity = opacity(ofLevel: run.level)
            let color = palette[run.color].color
            let strategy = rendering == .vectorReference ? .vectorMerged : glyphRunStrategy(
                level: run.level, count: members.count, stroke: run.stroke,
                rasterizes: rendering == .rasterIgnoringOptOut || members.allSatisfy(\.face.rasterizes)
            )
            switch strategy {
            case .vectorMerged:
                let path = CGMutablePath()
                for glyph in members {
                    let entry = paths.entry(for: glyph)
                    path.addPath(entry.path, transform: transform(for: glyph, entry: entry))
                }
                let shape = Path(path)
                if run.stroke > 0 { layer.stroke(shape, with: .color(palette.acc.color), lineWidth: run.stroke) }
                layer.fill(shape, with: .color(color))
            case .rasterGrouped:
                // 圖層裡逐字全不透明，合成時整層一次套 run 的透明度——疊字處不會比合併外框更深
                layer.drawLayer { group in stamp(members, in: group, color: color, paths: paths) }
            case .rasterDirect:
                stamp(members, in: layer, color: color, paths: paths)
            }
        }
    }

    /// 逐字貼點陣：點陣與外框在同一個座標系，套同一個 `transform(for:)`
    private static func stamp(_ glyphs: [GlyphDraw], in context: GraphicsContext, color: Color, paths: GlyphPathCache) {
        let scale = context.environment.displayScale
        for glyph in glyphs {
            let entry = paths.entry(for: glyph)
            guard let raster = paths.rasters.entry(text: glyph.text, face: glyph.face, path: entry, pixelsPerPoint: scale) else { continue }
            var single = context
            single.concatenate(transform(for: glyph, entry: entry))
            var image = single.resolve(raster.image)
            image.shading = .color(color)
            single.draw(image, in: raster.box)
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
        case .radialGlow(let center, let radius, let stops):
            let origin = CGPoint(x: center.x * bounds.width, y: center.y * bounds.height), reach = radius * bounds.width
            // 最外圈透明時，圓外整片都是透明——只填圓的外接方框，畫面相同（失焦光斑一幀 14 個小光圈，不再各填滿全畫布）
            let area = stops.last.map { $0.opacity == 0 && $0.location <= 1 } == true
                ? bounds.intersection(CGRect(x: origin.x - reach, y: origin.y - reach, width: reach * 2, height: reach * 2))
                : bounds
            guard !area.isEmpty else { return }
            context.fill(Path(area), with: .radialGradient(gradient(stops), center: origin, startRadius: 0, endRadius: reach))
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
        case .axialGlow(let start, let end, let stops):
            context.fill(Path(bounds), with: .linearGradient(
                gradient(stops),
                startPoint: CGPoint(x: start.x * bounds.width, y: start.y * bounds.height),
                endPoint: CGPoint(x: end.x * bounds.width, y: end.y * bounds.height)))
        case .halftone(let step, let color, let opacity):
            var layer = context
            layer.opacity = opacity
            layer.fill(HalftonePathCache.shared.path(size: bounds.size, step: step), with: .color(color.color))
        case .hairlines(let spacing, let color, let opacity):
            let path = CGMutablePath()
            for y in stride(from: CGFloat(0), to: bounds.height, by: max(spacing, 1)) { path.addRect(CGRect(x: 0, y: y, width: bounds.width, height: 1)) }
            var layer = context
            layer.opacity = opacity
            layer.fill(Path(path), with: .color(color.color))
        case .rects(let rects, let color, let opacity):
            let path = CGMutablePath()
            path.addRects(rects)
            var layer = context
            layer.opacity = opacity
            layer.fill(Path(path), with: .color(color.color))
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
            MainActor.assumeIsolated { LyricsFXFrameMeter.shared.record(elapsed, plan: plan, rasters: glyphPaths.rasters) }
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

extension LyricsFXCanvas {
    static func gradient(_ stops: [GlowStop]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color.opacity($0.opacity), location: $0.location) })
    }
}

/// 半調網點的路徑只跟畫布尺寸與格距有關：快取最近一組，換尺寸才重建
final class HalftonePathCache: @unchecked Sendable {
    static let shared = HalftonePathCache()

    private let lock = NSLock()
    private var key: (size: CGSize, step: CGFloat)?
    private var cached = Path()

    func path(size: CGSize, step: CGFloat) -> Path {
        lock.lock()
        defer { lock.unlock() }
        if let key, key.size == size, key.step == step { return cached }
        var path = Path()
        for dot in ComposedBackdrop.halftoneDots(size: size, step: step) {
            path.addEllipse(in: CGRect(x: dot.x - dot.size, y: dot.y - dot.size, width: dot.size * 2, height: dot.size * 2))
        }
        key = (size, step)
        cached = path
        return path
    }
}
