import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// B2 計劃 T5、T4：批 1（rock 系 9 團）的簽字對照、背景與配色的亮暗相容、新效果。歌詞為編造句

@Suite("B2 batch 1 signed fixture")
struct B2SignedFixtureTests {
    @Test func everySignedBandAndAliasResolvesToItsSignedProfile() throws {
        let file = try SignedBatchFile.load(batch: 1)
        #expect(file.bands.count == 9)
        SignedBatchChecks.everyBandAndAliasResolvesToItsSignedProfile(file)
    }

    @Test func everySignedBandIsInTheSecondBatch() throws {
        #expect(Set(SongProfileResolver.batchTwo.map(\.name)) == Set(try SignedBatchFile.load(batch: 1).bands.map(\.name)))
    }

    @Test func theAppOffersExactlyTheSignedCandidatesInEverySlot() throws {
        SignedBatchChecks.theAppOffersExactlyTheSignedCandidatesInEverySlot(try SignedBatchFile.load(batch: 1))
    }
}

@Suite("Backdrop and palette tone")
struct BackdropPaletteToneTests {
    @Test func lightPalettesAreRecognisedFromTheirBackground() {
        for id in ["popArt", "cream60", "mancSky", "britRed"] { #expect(LyricsFXCatalog.palette(id)?.isLight == true, "\(id)") }
        for id in ["ampRed", "vegas", "ice", "boneBlood"] { #expect(LyricsFXCatalog.palette(id)?.isLight == false, "\(id)") }
    }

    @Test func aBackdropThatNeedsADarkOrLightPaletteNeverGetsTheOtherKind() throws {
        for band in try SignedBatchFile.load(batch: 1).bands {
            for seed in UInt64(1)...200 {
                guard case .composed(let recipe) = Composer.compose(profile: band.profile, seed: seed),
                      case .backdrop(let backdrop)? = LyricsFXCatalog.component(recipe.backdrop)?.payload,
                      let tone = backdrop.tone, let palette = LyricsFXCatalog.palette(recipe.palette) else { continue }
                #expect(tone.accepts(palette), "\(band.name) seed \(seed)：\(recipe.backdrop)＋\(recipe.palette)")
            }
        }
    }
}

@Suite("B2 batch 1 effects")
struct B2EffectTests {
    static let size = CGSize(width: 900, height: 560)
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 2, end: 6, text: "lanterns over water", isChorus: false),
    ], source: .embeddedLRC, duration: 60)
    static let profile = SongProfile(axes: [.aggression: 0.4, .elegance: 0.5, .theatrical: 0.6], tags: [.arena])

    private func plan(_ t: Double, fx1: String, fx2: String = "none", backdrop: String = "void", palette: String = "vegas") -> FramePlan {
        let recipe = ComposedRecipe(font: "Bebas", backdrop: backdrop, enter: "fadeUp", exit: "up", fx1: fx1, fx2: fx2, palette: palette, seed: 3, profile: Self.profile)
        return LyricsFXFrame.plan(timeline: Self.timeline, time: t, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: FixedWidthMeasurer())
    }

    @Test func thumpZoomsTheScreenRightAfterAWordStartsThenSettles() {
        #expect(plan(2.03, fx1: "thump").zoom > 1.02)
        #expect(plan(5.5, fx1: "thump").zoom == 1)
        #expect(plan(2.03, fx1: "none").zoom == 1)
    }

    @Test func reflectAddsAFaintUpsideDownCopyOfEveryGlyph() {
        let frame = plan(5.5, fx1: "reflect")
        let mirrored = frame.ghosts.filter { $0.scaleY < 0 }
        #expect(mirrored.count == frame.glyphs.count && !mirrored.isEmpty)
        #expect(mirrored.allSatisfy { $0.opacity <= 0.16 + 1e-9 })
    }

    @Test func glowAndNeonStrokeAreFrameLevelSettings() {
        #expect(plan(5.5, fx1: "glow").glow > 0 && plan(5.5, fx1: "glow").stroke == 0)
        #expect(plan(5.5, fx1: "neonstroke").stroke > 0 && plan(5.5, fx1: "neonstroke").glow > 0)
        #expect(plan(5.5, fx1: "none").glow == 0 && plan(5.5, fx1: "none").stroke == 0)
    }

    @Test(arguments: [("bob", HoldTemplate.bob), ("wobble", .wobble), ("flicker", .flicker)])
    func smallHoldEffectsBecomeTheHoldTemplate(effect: String, template: HoldTemplate) throws {
        let recipe = ComposedRecipe(font: "Bebas", backdrop: "void", enter: "fadeUp", exit: "up", fx1: effect, fx2: "none", palette: "vegas", seed: 3, profile: Self.profile)
        let style = try #require(ResolvedStyle(recipe))
        #expect(style.personality.hold.first?.0 == template)
    }

    @Test(arguments: ["ampGlow", "embers", "halftone", "haze", "paper", "prism", "smokeHaze", "spot", "stars", "sunset", "tapeLeak"])
    func everyNewBackdropDrawsSomething(backdrop: String) {
        let frame = plan(3, fx1: "none", backdrop: backdrop, palette: backdrop == "halftone" ? "popArt" : "vegas")
        #expect(!(frame.back + frame.front).isEmpty, "\(backdrop)")
    }
}
