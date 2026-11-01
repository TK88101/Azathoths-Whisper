import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 5 計劃 T4：移植原型 lyrics-fx-preview.html 的 steel／neon 背景與 stomp／heat 效果（pyro、strobe 不搬，P17）。歌詞為編造句

@MainActor
@Suite("B2 batch 5 effects")
struct B2BatchFiveEffectTests {
    static let size = CGSize(width: 900, height: 560)
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 2, end: 30, text: "iron gears turn under winter light", isChorus: false),
    ], source: .embeddedLRC, duration: 60)
    static let profile = SongProfile(axes: [.theatrical: 0.85, .aggression: 0.85, .cold: 0.8], tags: [.industrial])

    private func plan(_ t: Double, fx1: String = "none", backdrop: String = "void", palette: String = "terminal") -> FramePlan {
        let recipe = ComposedRecipe(font: "Anton", backdrop: backdrop, enter: "type", exit: "cut", fx1: fx1, fx2: "none", palette: palette, seed: 3, profile: Self.profile)
        return LyricsFXFrame.plan(timeline: Self.timeline, time: t, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: FixedWidthMeasurer())
    }

    /// 原型：頂上一盞冷白聚光（中心在畫面上緣外 0.1 高、半徑 1.1 高、0.18 → 0），只有顆粒、沒有暗角
    @Test func steelIsACoolTopLightWithGrainOnly() {
        let frame = plan(3, backdrop: "steel")
        #expect(frame.back == [
            .radialGlow(center: CGPoint(x: 0.5, y: -0.1), radius: 1.1 * (Self.size.height / Self.size.width), stops: [
                GlowStop(location: 0, color: RGB(hex: 0xDCE4EB), opacity: 0.18), GlowStop(location: 1, color: RGB(hex: 0x000000), opacity: 0),
            ]),
        ])
        #expect(frame.front == ComposedBackdrop.front(.haze, size: Self.size, time: 3))
        #expect(BackdropKind.steel.tone == nil)
    }

    /// 原型：下半粉紅漸層（0.55 高起、0 → 0.3）＋六條 2 點橫線，強調色與暗色交替；不加顆粒與暗角
    @Test func neonIsAPinkFloorGlowWithAlternatingLines() throws {
        let palette = try #require(LyricsFXCatalog.palette("terminal"))
        let lines = ComposedBackdrop.neonLines(size: Self.size)
        #expect(plan(3, backdrop: "neon").back == [
            .axialGlow(start: CGPoint(x: 0.5, y: 0.55), end: CGPoint(x: 0.5, y: 1), stops: [
                GlowStop(location: 0, color: RGB(hex: 0xFF2E88), opacity: 0), GlowStop(location: 1, color: RGB(hex: 0xFF2E88), opacity: 0.3),
            ]),
            .rects(lines.pink, palette.acc, opacity: 0.5), .rects(lines.cyan, palette.dim, opacity: 0.5),
        ])
        #expect(plan(3, backdrop: "neon").front.isEmpty)
    }

    /// 原型：每個詞起點後 0.15 s 內整屏往下沉，最深 0.012 畫面高、線性回彈（取同時最強的詞）
    @Test func stompSinksTheScreenOnEveryWord() throws {
        let words = try #require(Self.timeline.lines.first?.words)
        for t in [words[1].start, words[1].start + 0.05, words[2].start + 0.2, 1.0] {
            let hit = words.reduce(0.0) { strongest, word in
                let since = t - word.start
                return since >= 0 && since < 0.15 ? max(strongest, 1 - since / 0.15) : strongest
            }
            let frame = plan(t, fx1: "stomp")
            #expect(abs(frame.shake.height - 0.012 * Self.size.height * CGFloat(hit)) < 1e-9, "t=\(t)")
            #expect(frame.shake.width == 0)
        }
        #expect(plan(words[1].start).shake == .zero)
    }

    /// 原型：字緣紅光，停穩後 shadowBlur 14×0.5；app 的光暈層畫配色強調色（Rammstein 兩組配色都是紅），半徑依 glow 的換算＝glowRadius × 7／14.8
    @Test func heatGivesTheTextAHalfStrengthAccentGlow() {
        #expect(plan(5, fx1: "heat", palette: "steelFire").glow == ComposedStyle.heatGlowRadius)
        #expect(abs(ComposedStyle.heatGlowRadius - ComposedStyle.glowRadius * 7 / 14.8) < 1e-9)
        #expect(plan(5, palette: "steelFire").glow == 0)
    }

    /// G1（V5）：本批新背景×配色、加上 heat，英／日文主字對比都 ≥ 4.5（全組合另由 LyricsFXContrastTests 涵蓋）
    @Test(arguments: ["steel|steelFire", "steel|blackRed", "void|steelFire", "void|blackRed", "neon|neonPink", "neon|terminal", "neon|mono", "neon|yellowBlack"])
    func theBatchsNewPairsStayReadable(pair: String) {
        let parts = pair.split(separator: "|").map(String.init)
        let fxs = parts[1] == "steelFire" || parts[1] == "blackRed" ? ["none", "heat"] : ["none"]
        for fx in fxs {
            for lyrics in [LyricsFXContrastTests.timeline, LyricsFXContrastTests.japanese] {
                #expect(LyricsFXContrastTests.readabilityFailure(backdrop: parts[0], palette: parts[1], fx: fx, lyrics: lyrics) == nil)
            }
        }
    }
}
