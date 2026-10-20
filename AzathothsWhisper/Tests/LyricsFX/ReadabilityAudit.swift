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
    /// 開頭 1 s 細取樣（空白多半在行首）
    static let fineWindow = 1.0
    static let fineStep = 0.05
    static let coarseStep = 0.1

    struct Finding: CustomStringConvertible {
        let line: Int
        let seconds: Double
        let at: Double
        var description: String { "第 \(line) 行 \(String(format: "%.2f", seconds)) s（約 \(String(format: "%.2f", at)) s 起）" }
    }

    /// 對象行的時刻表：開頭細、之後粗
    static func samples(_ line: TimedLine) -> [(time: Double, step: Double)] {
        var result: [(Double, Double)] = []
        var t = line.start
        while t < line.revealEnd {
            let step = t - line.start < fineWindow ? fineStep : coarseStep
            result.append((t, step))
            t += step
        }
        return result
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

    /// 對象行自己的煙霧殘影（smoke 進場只畫 5 份淡副本、不畫本體）：同字、彼此距離 0.3 字級以內的副本合成透明度 1−Π(1−a)
    static func hasInkFromCopies(_ ghosts: [GlyphDraw]) -> Bool {
        ghosts.contains { anchor in
            let near = ghosts.filter {
                $0.text == anchor.text && !$0.text.allSatisfy(\.isWhitespace)
                    && hypot($0.origin.x - anchor.origin.x, $0.origin.y - anchor.origin.y) < anchor.fontSize * 0.3
            }
            return 1 - near.reduce(1.0) { $0 * (1 - $1.opacity) } >= visibleOpacity
        }
    }

    /// G2：最長的「對象行沒有看得見主字」時間（連續取樣的刻度相加；最後一段再加一個刻度當保守上界）
    static func longestBlank(_ timeline: LyricsTimeline, recipe: ComposedRecipe, measurer: any TextMeasuring) -> Finding? {
        var worst: Finding?
        for index in timeline.lines.indices where !timeline.lines[index].text.allSatisfy(\.isWhitespace) {
            let single = onlyLine(timeline, index)
            var run = 0.0, runStart = 0.0
            for (time, step) in samples(timeline.lines[index]) {
                let frame = plan(single, time: time, recipe: recipe, measurer: measurer)
                if (frame.glyphs + frame.unlit).contains(where: isInk) || hasInkFromCopies(frame.ghosts) {
                    run = 0
                } else {
                    if run == 0 { runStart = time }
                    run += step
                    if run + step > (worst?.seconds ?? 0) { worst = Finding(line: index, seconds: run + step, at: runStart) }
                }
            }
        }
        return worst
    }

    /// 字框：CoreText 實際字寬 ×（行盒高 × 0.8），左右內縮 8%；不含旋轉（近似）
    static func box(_ glyph: GlyphDraw, measurer: any TextMeasuring) -> CGRect {
        let width = (measurer.advances(of: glyph.text, face: glyph.face, fontSize: glyph.fontSize).last ?? glyph.fontSize * 0.5) * glyph.scaleX
        let height = (measurer.ascent(face: glyph.face, fontSize: glyph.fontSize) + measurer.descent(face: glyph.face, fontSize: glyph.fontSize)) * glyph.scaleY * 0.8
        return CGRect(x: glyph.origin.x, y: glyph.origin.y, width: width, height: height).insetBy(dx: width * 0.08, dy: 0)
    }

    /// 自己的殘影副本：同字、原點在半個字級以內
    static func isOwnCopy(_ other: GlyphDraw, of target: GlyphDraw) -> Bool {
        other.text == target.text && abs(other.origin.x - target.origin.x) < target.fontSize * 0.5 && abs(other.origin.y - target.origin.y) < target.fontSize * 0.5
    }

    /// 對象行看得見的主字中，被畫面上其他看得見字形蓋住一半以上者的比例
    static func coveredFraction(target: [GlyphDraw], screen: FramePlan, measurer: any TextMeasuring) -> Double {
        let mains = target.filter(isInk)
        guard !mains.isEmpty else { return 0 }
        let others = (screen.glyphs + screen.unlit + screen.ghosts).filter(isInk)
        let covered = mains.filter { main in
            let box = Self.box(main, measurer: measurer)
            let area = box.width * box.height
            guard area > 0 else { return false }
            return others.contains { other in
                guard other != main, !isOwnCopy(other, of: main) else { return false }
                let overlap = box.intersection(Self.box(other, measurer: measurer))
                return !overlap.isNull && overlap.width * overlap.height / area > coveredArea
            }
        }
        return Double(covered.count) / Double(mains.count)
    }

    /// G3：最長的「對象行疊住」時間（取樣刻度相加）
    static func longestCovered(_ timeline: LyricsTimeline, recipe: ComposedRecipe, measurer: any TextMeasuring) -> Finding? {
        var worst: Finding?
        for index in timeline.lines.indices where !timeline.lines[index].text.allSatisfy(\.isWhitespace) {
            let single = onlyLine(timeline, index)
            var run = 0.0, runStart = 0.0
            var t = timeline.lines[index].start
            while t < timeline.lines[index].revealEnd {
                let target = plan(single, time: t, recipe: recipe, measurer: measurer).glyphs
                let screen = plan(timeline, time: t, recipe: recipe, measurer: measurer)
                if coveredFraction(target: target, screen: screen, measurer: measurer) > coveredShare {
                    if run == 0 { runStart = t }
                    run += coarseStep
                    if run > (worst?.seconds ?? 0) { worst = Finding(line: index, seconds: run, at: runStart) }
                } else {
                    run = 0
                }
                t += coarseStep
            }
        }
        return worst
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
            ("ja", LyricsTimelineBuilder.build(lyrics: "[00:02.00]夜明けの鐘が遠くで鳴る\n[00:06.00]川の上を灯りが流れていく\n[00:10.50]紙の舟は朝を待っている\n[00:15.00]", duration: 20)!),
            ("long", LyricsTimelineBuilder.build(lyrics: "[00:01.00]Lanterns drifting slowly over the silent river while the paper boats keep waiting for the dawn to come\n[00:09.00]Ash in the wind\n[00:12.00]", duration: 15)!),
        ]
    }
}
