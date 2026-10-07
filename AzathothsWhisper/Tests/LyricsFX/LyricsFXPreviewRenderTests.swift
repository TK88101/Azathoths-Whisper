import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// A2 計劃 §3.6：離屏把同一個 Canvas 繪製函式畫成圖。歌詞為編造句
@MainActor
@Suite("LyricsFX preview render")
struct LyricsFXPreviewRenderTests {
    static let size = CGSize(width: 900, height: 560)
    static let timeline = LyricsTimeline(
        lines: [TimedLine(start: 1, end: 4, text: "Paper boats at dawn", isChorus: false),
                TimedLine(start: 4, end: 8, text: "Quiet harbor", isChorus: false)],
        source: .embeddedLRC, duration: 60
    )

    static func image(
        time: Double?, motion: LyricsFXMotion = .full, timeline: LyricsTimeline? = timeline, size: CGSize = size, scale: CGFloat = 2
    ) -> CGImage? {
        let measurer = CoreTextMeasurer()
        let view = Canvas { context, size in
            let plan = LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: motion, measurer: measurer)
            LyricsFXCanvas.draw(plan, in: context, size: size, paths: GlyphPathCache())
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.background)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// 非背景（非純黑）像素數
    static func litPixels(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        return stride(from: 0, to: data.count, by: 4).filter { data[$0] > 24 || data[$0 + 1] > 24 || data[$0 + 2] > 24 }.count
    }

    @Test func theCanvasRendersOffscreenWithText() throws {
        let image = try #require(Self.image(time: 3))
        #expect(image.width == Int(Self.size.width * 2))
        #expect(Self.litPixels(image) > 2000)
    }

    @Test func anEmptyMomentRendersOnlyTheBackground() throws {
        let image = try #require(Self.image(time: 30))
        #expect(Self.litPixels(image) == 0)
    }
}

// 定格圖與 6 秒 GIF：寫到暫存目錄給人看（A2 計劃 §3.6）。產物路徑寫進 `paths.txt`
@MainActor
@Suite("LyricsFX preview artifacts")
struct LyricsFXPreviewArtifactTests {
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-lyricsfx-preview")
    static var timeline: LyricsTimeline? {
        LyricsTimelineBuilder.build(lyrics: LyricsFXPreviewFixture.lyrics, duration: LyricsFXPreviewFixture.duration)
    }

    /// 升起層在預設視窗下的畫布：寬 1200、高 800 − 標題列與 footer（約 150）
    static let canvas = CGSize(width: 1200, height: 650)

    @Test func theFixtureIsAnEmbeddedLRCTimeline() throws {
        let timeline = try #require(Self.timeline)
        #expect(timeline.source == .embeddedLRC)
        #expect(timeline.lines.count == 9)
    }

    /// 壓力歌詞在預設畫布上恰好畫出 200 個字（Codex R1 #2：是「畫出 200」，不是「輸入 200」）
    @Test func theDenseFixtureDrawsExactly200Glyphs() throws {
        let timeline = try #require(LyricsTimelineBuilder.build(lyrics: LyricsFXPreviewFixture.denseLyrics, duration: LyricsFXPreviewFixture.duration))
        let plan = LyricsFXFrame.plan(timeline: timeline, time: 2, size: Self.canvas, motion: .full, measurer: CoreTextMeasurer())
        #expect(plan.glyphs.count == 200)
    }

    @Test func writesStillsAndAShortGIF() throws {
        let timeline = try #require(Self.timeline)
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let stills: [(String, Double, LyricsFXMotion)] = [
            ("1-enter", 2.12, .full), ("2-hold", 3.5, .full), ("3-change", 5.62, .full),
            ("4-interlude-preview", 14, .full), ("5-cjk", 20, .full), ("6-long-line", 25, .full), ("7-reduced", 5.62, .reduced),
        ]
        var written: [String] = []
        for (name, time, motion) in stills {
            let image = try #require(LyricsFXPreviewRenderTests.image(time: time, motion: motion, timeline: timeline, size: Self.canvas))
            #expect(LyricsFXPreviewRenderTests.litPixels(image) > 1000, "\(name) 有字")
            written.append(try PreviewImageWriter.png(image, to: Self.directory.appendingPathComponent("\(name).png")).path)
        }
        let frames = try (0..<120).map { index in
            try #require(LyricsFXPreviewRenderTests.image(time: 3 + Double(index) * 0.05, timeline: timeline, size: Self.canvas, scale: 1))
        }
        written.append(try PreviewImageWriter.gif(frames, delay: 0.05, to: Self.directory.appendingPathComponent("mono-6s.gif")).path)
        try written.joined(separator: "\n").write(to: Self.directory.appendingPathComponent("paths.txt"), atomically: true, encoding: .utf8)
    }
}
