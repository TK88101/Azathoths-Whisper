import CoreGraphics
import Testing

@testable import AzathothsWhisper

// B1 計劃 §3.6、§5：組合風格的 plan（固定寬度量測替身）。歌詞為編造句
@Suite("Composed style plan")
struct ComposedStyleFrameTests {
    static let size = CGSize(width: 900, height: 560)
    static let measurer = FixedWidthMeasurer()
    static let black = SongProfile(axes: [.aggression: 0.9, .elegance: 0.1, .theatrical: 0.2], tags: [.black])
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 2, end: 6, text: "lanterns over water", isChorus: false),
        TimedLine(start: 6, end: 9, text: "ash in the wind", isChorus: false),
    ], source: .embeddedLRC, duration: 60)

    static func recipe(
        font: String = "Grimoire", backdrop: String = "void", enter: String = "condense", exit: String = "scatter",
        fx1: String = "none", fx2: String = "none", palette: String = "ice", seed: UInt64 = 7, profile: SongProfile = black
    ) -> SessionRecipe {
        .composed(ComposedRecipe(font: font, backdrop: backdrop, enter: enter, exit: exit, fx1: fx1, fx2: fx2, palette: palette, seed: seed, profile: profile))
    }

    private func plan(_ t: Double, _ recipe: SessionRecipe = recipe(), motion: LyricsFXMotion = .full, timeline: LyricsTimeline = timeline) -> FramePlan {
        LyricsFXFrame.plan(timeline: timeline, time: t, size: Self.size, motion: motion, recipe: recipe, measurer: Self.measurer)
    }

    @Test func theSameInputGivesTheSamePlan() {
        #expect(plan(3.3) == plan(3.3))
    }

    @Test func nothingBeforeTheFirstLine() {
        #expect(plan(1.5).glyphs.isEmpty)
    }

    @Test func onceEveryCharacterHasEnteredTheLineIsComplete() {
        // lash 進場 0.12–0.25 s：行尾前所有字都已落定（condense 長達 1.7 s，行尾時末字可能還在凝結）
        let glyphs = plan(5.9, Self.recipe(enter: "lash", exit: "fade")).glyphs
        #expect(glyphs.count == "lanternsoverwater".count)
        #expect(glyphs.allSatisfy { $0.opacity > 0.99 })
    }

    @Test func valuesStayInRangeThroughTheSong() {
        for enter in ["condense", "negative", "smoke", "rise", "swoop", "lash", "slam"] {
            for t in stride(from: 1.5, through: 12, by: 0.13) {
                let frame = plan(t, Self.recipe(enter: enter, exit: "fade"))
                for glyph in frame.glyphs + frame.ghosts {
                    #expect((0...1).contains(glyph.opacity), "\(enter)@\(t)")
                    #expect(glyph.scaleX > 0 && glyph.scaleY > 0 && glyph.fontSize > 0)
                }
            }
        }
    }

    @Test func settledGlyphsStayOnTheCanvas() {
        for glyph in plan(5.9, Self.recipe(enter: "swoop", exit: "fade")).glyphs {
            #expect(glyph.origin.x >= 0 && glyph.origin.x <= Self.size.width && glyph.origin.y >= 0 && glyph.origin.y <= Self.size.height)
        }
    }

    @Test func aCutLineVanishesAtItsEnd() {
        // 第一行 17 字、第二行 12 字：行尾一過，畫面上只可能是第二行的字
        #expect(plan(5.99, Self.recipe(exit: "cut")).glyphs.count >= 17)
        #expect(plan(6.01, Self.recipe(exit: "cut")).glyphs.count <= 12)
    }

    @Test func aTrailingLineLingersDimThenGoes() {
        let recipe = Self.recipe(exit: "fade")
        // 9.5 s：第一行（6 s 結束）的殘留已過、第二行（9 s 結束）正在殘留
        let lingering = plan(9.5, recipe).glyphs
        #expect(lingering.count == "ashinthewind".count && lingering.allSatisfy { $0.opacity < 1 })
        #expect(plan(9 + 0.7 + ComposedStyle.trailFade + 0.01, recipe).glyphs.isEmpty)
    }

    @Test func smokeIsDrawnAsGhostsWithoutTheBody() {
        let frame = plan(2.05, Self.recipe(enter: "smoke"))
        let entering = frame.ghosts.count
        #expect(entering > 0 && entering.isMultiple(of: ComposedStyle.ghostCopies))
    }

    @Test func condensingCharactersShedSpecks() {
        let frame = plan(2.2, Self.recipe(enter: "condense"))
        #expect(frame.back.contains { if case .particles = $0 { true } else { false } })
    }

    @Test func aNegativeEntranceInvertsTheGlyph() {
        // 每字出場時刻有抖動：掃過第一個詞的出場窗，負片時刻一定出現
        let frames = stride(from: 2.0, through: 3.0, by: 0.01).map { plan($0, Self.recipe(enter: "negative")) }
        #expect(frames.contains { !$0.boxes.isEmpty && $0.glyphs.contains { $0.color == .bg } })
        #expect(plan(5.9, Self.recipe(enter: "negative")).boxes.isEmpty, "落定後不再反白")
    }

    @Test func misregistrationAddsAShadowAndAHighlight() {
        let frame = plan(5.9, Self.recipe(fx1: "misreg"))
        #expect(frame.ghosts.filter { $0.color == .black }.count == frame.glyphs.count)
        #expect(frame.ghosts.filter { $0.color == .white }.count == frame.glyphs.count)
    }

    @Test func shakeKicksOnlyRightAtAWordStart() {
        let recipe = Self.recipe(fx1: "shake")
        #expect(plan(2.01, recipe).shake != .zero)
        #expect(plan(5.95, recipe).shake == .zero)
    }

    @Test func slamWordsExpireOnTheirOwnClock() {
        let long = LyricsTimeline(lines: [TimedLine(start: 1, end: 20, text: "iron", isChorus: false)], source: .embeddedLRC, duration: 30)
        #expect(!plan(1.5, Self.recipe(enter: "slam"), timeline: long).glyphs.isEmpty)
        #expect(plan(1 + 3.9, Self.recipe(enter: "slam"), timeline: long).glyphs.isEmpty)
    }

    @Test func backdropsBecomeLayers() {
        let shafts = plan(3, Self.recipe(backdrop: "shafts"))
        if case .axialGlow = shafts.back.first {} else { Issue.record("光柱的底是漸層") }
        let film = plan(3, Self.recipe(backdrop: "film"))
        #expect(film.front.contains { if case .grain(_, _, true) = $0 { true } else { false } })
        for backdrop in ["void", "film", "snow", "ash", "crimsonFog", "shafts"] {
            let particles = plan(3, Self.recipe(backdrop: backdrop)).back.reduce(0) { count, layer in
                if case .particles(let dots, _, _) = layer { count + dots.count } else { count }
            }
            #expect(particles <= ComposedStyle.maxParticles, "\(backdrop)")
        }
    }

    @Test func thePaletteComesFromTheRecipe() {
        #expect(plan(3, Self.recipe(palette: "goldNavy")).palette == LyricsFXCatalog.palette("goldNavy"))
    }

    @Test func reducedMotionFallsBackToMono() {
        let glyphs = plan(3, motion: .reduced).glyphs
        #expect(!glyphs.isEmpty && glyphs.allSatisfy { $0.face == .displayMedium || $0.face == .displayRegular })
    }

    @Test func uppercaseFontsShoutAndOthersCapitalizeTheFirstLetter() {
        #expect(plan(5.9, Self.recipe(font: "Catacombs")).glyphs.map(\.text).joined() == "LANTERNSOVERWATER")
        #expect(plan(5.9, Self.recipe(font: "Fraktur")).glyphs.map(\.text).joined() == "Lanternsoverwater")
    }

    @Test func monoRecipeIsTheA2Plan() {
        let mono = LyricsFXFrame.plan(timeline: Self.timeline, time: 3, size: Self.size, motion: .full, recipe: .mono, measurer: Self.measurer)
        #expect(mono == LyricsFXFrame.plan(timeline: Self.timeline, time: 3, size: Self.size, motion: .full, measurer: Self.measurer))
    }

    /// P12（使用者 2026-10-06，看 Catacombs 預覽）：「從無到有的漸入漸出持續時間稍長，字有點發虛」→ 淡入型進場與殘留淡出縮短 40%
    @Test func fadeInEntrancesAndTrailsAreShortenedP12() {
        let original: [String: ClosedRange<Double>] = ["condense": 0.9...1.7, "smoke": 0.6...1.3, "rise": 0.6...1.2]
        for (id, range) in original {
            guard case .enter(let spec)? = LyricsFXCatalog.component(id)?.payload else {
                Issue.record("\(id) 不在目錄")
                continue
            }
            #expect(abs(spec.duration.lowerBound - range.lowerBound * 0.6) < 1e-9 && abs(spec.duration.upperBound - range.upperBound * 0.6) < 1e-9, "\(id)")
        }
        guard case .enter(let slam)? = LyricsFXCatalog.component("slam")?.payload else { return }
        #expect(slam.duration == 0.14...0.26, "快速進場不動")
        #expect(ComposedStyle.trailHold == 0.4 && ComposedStyle.trailFade == 1.4)
    }

    @Test func theRecipeProbeShowsTheFontOrMono() {
        #expect(LyricsFXView.recipeProbeValue(Self.recipe(font: "Cinzel"), reduceMotion: false) == "Cinzel")
        #expect(LyricsFXView.recipeProbeValue(Self.recipe(font: "Cinzel"), reduceMotion: true) == "mono")
        #expect(LyricsFXView.recipeProbeValue(.mono, reduceMotion: false) == "mono")
    }
}
