import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// 點陣畫法和改版前的合併外框畫法逐像素比（docs/plans/2026-10-16-lyrics-fx-glyph-raster-cache.md §3 V3）。
// 門檻取自 spike 的逐案實測最差值，綁定本機環境；轉紅時不得放寬（見計劃）。歌詞為編造句
@MainActor
@Suite("Glyph raster fidelity", .serialized)
struct GlyphRasterFidelityTests {
    struct Limits {
        let mean: Double
        let over2: Double
        let over16: Double
        let maxDiff: Int
    }

    struct Stats {
        var mean = 0.0, over2 = 0.0, over16 = 0.0, outsideEdge = 0.0
        var maxDiff = 0, outsideEdgeMax = 0
    }

    static let size = CGSize(width: 900, height: 560)
    /// 實際全螢幕（內建螢幕 1728×945 pt；一般字 em≈113 pt、Anton≈142 pt）——計劃 2026-10-17 全螢幕缺口 §3.1
    nonisolated static let fullscreen = CGSize(width: 1728, height: 945)
    static let times: [Double] = [2.4, 4.6, 5.7, 9.3, 20.5, 24.0]
    static let limits: [CGFloat: Limits] = [
        2: Limits(mean: 0.0007, over2: 0.015, over16: 0.004, maxDiff: 96),
        1: Limits(mean: 0.0013, over2: 0.023, over16: 0.0075, maxDiff: 96),
    ]
    /// 邊緣帶外：差 > 16/255 的像素占比與最大差（擋住字內部的內容錯誤）
    static let outsideEdgeShare = 0.00001
    static let outsideEdgeMax = 48
    static let profile = SongProfile(axes: [.theatrical: 0.9, .aggression: 0.6], tags: [.emo])
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lyricsfx-fidelity", isDirectory: true)

    /// 每幀量測的 7 份＋整屏縮放＋mono＋光暈＋霓虹描邊（計劃 §3 V3）
    static let recipes: [String: [String]] = [
        "rocksalt": ["RockSalt", "bluehour", "lurch", "wither", "weep", "jitter", "revenge"],
        "imfell": ["IMFell", "bluehour", "scrawl", "sink", "weep", "flicker", "parade"],
        "courier": ["CourierPrime", "bluehour", "fadeUp", "sink", "breathe", "reflect", "overcast"],
        "shadows": ["ShadowsLight", "bluehour", "scrawl", "wither", "weep", "reflect", "bruise"],
        "marker": ["Marker", "bluehour", "lurch", "wither", "weep", "jitter", "revenge"],
        "catacombs": ["Catacombs", "snow", "smoke", "dissolve", "misreg", "shake", "ice"],
        "elite": ["Elite", "scan", "drop", "bands", "rgbsplit", "shake", "acid"],
        "thump": ["Anton", "void", "fadeUp", "sink", "thump", "jitter", "revenge"],
        "glow": ["Cinzel", "shafts", "smoke", "fade", "breathe", "glow", "goldNavy"],
        "neonstroke": ["Bungee", "void", "fadeUp", "sink", "neonstroke", "none", "revenge"],
        // Anton 的每幀量測配方（批 4 遺留 §9.2）：大字＋旋轉＋整屏縮放、半透明副本多字
        "antonlp": ["Anton", "scan", "stamp", "scatter", "rgbsplit", "thump", "acid"],
        "antonsk": ["Anton", "smokeHaze", "drop", "fall", "misreg", "shake", "ampRed"],
        "mono": [],
    ]

    static func recipe(_ name: String) -> SessionRecipe {
        guard let ids = recipes[name], ids.count == 7 else { return .mono }
        return .composed(ComposedRecipe(font: ids[0], backdrop: ids[1], enter: ids[2], exit: ids[3], fx1: ids[4], fx2: ids[5], palette: ids[6], seed: 7, profile: profile))
    }

    static func image(_ recipe: SessionRecipe, time: Double, scale: CGFloat, rendering: LyricsFXCanvas.GlyphRendering, size: CGSize = size) -> CGImage? {
        let measurer = CoreTextMeasurer()
        let paths = GlyphPathCache()
        let timeline = LyricsTimelineBuilder.build(lyrics: LyricsFXPreviewFixture.lyrics, duration: LyricsFXPreviewFixture.duration)
        let view = Canvas { context, size in
            let plan = LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: .full, recipe: recipe, measurer: measurer)
            LyricsFXCanvas.draw(plan, in: context, size: size, paths: paths, rendering: rendering)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// sRGB、RGBA8 premultiplied
    static func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    /// 比 RGB 三通道；「邊緣帶」＝參考圖 5×5 鄰域內有亮度差 > 16/255 的像素
    static func compare(_ reference: [UInt8], _ candidate: [UInt8], width: Int, height: Int) -> Stats {
        var stats = Stats()
        var sum = 0, over2 = 0, over16 = 0, outside = 0
        reference.withUnsafeBufferPointer { a in
            candidate.withUnsafeBufferPointer { b in
                func luma(_ x: Int, _ y: Int) -> Int {
                    let i = (y * width + x) * 4
                    return (Int(a[i]) + Int(a[i + 1]) + Int(a[i + 2])) / 3
                }
                let rowBytes = width * 4
                for y in 0..<height {
                    // 整列相同就沒有差可算（背景與沒受影響的字都是逐像素相同）；統計結果不變，只省 Debug 下的時間
                    if memcmp(a.baseAddress! + y * rowBytes, b.baseAddress! + y * rowBytes, rowBytes) == 0 { continue }
                    for x in 0..<width {
                        let i = (y * width + x) * 4
                        var worst = 0
                        for c in 0..<3 {
                            let d = abs(Int(a[i + c]) - Int(b[i + c]))
                            sum += d
                            worst = max(worst, d)
                            if d > 2 { over2 += 1 }
                            if d > 16 { over16 += 1 }
                        }
                        stats.maxDiff = max(stats.maxDiff, worst)
                        guard worst > 16 else { continue }
                        let center = luma(x, y)
                        var onEdge = false
                        for dy in -2...2 where !onEdge {
                            for dx in -2...2 {
                                let xx = x + dx, yy = y + dy
                                if xx >= 0, yy >= 0, xx < width, yy < height, abs(luma(xx, yy) - center) > 16 { onEdge = true; break }
                            }
                        }
                        if !onEdge {
                            outside += 1
                            stats.outsideEdgeMax = max(stats.outsideEdgeMax, worst)
                        }
                    }
                }
            }
        }
        let channels = Double(width * height * 3)
        stats.mean = Double(sum) / channels / 255
        stats.over2 = Double(over2) / channels
        stats.over16 = Double(over16) / channels
        stats.outsideEdge = Double(outside) / Double(width * height)
        return stats
    }

    /// 診斷（不設門檻）：參考、點陣、差異熱圖（差 × 4）
    static func writeDiagnostics(name: String, reference: CGImage, candidate: CGImage, a: [UInt8], b: [UInt8]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PreviewImageWriter.png(reference, to: directory.appendingPathComponent("\(name)-reference.png"))
        try PreviewImageWriter.png(candidate, to: directory.appendingPathComponent("\(name)-raster.png"))
        var heat = [UInt8](repeating: 255, count: a.count)
        for i in stride(from: 0, to: a.count, by: 4) {
            let d = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
            let v = UInt8(min(255, d * 4))
            heat[i] = v; heat[i + 1] = 0; heat[i + 2] = 0
        }
        let width = reference.width, height = reference.height
        let image = heat.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        if let image { try PreviewImageWriter.png(image, to: directory.appendingPathComponent("\(name)-heat.png")) }
    }

    /// 一份配方 × 6 個時刻 × 一種 scale：judged＝照門檻判，否則只記錄；回傳逐案報告，最差一案輸出熱圖
    static func check(_ name: String, size: CGSize, scale: CGFloat, rendering: LyricsFXCanvas.GlyphRendering, judged: Bool, prefix: String = "") throws -> [String] {
        let recipe = Self.recipe(name)
        let limits = try #require(Self.limits[scale])
        var report: [String] = []
        var worst: (stats: Stats, time: Double, a: [UInt8], b: [UInt8], ra: CGImage?, rb: CGImage?) = (Stats(), 0, [], [], nil, nil)
        for time in Self.times {
            let reference = try #require(Self.image(recipe, time: time, scale: scale, rendering: .vectorReference, size: size))
            let candidate = try #require(Self.image(recipe, time: time, scale: scale, rendering: rendering, size: size))
            let a = Self.pixels(reference), b = Self.pixels(candidate)
            let stats = Self.compare(a, b, width: reference.width, height: reference.height)
            let label = "\(prefix)\(name)@\(time) \(Int(scale))x"
            if judged {
                #expect(stats.mean <= limits.mean, "\(label) 平均差 \(stats.mean)")
                #expect(stats.over2 <= limits.over2, "\(label) 差>2 占比 \(stats.over2)")
                #expect(stats.over16 <= limits.over16, "\(label) 差>16 占比 \(stats.over16)")
                #expect(stats.maxDiff <= limits.maxDiff, "\(label) 最大差 \(stats.maxDiff)")
                #expect(stats.outsideEdge <= Self.outsideEdgeShare, "\(label) 邊緣帶外差>16 占比 \(stats.outsideEdge)")
                #expect(stats.outsideEdgeMax <= Self.outsideEdgeMax, "\(label) 邊緣帶外最大差 \(stats.outsideEdgeMax)")
            }
            report.append(String(format: "%@%@ mean=%.5f over2=%.3f%% over16=%.3f%% max=%d outside=%.4f%% outsideMax=%d",
                                 label, judged ? "" : " (記錄)", stats.mean, stats.over2 * 100, stats.over16 * 100, stats.maxDiff, stats.outsideEdge * 100, stats.outsideEdgeMax))
            if stats.over16 >= worst.stats.over16 { worst = (stats, time, a, b, reference, candidate) }
        }
        if let ra = worst.ra, let rb = worst.rb {
            try Self.writeDiagnostics(name: "\(prefix)\(name)-\(worst.time)-\(Int(scale))x", reference: ra, candidate: rb, a: worst.a, b: worst.b)
        }
        return report
    }

    static func writeReport(_ lines: [String], name: String) throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: Self.directory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }

    /// 這份配方在 6 個時刻實際用到的變換（確認案例涵蓋大字、旋轉、整屏縮放、半透明多字）
    static func transformSummary(_ name: String, size: CGSize) -> String {
        let measurer = CoreTextMeasurer()
        let timeline = LyricsTimelineBuilder.build(lyrics: LyricsFXPreviewFixture.lyrics, duration: LyricsFXPreviewFixture.duration)
        var rotation: CGFloat = 0, minScale = CGFloat.infinity, maxScale: CGFloat = 0, zoom: CGFloat = 1, effective: CGFloat = 0, grouped = 0
        for time in Self.times {
            let plan = LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: .full, recipe: Self.recipe(name), measurer: measurer)
            zoom = max(zoom, plan.zoom)
            for glyph in plan.glyphs + plan.ghosts {
                rotation = max(rotation, abs(glyph.rotation))
                minScale = min(minScale, glyph.scaleX, glyph.scaleY)
                maxScale = max(maxScale, glyph.scaleX, glyph.scaleY)
                effective = max(effective, glyph.fontSize * max(glyph.scaleX, glyph.scaleY) * plan.zoom)
            }
            grouped += LyricsFXCanvas.runs(of: plan.ghosts).filter { $0.level < LyricsFXCanvas.opacityLevels && $0.range.count > 1 }.count
            grouped += LyricsFXCanvas.runs(of: plan.glyphs, stroking: true).filter { $0.level < LyricsFXCanvas.opacityLevels && $0.range.count > 1 }.count
        }
        return String(format: "%@ 變換：max|rot|=%.3f scale=%.3f…%.3f zoom≤%.3f 最大有效字級=%.1f pt 半透明多字 run=%d", name, rotation, minScale, maxScale, zoom, effective, grouped)
    }

    @Test(arguments: ["rocksalt", "imfell", "courier", "shadows", "marker", "catacombs", "elite", "thump", "glow", "mono"])
    func theRasterDrawingLooksLikeTheMergedOutlineDrawing(_ name: String) throws {
        var report: [String] = []
        for scale in [CGFloat(2), 1] {
            report += try Self.check(name, size: Self.size, scale: scale, rendering: .raster, judged: true)
        }
        try Self.writeReport(report, name: name)
    }

    /// 實際全螢幕字級（計劃 2026-10-17 全螢幕缺口 §3.1）：Anton 也強制走點陣；2× 照同一組門檻判（內建螢幕是 2×），1× 只記錄（這個尺寸的 1× 不會出現）
    @Test(arguments: ["rocksalt", "imfell", "courier", "shadows", "marker", "catacombs", "elite", "glow", "mono", "thump", "antonlp", "antonsk"])
    func theRasterDrawingHoldsAtTheRealFullScreenSize(_ name: String) throws {
        var report = [Self.transformSummary(name, size: Self.fullscreen)]
        report += try Self.check(name, size: Self.fullscreen, scale: 2, rendering: .rasterIgnoringOptOut, judged: true, prefix: "full-")
        report += try Self.check(name, size: Self.fullscreen, scale: 1, rendering: .rasterIgnoringOptOut, judged: false, prefix: "full-")
        try Self.writeReport(report, name: "full-\(name)")
    }

    /// 霓虹描邊走合併外框（描邊要路徑）→ 和參考畫法同一條路，必須逐像素相同
    @Test func neonStrokeStillDrawsTheMergedOutlinePixelForPixel() throws {
        let recipe = Self.recipe("neonstroke")
        for scale in [CGFloat(2), 1] {
            for time in Self.times {
                let reference = try #require(Self.image(recipe, time: time, scale: scale, rendering: .vectorReference))
                let candidate = try #require(Self.image(recipe, time: time, scale: scale, rendering: .raster))
                #expect(Self.pixels(reference) == Self.pixels(candidate), "neonstroke@\(time) \(Int(scale))x")
            }
        }
    }
}

@Suite("Glyph run strategy")
struct GlyphRunStrategyTests {
    @Test func aStrokedRunKeepsTheMergedOutline() {
        #expect(LyricsFXCanvas.glyphRunStrategy(level: 20, count: 5, stroke: 2) == .vectorMerged)
        #expect(LyricsFXCanvas.glyphRunStrategy(level: 7, count: 1, stroke: 0.5) == .vectorMerged)
    }

    @Test func aTranslucentRunOfSeveralGlyphsIsGroupedSoOverlapsDoNotDarken() {
        #expect(LyricsFXCanvas.glyphRunStrategy(level: 19, count: 2, stroke: 0) == .rasterGrouped)
        #expect(LyricsFXCanvas.glyphRunStrategy(level: 1, count: 40, stroke: 0) == .rasterGrouped)
    }

    @Test func anOpaqueRunOrASingleGlyphIsStampedDirectly() {
        #expect(LyricsFXCanvas.glyphRunStrategy(level: LyricsFXCanvas.opacityLevels, count: 40, stroke: 0) == .rasterDirect)
        #expect(LyricsFXCanvas.glyphRunStrategy(level: 5, count: 1, stroke: 0) == .rasterDirect)
    }
}
