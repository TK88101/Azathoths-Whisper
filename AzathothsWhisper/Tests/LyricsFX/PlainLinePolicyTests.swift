import CoreGraphics
import Testing

@testable import AzathothsWhisper

// ⑤ 中日韓字型計劃 §4.3：韓文行無特效（使用者 2026-10-22）——只做整行淡入淡出；目前行是韓文時整格效果不觸發；
// 同一首的英文行照原 recipe。固定字寬量測，歌詞為編造句
@Suite("Plain line policy")
struct PlainLinePolicyTests {
    static let size = CGSize(width: 900, height: 560)
    static let korean = "AppleSDGothicNeo-SemiBold"
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 1, end: 4, text: "lanterns over water", isChorus: false),
        TimedLine(start: 4, end: 8, text: "새벽 하늘 lanterns", isChorus: false),
        TimedLine(start: 8, end: 11, text: "ash in the wind", isChorus: false),
    ], source: .embeddedLRC, duration: 60)

    private func plan(_ time: Double, enter: String = "smoke", fx1: String = "glow", fx2: String = "misreg") -> FramePlan {
        let recipe = ComposedRecipe(
            font: "Bebas", backdrop: "void", enter: enter, exit: "scatter", fx1: fx1, fx2: fx2, palette: "ice", seed: 7,
            profile: SongProfile(axes: [.aggression: 0.8], tags: [])
        )
        return LyricsFXFrame.plan(timeline: Self.timeline, time: time, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: FixedWidthMeasurer())
    }

    private func koreanGlyphs(_ glyphs: [GlyphDraw]) -> [GlyphDraw] {
        glyphs.filter { $0.face.postScriptName == Self.korean }
    }

    @Test(arguments: [4.05, 4.2, 5.0, 7.9])
    func aKoreanLineIsDrawnWithOpacityOnly(time: Double) {
        let frame = plan(time)
        let drawn = koreanGlyphs(frame.unlit + frame.glyphs)
        #expect(drawn.count == "새벽하늘lanterns".count)
        #expect(drawn.allSatisfy { $0.rotation == 0 && $0.scaleX == 1 && $0.scaleY == 1 && $0.stroke == 0 && $0.color == .fg })
        #expect(Set(drawn.map(\.fontSize)).count == 1)
        #expect(koreanGlyphs(frame.ghosts).isEmpty)
        #expect(frame.boxes.isEmpty)
    }

    @Test func aKoreanLineStaysOutOfTheGlowLayer() {
        let frame = plan(5)
        #expect(koreanGlyphs(frame.glyphs).isEmpty)
        #expect(!koreanGlyphs(frame.unlit).isEmpty)
    }

    @Test func aKoreanLineFadesInOverTheFirstMoment() {
        let early = koreanGlyphs(plan(4.1).unlit).map(\.opacity)
        let settled = koreanGlyphs(plan(5).unlit).map(\.opacity)
        #expect(early.allSatisfy { $0 > 0 && $0 < 1 })
        #expect(settled.allSatisfy { $0 == 1 })
    }

    @Test(arguments: [4.0, 4.03, 4.1, 4.3, 6.0])
    func noFrameEffectsWhileKoreanIsTheCurrentLine(time: Double) {
        let frame = plan(time, fx1: "shake", fx2: "thump")
        #expect(frame.shake == .zero)
        #expect(frame.zoom == 1)
        let lines = plan(time, fx1: "speedlines", fx2: "none")
        #expect(lines.back.count == plan(0.5, fx1: "speedlines", fx2: "none").back.count)
    }

    @Test func theEnglishLineAfterwardsTriggersFrameEffectsAgain() {
        #expect(plan(8.05, fx1: "speedlines", fx2: "none").back.count > plan(0.5, fx1: "speedlines", fx2: "none").back.count)
        #expect(plan(1.05, fx1: "speedlines", fx2: "none").back.count > plan(0.5, fx1: "speedlines", fx2: "none").back.count)
    }

    @Test func englishLinesKeepTheirEffects() {
        let frame = plan(3)
        #expect(!frame.ghosts.isEmpty)   // misreg 副本
        #expect(frame.glyphs.allSatisfy { $0.face.id == "Bebas" })
    }
}
