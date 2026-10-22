import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// ⑤ 中日韓字型計劃 §7 風險①：中日文每一句都有新字（字種遠多於拉丁），沿用 I-46 的「一格 8.3 ms」門檻量兩種情境：
// 完全冷（量測、外框、點陣快取全清）的密集日文整幀；以及一首不重複字 ≥ 400 的歌、快取照常延續時每句剛出現的那一幀。
// 只在 -O 量測建置、帶 AZW_PERF=1 時跑：TEST_RUNNER_AZW_PERF=1 xcodebuild test ... SWIFT_OPTIMIZATION_LEVEL=-O。歌詞為編造的字串（不是真歌詞）
@MainActor
@Suite("Glyph raster CJK cold frame", .enabled(if: ProcessInfo.processInfo.environment["AZW_PERF"] == "1"))
struct GlyphRasterCJKColdFrameTests {
    static let budget: Duration = .microseconds(8_300)
    static let runs = 10

    /// 編造的字池（常用漢字＋假名），每句取不同的一段，確保每句都是新字
    static let pool = Array(
        "夜明灯籠川流港静鐘鳴舟朝待空海風雨雪花月星光影声心時間夢道路街橋森山島雲火水土金銀赤青白黒今日明昨春夏秋冬東西南北上下左右前後内外"
        + "高低長短遠近新古早遅強弱多少大小深浅重軽熱冷暖涼甘苦辛酸美醜善悪真偽正誤生死始終開閉出入去来行帰見聞言話読書歌舞笑泣怒喜愛憎望願祈"
        + "城町村森林野原畑田池湖沼泉滝谷峰岬浜岸波潮砂石岩鉄銅玉珠宝鏡窓扉壁床屋根柱階段庭門塔寺社宮殿館駅港船車馬牛羊犬猫鳥魚虫草木竹松梅桜"
        + "紅緑紫黄灰茶桃橙藍翠碧鋼針糸布紙筆墨絵色音楽琴笛鼓詩句章節頁巻冊箱袋瓶杯皿鍋釜刀剣弓矢盾旗灯炎煙霧霞虹露霜氷雷嵐吹雲晴曇陰陽表裏"
        + "医院薬病痛治療健康体頭顔目耳鼻口歯首肩腕手指胸腹背腰足膝骨肉血汗涙息命魂精神気力意志感情思考記憶知識学問教育研究実験科理数式計算"
        + "政治経済社会文化歴史地理国家民族世界平和戦争勝負争競技試合選手監督審判観客応援拍手歓迎祝賀式典儀礼祭礼宴会食事料理飯麺肉菜果実酒茶"
        + "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんアイウエオカキクケコサシスセソタチツテト"
    )

    static func song(lines count: Int, perLine: Int) -> LyricsTimeline {
        let lines = (0..<count).map { index -> TimedLine in
            let start = (index * perLine) % (pool.count - perLine)
            return TimedLine(start: Double(index) * 4 + 1, end: Double(index) * 4 + 5, text: String(pool[start..<start + perLine]), isChorus: false)
        }
        return LyricsTimeline(lines: lines, source: .embeddedLRC, duration: Double(count) * 4 + 10)
    }

    private func frameTime(_ timeline: LyricsTimeline, time: Double, recipe: SessionRecipe, canvas: CGSize, measurer: CoreTextMeasurer, paths: GlyphPathCache) -> (Duration, Int) {
        var elapsed: Duration = .zero
        var glyphs = 0
        let view = Canvas { context, size in
            let started = ContinuousClock.now
            let plan = LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: .full, recipe: recipe, measurer: measurer)
            LyricsFXCanvas.draw(plan, in: context, size: size, paths: paths)
            elapsed = ContinuousClock.now - started
            glyphs = plan.glyphs.count + plan.ghosts.count + plan.unlit.count
        }
        .frame(width: canvas.width, height: canvas.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        _ = renderer.cgImage
        return (elapsed, glyphs)
    }

    private func report(_ name: String, _ line: String) {
        try? line.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lyricsfx-cjk-coldframe-\(name).txt"), atomically: true, encoding: .utf8)
    }

    @Test(arguments: ["rocksalt", "catacombs", "marker"], [CGSize(width: 900, height: 560), GlyphRasterFidelityTests.fullscreen])
    func aFullyColdJapaneseFrameStaysWithinOneRefresh(_ name: String, canvas: CGSize) throws {
        let timeline = Self.song(lines: 3, perLine: 24)
        var samples: [Duration] = []
        var glyphCount = 0
        for _ in 0..<Self.runs {
            let (elapsed, glyphs) = frameTime(timeline, time: 4.6, recipe: GlyphRasterFidelityTests.recipe(name), canvas: canvas, measurer: CoreTextMeasurer(), paths: GlyphPathCache())
            samples.append(elapsed)
            glyphCount = glyphs
        }
        let worst = try #require(samples.max())
        let line = "\(name) \(Int(canvas.width))x\(Int(canvas.height)) fully-cold JA max \(worst) over \(samples.count) runs, glyphs \(glyphCount), samples(ms) "
            + samples.map { String(format: "%.2f", Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000) }.joined(separator: ",")
        report("\(name)-\(Int(canvas.width))-cold", line)
        #expect(glyphCount >= 24, "量的是一整句日文")
        #expect(worst <= Self.budget, "\(line)")
    }

    @Test(arguments: ["rocksalt", "catacombs"])
    func eachNewJapaneseLineStaysWithinOneRefreshAcrossASong(_ name: String) throws {
        let timeline = Self.song(lines: 30, perLine: 18)
        let unique = Set(timeline.lines.flatMap { Array($0.text) }).count
        let measurer = CoreTextMeasurer()
        let paths = GlyphPathCache()
        let canvas = GlyphRasterFidelityTests.fullscreen
        var worst: Duration = .zero
        for line in timeline.lines {
            for offset in [0.02, 0.3, 1.0] {
                worst = max(worst, frameTime(timeline, time: line.start + offset, recipe: GlyphRasterFidelityTests.recipe(name), canvas: canvas, measurer: measurer, paths: paths).0)
            }
        }
        let summary = "\(name) song unique \(unique) worst \(worst) misses \(paths.rasters.misses) bytes \(paths.rasters.bytes)"
        report("\(name)-song", summary)
        #expect(unique >= 400)
        #expect(worst <= Self.budget, "\(summary)")
    }
}
