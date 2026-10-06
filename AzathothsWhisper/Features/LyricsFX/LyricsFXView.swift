import SwiftUI

/// 把 `FramePlan` 畫進 Canvas（View 與離屏渲染共用，A2 計劃 §3.6）。
/// 逐字取外框路徑，同透明度同色的字併成一條 Path、一次 fill（A2 計劃 §3.7：逐字 `draw(Text)` 實測超預算）
enum LyricsFXCanvas {
    private struct Group: Hashable {
        let opacity: Double
        let tone: GlyphDraw.Tone
    }

    static func draw(_ plan: FramePlan, in context: GraphicsContext, paths: GlyphPathCache) {
        var groups: [Group: Path] = [:]
        var order: [Group] = []
        for glyph in plan.glyphs where glyph.opacity > 0 {
            let group = Group(opacity: glyph.opacity, tone: glyph.tone)
            if groups[group] == nil { order.append(group) }
            groups[group, default: Path()].addPath(
                Path(paths.path(for: glyph)),
                transform: CGAffineTransform(translationX: glyph.origin.x, y: glyph.origin.y)
            )
        }
        for group in order {
            guard let path = groups[group] else { continue }
            var layer = context
            layer.opacity = group.opacity
            layer.fill(path, with: .color(group.tone == .primary ? Theme.coldWhite : Theme.Gray.g500))
        }
    }
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
        let motion = motion
        let measurer = measurer
        let glyphPaths = glyphPaths
        return Canvas { context, size in
            #if DEBUG
            let started = ContinuousClock.now
            #endif
            let plan = LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: motion, measurer: measurer)
            LyricsFXCanvas.draw(plan, in: context, paths: glyphPaths)
            #if DEBUG
            let elapsed = ContinuousClock.now - started
            MainActor.assumeIsolated { LyricsFXFrameMeter.shared.record(elapsed, glyphs: plan.glyphs.count) }
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
