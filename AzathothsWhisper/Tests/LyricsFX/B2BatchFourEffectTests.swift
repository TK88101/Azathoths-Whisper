import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// B2 批 4 計劃 T4：emo 群新增的背景（雨絲、藍調時刻）與效果（往下暈開），移植原型 lyrics-fx-preview.html 的 rain／bluehour／weep。
// 歌詞為編造句

@Suite("B2 batch 4 effects")
struct B2BatchFourEffectTests {
    static let size = CGSize(width: 900, height: 560)
    static let timeline = LyricsTimeline(lines: [
        TimedLine(start: 2, end: 30, text: "paper boats in the gutter", isChorus: false),
    ], source: .embeddedLRC, duration: 60)
    static let profile = SongProfile(axes: [.theatrical: 0.9, .aggression: 0.6], tags: [.emo])

    private func plan(_ t: Double, fx1: String = "none", fx2: String = "none", backdrop: String = "void") -> FramePlan {
        let recipe = ComposedRecipe(font: "Anton", backdrop: backdrop, enter: "type", exit: "cut", fx1: fx1, fx2: fx2, palette: "hybridGrey", seed: 3, profile: Self.profile)
        return LyricsFXFrame.plan(timeline: Self.timeline, time: t, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: FixedWidthMeasurer())
    }

    @Test func rainIsThinSlantedStreaksInTheDimColourFallingUnderAVignette() throws {
        let palette = try #require(LyricsFXCatalog.palette("hybridGrey"))
        let still = ComposedBackdrop.back(.rain, palette: palette, size: Self.size, time: 0)
        guard case .streaks(let streaks, let color, let opacity)? = still.first, still.count == 1 else { Issue.record("雨絲應是一層細線"); return }
        #expect(color == palette.dim && opacity == 0.3 && streaks.count == ComposedBackdrop.rainCount)
        for streak in streaks {
            let length = streak.to.y - streak.from.y
            // 長度＝畫布高的 4–9%，往左下斜（橫移＝長度的 18%）
            #expect(length >= Self.size.height * 0.04 - 1e-6 && length <= Self.size.height * 0.09 + 1e-6)
            #expect(abs((streak.from.x - streak.to.x) - length * 0.18) < 1e-6)
        }
        // 往下落：0.1 秒後每一條都在原位下方 26–48 點（每秒 260–480 點；繞回頂端的不算）
        guard case .streaks(let later, _, _)? = ComposedBackdrop.back(.rain, palette: palette, size: Self.size, time: 0.1).first else { return }
        let fallen = zip(streaks, later).map { $1.from.y - $0.from.y }.filter { $0 > 0 }
        #expect(fallen.count >= streaks.count - 12 && fallen.allSatisfy { $0 >= 26 - 1e-6 && $0 <= 48 + 1e-6 })
        #expect(BackdropKind.rain.tone == .dark)
        let front = ComposedBackdrop.front(.rain, size: Self.size, time: 0)
        #expect(front.first == .vignette(strength: 0.7) && front.count == 2)
    }

    @Test func blueHourIsACoolGlowRisingFromTheBottomWithAFaintWarmWindow() {
        let frame = plan(3, backdrop: "bluehour")
        #expect(frame.back == [
            .axialGlow(start: CGPoint(x: 0.5, y: 0.3), end: CGPoint(x: 0.5, y: 1), stops: [
                GlowStop(location: 0, color: RGB(hex: 0x3C6EAA), opacity: 0), GlowStop(location: 1, color: RGB(hex: 0x3C6EAA), opacity: 0.34),
            ]),
            .radialGlow(center: CGPoint(x: 0.22, y: 0.2), radius: 0.7 * Self.size.height / Self.size.width, stops: [
                GlowStop(location: 0, color: RGB(hex: 0xFFD6A0), opacity: 0.08), GlowStop(location: 1, color: RGB(hex: 0x000000), opacity: 0),
            ]),
        ])
        #expect(BackdropKind.bluehour.tone == .dark)
        #expect(frame.front.first == .vignette(strength: 0.7))
    }

    @Test func weepGrowsFromNothingAfterAQuarterSecondToFullInUnderTwo() {
        #expect(ComposedStyle.weepAmount(age: 0.25) == 0 && ComposedStyle.weepAmount(age: 0.1) == 0)
        #expect(abs(ComposedStyle.weepAmount(age: 1.05) - 0.5) < 1e-9)
        #expect(ComposedStyle.weepAmount(age: 1.85) == 1 && ComposedStyle.weepAmount(age: 30) == 1)
    }

    /// 每個字的正下方拖出三份越來越淡的副本，等距排開；間距隨該字停留的時間從 0 拉到 0.1 字級。剛進場時沒有。
    /// 字照行長分散出現（最後一個字到行尾前才出來），所以每個字各自驗「三份等距」，另驗有字已經拉到最開
    @Test func weepTrailsThreeFadingCopiesBelowEachSettledGlyph() {
        let settled = plan(29.5, fx1: "weep")
        #expect(!settled.glyphs.isEmpty && settled.ghosts.count == settled.glyphs.count * ComposedStyle.weepCopies)
        var fullyOpen = 0
        for glyph in settled.glyphs {
            // 折行後上下兩列可能有同字同 x：只取落在這個字下方 0.3 字級內的
            let reach = glyph.fontSize * ComposedStyle.weepStep * CGFloat(ComposedStyle.weepCopies)
            let copies = settled.ghosts
                .filter { $0.text == glyph.text && abs($0.origin.x - glyph.origin.x) < 1e-6 && $0.origin.y > glyph.origin.y && $0.origin.y <= glyph.origin.y + reach + 1e-6 }
                .sorted { $0.origin.y < $1.origin.y }
            guard copies.count == ComposedStyle.weepCopies else { Issue.record("\(glyph.text) 下方有 \(copies.count) 份副本"); continue }
            let gap = copies[0].origin.y - glyph.origin.y
            #expect(gap > 0 && gap <= glyph.fontSize * ComposedStyle.weepStep + 1e-6, "\(glyph.text) 第一份往下 \(gap)")
            if abs(gap - glyph.fontSize * ComposedStyle.weepStep) < 1e-6 { fullyOpen += 1 }
            for (index, copy) in copies.enumerated() {
                #expect(copy.color == .fg && abs((copy.origin.y - glyph.origin.y) - gap * CGFloat(index + 1)) < 1e-6, "\(glyph.text) 第 \(index + 1) 份不等距")
                #expect(abs(copy.opacity - glyph.opacity * ComposedStyle.weepOpacity(level: index + 1)) < 1e-9)
            }
        }
        #expect(fullyOpen >= settled.glyphs.count / 2, "停滿的字應已拉到 0.1 字級")
        #expect(plan(2.05, fx1: "weep").ghosts.isEmpty)
        #expect(plan(29.5).ghosts.isEmpty)
    }

    /// 同一層的副本排在一起，繪製端一層只填一次（批 3 RGB 分離的教訓）
    @Test func weepCopiesAreGroupedByLayerSoEachLayerFillsOnce() {
        #expect(LyricsFXCanvas.runs(of: plan(29.5, fx1: "weep").ghosts).count == ComposedStyle.weepCopies)
    }

    /// 燭火閃爍讓每個字各自明滅，副本的透明度逐字不同；仍照量化階排在一起，填色次數＝出現的階數，不隨字數增加
    @Test func weepStaysAFewFillsEvenWhenEveryGlyphFlickersOnItsOwn() {
        for t in [12.0, 20.3, 29.5] {
            let ghosts = plan(t, fx1: "weep", fx2: "flicker").ghosts
            let levels = Set(ghosts.map { LyricsFXCanvas.opacityLevel($0.opacity) }).subtracting([0])
            #expect(!ghosts.isEmpty && LyricsFXCanvas.runs(of: ghosts).count == levels.count, "t=\(t)")
        }
        #expect(Set(plan(20.3, fx1: "weep", fx2: "flicker").glyphs.map(\.opacity)).count > 1, "前提：閃爍時各字透明度不同")
    }
}

// B2 批 4 計劃 T6：對照組——性格相反的團不會抽到對方的東西
@Suite("B2 batch 4 contrasts")
struct B2BatchFourContrastTests {
    /// 同一團連抽 400 次（帶「排除上一次」）用到的所有元件
    private func drawn(_ artist: String) -> Set<String> {
        guard case .profile(let profile) = SongProfileResolver.resolve(artist: artist, genre: nil) else {
            Issue.record("\(artist) 不在覆寫表"); return []
        }
        var ids: Set<String> = []
        var previous: ComposedRecipe?
        for seed in 1...400 as ClosedRange<UInt64> {
            guard case .composed(let recipe) = Composer.compose(profile: profile, seed: seed, avoiding: previous) else {
                Issue.record("\(artist) 抽到 mono"); break
            }
            ids.formUnion(recipe.componentIDs)
            previous = recipe
        }
        return ids
    }

    @Test func theTheatricalBandAndTheFastDryBandShareNothingButTheEmptyDefaults() {
        let myChemicalRomance = drawn("My Chemical Romance"), theStorySoFar = drawn("The Story So Far")
        #expect(myChemicalRomance.isSuperset(of: ["IMFell", "rain", "scrawl", "sink", "wither", "weep", "revenge", "parade"]))
        #expect(theStorySoFar.isSuperset(of: ["Marker", "gig", "punch", "rip", "speedlines", "skateTeal"]))
        #expect(myChemicalRomance.intersection(theStorySoFar).isSubset(of: ["none", "void", "mallPink"]))
    }

    @Test func theScreamingBandAndTheQuietBandKeepTheirOwnMotion() {
        let theUsed = drawn("The Used"), deathCab = drawn("Death Cab for Cutie")
        #expect(theUsed.isSuperset(of: ["RockSalt", "xerox", "lurch", "cut", "shake", "revenge"]))
        #expect(deathCab.isSuperset(of: ["CourierPrime", "bluehour", "fadeUp", "fadeShort", "breathe", "overcast"]))
        #expect(theUsed.isDisjoint(with: ["fadeUp", "bloom", "ease", "breathe", "overcast", "Grotesk", "Gochi", "CormorantIt"]))
        #expect(deathCab.isDisjoint(with: ["RockSalt", "IMFell", "lurch", "scrawl", "cut", "rip", "shake", "jitter", "weep", "revenge", "parade"]))
    }

    /// 合作寫法使用者沒指定歸屬：不套兩團的任何一個（對照檔 `unassigned`）
    @Test func theCollaborationSpellingStaysUnassigned() {
        #expect(SongProfileResolver.resolve(artist: "The Used & My Chemical Romance", genre: "Alternative") == .mono)
    }
}
