import CoreGraphics
import Foundation

@testable import AzathothsWhisper

/// 讀得到的檢查（docs/plans/2026-10-20-lyrics-fx-readability-gate.md §2）：只用 `LyricsFXFrame.plan` 的純資料，不繪製
enum ReadabilityAudit {
    static let size = CGSize(width: 960, height: 600)
    /// 看得見的字
    static let visibleOpacity = EnterTemplate.visibleAlpha
    /// G2：對象行唱歌中沒有任何看得見的主字，連續時間（含取樣刻度）上限
    static let maxBlank = 0.3
    /// G3：被蓋住一半以上的主字超過這個比例，算「疊住」
    static let coveredShare = 0.1
    static let coveredArea = 0.5
    static let maxCovered = 0.5
    /// 全程固定刻度：0.1 s 會把字輪流交疊的閃爍誤連成一段、也會漏掉（計劃 §6 的 0.01 s 實測）
    static let step = 0.02
    /// G3 豁免：從旁邊滑進來的字會短暫橫越鄰字；使用者看過改前改後選原樣（2026-10-20，ACCEPTANCE I-60）。只豁免 G3，G1／G2 照量
    static let coverExemptEnters: Set<String> = ["swagger", "slide"]
    /// G3：命中之間短於這個的空隙算連續（約為眼睛分不出閃爍的間隔）；G2 不接空隙——空白中短暫看得見字，就不算空白
    static let fusionGap = 0.1

    struct Finding: CustomStringConvertible {
        let line: Int
        let seconds: Double
        let at: Double
        var description: String { "第 \(line) 行 \(String(format: "%.2f", seconds)) s（約 \(String(format: "%.2f", at)) s 起）" }
    }

    /// 對象行的時刻表（以序號乘刻度，不累加，避免浮點誤差多出一格）
    static func samples(_ line: TimedLine) -> [(time: Double, step: Double)] {
        let count = Int(((line.revealEnd - line.start) / step).rounded(.up))
        return (0..<max(0, count)).map { (line.start + Double($0) * step, step) }
    }

    /// 只留對象行：其他行清成空白（空白行不畫），行號不變——排版與種子依行號，重新編號會換位置
    static func onlyLine(_ timeline: LyricsTimeline, _ index: Int) -> LyricsTimeline {
        let lines = timeline.lines.indices.map { i in
            i == index ? timeline.lines[i] : TimedLine(start: timeline.lines[i].start, end: timeline.lines[i].end, text: "", isChorus: false)
        }
        return LyricsTimeline(lines: lines, source: timeline.source, duration: timeline.duration)
    }

    static func plan(_ timeline: LyricsTimeline, time: Double, recipe: ComposedRecipe, measurer: any TextMeasuring) -> FramePlan {
        LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: .full, recipe: .composed(recipe), measurer: measurer)
    }

    static func isInk(_ glyph: GlyphDraw) -> Bool {
        glyph.opacity >= visibleOpacity && !glyph.text.allSatisfy(\.isWhitespace)
    }

    static func distance(_ a: GlyphDraw, _ b: GlyphDraw) -> CGFloat {
        hypot(a.origin.x - b.origin.x, a.origin.y - b.origin.y)
    }

    /// 對象行看得見的主字：本體（glyphs＋unlit），加上沒有本體的煙霧副本群（smoke 進場只畫 5 份淡副本）——
    /// 同字、彼此距離 0.3 字級以內的副本合成透明度 1−Π(1−a)，看得見就算一個字（以群裡第一份的位置）。
    /// 附近 0.5 字級內有同字本體的副本（錯位、分色、淚痕）是本體的效果，不另算。G2／G3 共用這一個定義
    static func targets(_ frame: FramePlan) -> [GlyphDraw] {
        let bodies = (frame.glyphs + frame.unlit).filter(isInk)
        // 倒影（scaleY < 0）是本體的效果、畫在遠處，不是煙霧
        let copies = frame.ghosts.filter { ghost in
            ghost.scaleY > 0 && !ghost.text.allSatisfy(\.isWhitespace) && !bodies.contains { $0.text == ghost.text && distance($0, ghost) < ghost.fontSize * 0.5 }
        }
        var claimed = Set<Int>()
        var clusters: [GlyphDraw] = []
        for (i, anchor) in copies.enumerated() where !claimed.contains(i) {
            let members = copies.indices.filter { !claimed.contains($0) && copies[$0].text == anchor.text && distance(copies[$0], anchor) < anchor.fontSize * 0.3 }
            let combined = 1 - members.reduce(1.0) { $0 * (1 - copies[$1].opacity) }
            guard combined >= visibleOpacity else { continue }
            claimed.formUnion(members)
            clusters.append(GlyphDraw(text: anchor.text, face: anchor.face, fontSize: anchor.fontSize, origin: anchor.origin, rotation: anchor.rotation,
                                      scaleX: anchor.scaleX, scaleY: anchor.scaleY, opacity: combined, color: anchor.color))
        }
        return bodies + clusters
    }

    /// 最長的連續命中：從段首到最後一次命中再加兩個刻度（該格本身＋保守上界，兩個取樣點之間可能還在持續）。
    /// 命中之間的空隙（未命中格數 × 刻度）短於 `bridging` 時接成同一段。G2／G3 共用
    static func longestRun(_ samples: [(hit: Bool, time: Double, step: Double)], bridging: Double = 0) -> (seconds: Double, at: Double)? {
        var worst: (seconds: Double, at: Double)?
        var runStart: Double?
        var gap = 0.0
        for sample in samples {
            guard sample.hit else {
                gap += sample.step
                if gap >= bridging - 1e-9 { runStart = nil }
                continue
            }
            gap = 0
            let start = runStart ?? sample.time
            runStart = start
            let seconds = sample.time - start + 2 * sample.step
            if seconds > (worst?.seconds ?? 0) + 1e-12 { worst = (seconds, start) }
        }
        return worst
    }

    /// 每一行各自量，回傳最長的一筆
    static func worstLine(_ timeline: LyricsTimeline, bridging: Double = 0, _ hit: (Int, Double) -> Bool) -> Finding? {
        timeline.lines.indices.filter { !timeline.lines[$0].text.allSatisfy(\.isWhitespace) }.compactMap { index -> Finding? in
            let run = longestRun(samples(timeline.lines[index]).map { (hit(index, $0.time), $0.time, $0.step) }, bridging: bridging)
            return run.map { Finding(line: index, seconds: $0.seconds, at: $0.at) }
        }.max { $0.seconds < $1.seconds }
    }

    /// G2：最長的「對象行沒有看得見主字」時間
    static func longestBlank(_ timeline: LyricsTimeline, recipe: ComposedRecipe, measurer: any TextMeasuring) -> Finding? {
        worstLine(timeline) { index, time in
            targets(plan(onlyLine(timeline, index), time: time, recipe: recipe, measurer: measurer)).isEmpty
        }
    }

    /// 字框：CoreText 實際字寬 ×（行盒高 × 0.8），左右內縮 8%；不含旋轉（近似）；翻轉（倒影）取絕對值，框不往上翻
    static func box(_ glyph: GlyphDraw, measurer: any TextMeasuring) -> CGRect {
        let width = (measurer.advances(of: glyph.text, face: glyph.face, fontSize: glyph.fontSize).last ?? glyph.fontSize * 0.5) * glyph.scaleX
        let height = (measurer.ascent(face: glyph.face, fontSize: glyph.fontSize) + measurer.descent(face: glyph.face, fontSize: glyph.fontSize)) * abs(glyph.scaleY) * 0.8
        return CGRect(x: glyph.origin.x, y: glyph.origin.y, width: width, height: height).insetBy(dx: width * 0.08, dy: 0)
    }

    /// 自己的殘影副本：殘影層裡同字、原點在半個字級以內
    static func isOwnCopy(_ other: GlyphDraw, of target: GlyphDraw) -> Bool {
        other.text == target.text && abs(other.origin.x - target.origin.x) < target.fontSize * 0.5 && abs(other.origin.y - target.origin.y) < target.fontSize * 0.5
    }

    /// 字層裡的自己：半個字級內、離主字最近的那一個同字（整個畫面的 plan 裡，自己的透明度可能因讓位不同，
    /// 位置也可能因隨機擺動共用亂數流而略有不同）；其他同字（相鄰的 ll）照算
    static func itself(of target: GlyphDraw, among bodies: [GlyphDraw]) -> Int? {
        bodies.indices.filter { bodies[$0].text == target.text && distance(bodies[$0], target) < target.fontSize * 0.5 }
            .min { distance(bodies[$0], target) < distance(bodies[$1], target) }
    }

    /// 對象行看得見的主字中，被畫面上其他看得見字形蓋住一半以上者的比例
    static func coveredFraction(target: [GlyphDraw], screen: FramePlan, measurer: any TextMeasuring) -> Double {
        let mains = target.filter(isInk)
        guard !mains.isEmpty else { return 0 }
        let bodies = (screen.glyphs + screen.unlit).filter(isInk)
        let ghosts = screen.ghosts.filter(isInk)
        let covered = mains.filter { main in
            let box = Self.box(main, measurer: measurer)
            let area = box.width * box.height
            guard area > 0 else { return false }
            let me = itself(of: main, among: bodies)
            let others = bodies.indices.filter { $0 != me }.map { bodies[$0] } + ghosts.filter { !isOwnCopy($0, of: main) }
            return others.contains { other in
                let overlap = box.intersection(Self.box(other, measurer: measurer))
                return !overlap.isNull && overlap.width * overlap.height / area > coveredArea
            }
        }
        return Double(covered.count) / Double(mains.count)
    }

    /// G3：最長的「對象行疊住」時間（取樣與 G2 同一張時刻表；短空隙接起來）
    static func longestCovered(_ timeline: LyricsTimeline, recipe: ComposedRecipe, measurer: any TextMeasuring) -> Finding? {
        worstLine(timeline, bridging: fusionGap) { index, time in
            let target = targets(plan(onlyLine(timeline, index), time: time, recipe: recipe, measurer: measurer))
            let screen = plan(timeline, time: time, recipe: recipe, measurer: measurer)
            return coveredFraction(target: target, screen: screen, measurer: measurer) > coveredShare
        }
    }

    /// 涵蓋：全部 profile（樂團表＋曲風列）
    static var profiles: [(name: String, profile: SongProfile)] {
        SongProfileResolver.bandTable.map { ($0.name, $0.profile) }
            + SongProfileResolver.keywordRows.compactMap { row in
                SongProfileResolver.compose(genre: row.keywords[0], rows: [row]).map { ("genre:\(row.keywords[0])", $0) }
            }
    }

    static let seeds = 6

    /// 同一首歌連播：每次排除上一次（與 VM 同一條規則）
    static func recipes(_ name: String, _ profile: SongProfile) -> [ComposedRecipe] {
        var previous: ComposedRecipe?
        return (0..<UInt64(seeds)).compactMap { seed in
            guard case .composed(let recipe) = Composer.compose(profile: profile, seed: FXHash.fnv1a64(name) ^ seed, avoiding: previous) else { return nil }
            previous = recipe
            return recipe
        }
    }

    /// 三份固定歌詞（全部編造）：英文預覽、日文、長句
    static var fixtures: [(name: String, timeline: LyricsTimeline)] {
        [
            ("en", LyricsTimelineBuilder.build(lyrics: LyricsFXPreviewFixture.lyrics, duration: LyricsFXPreviewFixture.duration)!),
            // ⑤ 中日韓字型計劃 §4.5：加一行全形標點與英文混排（冬青黑體整行）
            ("ja", LyricsTimelineBuilder.build(lyrics: "[00:02.00]夜明けの鐘が遠くで鳴る\n[00:06.00]川の上を灯りが流れていく\n[00:10.50]紙の舟は朝を待っている\n[00:15.00]「灯籠」が、静かに流れる。lanterns drift\n[00:19.50]", duration: 24)!),
            ("long", LyricsTimelineBuilder.build(lyrics: "[00:01.00]Lanterns drifting slowly over the silent river while the paper boats keep waiting for the dawn to come\n[00:09.00]Ash in the wind\n[00:12.00]", duration: 15)!),
        ]
    }
}
