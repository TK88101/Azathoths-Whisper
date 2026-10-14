import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// 批 4 T7 回饋修正（docs/plans/2026-10-14-lyrics-fx-b2-batch4-t7-fixes.md）：Rock Salt 出框、拿掉雨絲、暈開減量、倒影調淡。
// 歌詞為編造句
@MainActor
@Suite("B2 batch 4 T7 fixes")
struct B2BatchFourT7FixTests {
    /// 內建螢幕上 app 視窗的歌詞區（約 1728×945 點）
    static let size = CGSize(width: 1728, height: 945)
    static let line = "Lanterns over water, salt along the rope, gulls above the ferry, bells across the bay, and paper boats beside the pier tonight"
    static let timeline = LyricsTimeline(lines: [TimedLine(start: 2, end: 30, text: line, isChorus: false)], source: .embeddedLRC, duration: 60)
    static let profile = SongProfile(axes: [.theatrical: 0.9, .aggression: 0.6], tags: [.emo])

    private func plan(font: String, _ t: Double = 29.5, fx1: String = "none") -> FramePlan {
        let recipe = ComposedRecipe(font: font, backdrop: "void", enter: "fadeUp", exit: "sink", fx1: fx1, fx2: "none", palette: "revenge", seed: 3, profile: Self.profile)
        return LyricsFXFrame.plan(timeline: Self.timeline, time: t, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: CoreTextMeasurer())
    }

    /// 每個字實際墨跡的上下緣（用 app 的真實字形外框；旋轉小，另留 2% 邊）
    private func inkSpan(_ frame: FramePlan) -> (top: CGFloat, bottom: CGFloat) {
        let paths = GlyphPathCache()
        var top = CGFloat.infinity, bottom = -CGFloat.infinity
        for glyph in frame.glyphs {
            let entry = paths.entry(for: glyph)
            let box = entry.path.boundingBoxOfPath
            let scale = glyph.fontSize / entry.size * max(abs(glyph.scaleY), 1)
            top = min(top, glyph.origin.y + box.minY * scale)
            bottom = max(bottom, glyph.origin.y + box.maxY * scale)
        }
        return (top, bottom)
    }

    @Test func rockSaltIsDrawnAtThePrototypesSmallerSizeAndOtherFontsAreNot() throws {
        let rockSalt = try #require(LyricsFXCatalog.component("RockSalt"))
        guard case .font(let face) = rockSalt.payload else { Issue.record("RockSalt 不是字型"); return }
        #expect(abs(face.sizeScale - 0.085 / 0.12) < 1e-9)
        for id in ["IMFell", "ShadowsLight", "CourierPrime", "Anton"] {
            guard case .font(let other)? = LyricsFXCatalog.component(id)?.payload else { Issue.record("\(id) 不是字型"); continue }
            #expect(other.sizeScale == 1, "\(id)")
        }
    }

    /// 使用者 T7：「字體被砍掉了、沒有顯示全」——長句折行後，Rock Salt 的每個字都要完整落在歌詞區內、且至少兩列
    @Test func aLongRockSaltLineStaysInsideTheLyricsArea() {
        let frame = plan(font: "RockSalt")
        let span = inkSpan(frame)
        let margin = Self.size.height * 0.02
        #expect(span.top >= margin && span.bottom <= Self.size.height - margin, "墨跡 \(span.top)…\(span.bottom)／高 \(Self.size.height)")
        // 以實際列高分組（em 已乘 sizeScale），兩列的字至少差一列高的一半
        let rowHeight = Self.size.height * ComposedStyle.emRatio * (0.085 / 0.12) * ComposedStyle.lineHeight
        let ys = frame.glyphs.map(\.origin.y)
        #expect((ys.max() ?? 0) - (ys.min() ?? 0) >= rowHeight * 0.5)
    }

    /// 使用者 T7：「雨絲不要了」（三團候選不含 rain 由重產的簽字對照檔＋`B2BatchFourSignedFixtureTests` 把關）
    @Test func rainIsGoneFromTheCatalog() {
        #expect(LyricsFXCatalog.component("rain") == nil)
    }

    /// 使用者 T7：「層數減少一些，不要暈開那麼大」——兩份副本、最遠 0.12 字級
    @Test func weepLeavesTwoCopiesReachingAtMostTwelveHundredthsOfTheFontSize() {
        #expect(ComposedStyle.weepCopies == 2)
        let frame = plan(font: "CourierPrime", fx1: "weep")
        // 長句的最後幾個字剛出現、還沒開始暈開，所以只驗上限；「每字恰兩份」由 B2BatchFourEffectTests 的短句驗
        #expect(!frame.ghosts.isEmpty && frame.ghosts.count <= frame.glyphs.count * 2)
        let deepest = frame.glyphs.map { glyph in
            frame.ghosts.filter { $0.text == glyph.text && abs($0.origin.x - glyph.origin.x) < 1e-6 && $0.origin.y > glyph.origin.y }
                .map { ($0.origin.y - glyph.origin.y) / glyph.fontSize }
                .filter { $0 <= 0.5 }
                .max() ?? 0
        }
        #expect(deepest.allSatisfy { $0 <= 0.12 + 1e-9 } && deepest.contains { abs($0 - 0.12) < 1e-9 })
    }

    /// 使用者 T7：「讓這個倒影淡一些」——減半到 0.08（所有用倒影的團一起，使用者選 A）
    @Test func reflectionIsHalfAsStrongAsBefore() {
        let frame = plan(font: "CourierPrime", 5.5, fx1: "reflect")
        let mirrored = frame.ghosts.filter { $0.scaleY < 0 }
        #expect(!mirrored.isEmpty && mirrored.allSatisfy { $0.opacity <= 0.08 + 1e-9 })
        #expect(mirrored.contains { $0.opacity > 0.07 })
    }
}
