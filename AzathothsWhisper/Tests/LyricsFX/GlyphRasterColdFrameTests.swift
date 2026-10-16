import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// 計劃 2026-10-16 §3 V1b：點陣快取清空（或換 displayScale）後的第一幀＝整幀所有字都要重建點陣，最壞也不能超過一格（8.3 ms）。
// 量的是和 LyricsFXFrameMeter 同一個區間（plan＋Canvas 編碼）。只在 -O 量測建置、帶 AZW_PERF=1 時跑（Debug 的時間沒有意義）：
// TEST_RUNNER_AZW_PERF=1 xcodebuild test ... SWIFT_OPTIMIZATION_LEVEL=-O -only-testing:AzathothsWhisperTests/GlyphRasterColdFrameTests
@MainActor
@Suite("Glyph raster cold frame", .enabled(if: ProcessInfo.processInfo.environment["AZW_PERF"] == "1"))
struct GlyphRasterColdFrameTests {
    static let budget: Duration = .microseconds(8_300)
    static let runs = 10
    static let profile = SongProfile(axes: [.theatrical: 0.9, .aggression: 0.6], tags: [.emo])

    @Test(arguments: [
        ["RockSalt", "bluehour", "lurch", "wither", "weep", "jitter", "revenge"],
        ["Catacombs", "snow", "smoke", "dissolve", "misreg", "shake", "ice"],
    ])
    func aFrameAfterTheRasterCacheIsClearedStaysWithinOneRefresh(_ ids: [String]) throws {
        let recipe = SessionRecipe.composed(ComposedRecipe(font: ids[0], backdrop: ids[1], enter: ids[2], exit: ids[3], fx1: ids[4], fx2: ids[5], palette: ids[6], seed: 7, profile: Self.profile))
        let timeline = try #require(LyricsTimelineBuilder.build(lyrics: LyricsFXPreviewFixture.denseLyrics, duration: LyricsFXPreviewFixture.duration))
        let measurer = CoreTextMeasurer()
        let paths = GlyphPathCache()
        var samples: [Duration] = []
        var glyphCount = 0
        for run in 0...Self.runs {
            // 第 0 次暖外框與量測快取（清空點陣不會清它們），只計後面 10 次
            paths.rasters.removeAll()
            var elapsed: Duration = .zero
            let view = Canvas { context, size in
                let started = ContinuousClock.now
                let plan = LyricsFXFrame.plan(timeline: timeline, time: 4, size: size, motion: .full, recipe: recipe, measurer: measurer)
                LyricsFXCanvas.draw(plan, in: context, size: size, paths: paths)
                elapsed = ContinuousClock.now - started
                glyphCount = plan.glyphs.count + plan.ghosts.count
            }
            .frame(width: LyricsFXPreviewArtifactTests.canvas.width, height: LyricsFXPreviewArtifactTests.canvas.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            _ = renderer.cgImage
            if run > 0 { samples.append(elapsed) }
        }
        let worst = try #require(samples.max())
        let line = "\(ids[0]) cold-frame max \(worst) over \(samples.count) runs, glyphs+ghosts \(glyphCount), misses \(paths.rasters.misses)"
        try line.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lyricsfx-coldframe-\(ids[0]).txt"), atomically: true, encoding: .utf8)
        #expect(glyphCount > 100, "量的是密集預覽的整幀")
        #expect(worst <= Self.budget, "\(line)")
    }
}
