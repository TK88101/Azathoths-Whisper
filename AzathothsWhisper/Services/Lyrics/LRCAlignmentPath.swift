import Foundation

/// 單調最優對齊路徑（⑩ 計劃 docs/plans/2026-11-06-lyrics-timing-fix.md §4.1、附錄 D）。
///
/// 轉移：跳過 Music 行、跳過 cue、`1 Music ↔ s cue`（s＝1…`LRCAligner.maxMergedCues`，不跨空 cue）、
/// `t Music ↔ 1 cue`（t＝2…`LRCAligner.maxMergedMusicLines`）。分數＝(對上的 Music 行數, 群組數) 字典序。
/// 重建：每個 Music 行取「最早的最佳 cue」，同一 cue 依 單行 → 串接 → 反向 的順序；找不到就跳過該行、不吃 cue。
/// 貪婪（revision 2）本來就最佳時，這個重建逐步重現它（不變式 ⓑ，`LRCAlignmentOracleTests` 守）
struct LRCAlignmentPath: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        /// Music 第 `music` 行對 cue `cue`…`cue + span − 1`
        case forward(music: Int, cue: Int, span: Int)
        /// Music 第 `music`…`music + span − 1` 行對 cue `cue`
        case reverse(music: Int, cue: Int, span: Int)

        var musicLines: Int {
            if case .reverse(_, _, let span) = self { return span }
            return 1
        }
    }

    let steps: [Step]

    var matchedMusicLines: Int { steps.reduce(0) { $0 + $1.musicLines } }

    /// 取消＝nil（每次相似度比較前、配置分數表前都檢查：20 s 時限與 shutdown 才管得到它）
    static func find(music: [[Character]], cues: [[Character]]) -> LRCAlignmentPath? {
        guard !Task.isCancelled else { return nil }
        var table = ScoreTable(rows: music.count + 1, columns: cues.count + 1)
        // 每格可行的配對轉移只算一次（相似度是主要成本），重建時直接讀
        var masks = [TransitionMask](repeating: [], count: music.count * (cues.count + 1))
        for i in stride(from: music.count - 1, through: 0, by: -1) {
            for j in stride(from: cues.count, through: 0, by: -1) {
                guard let mask = matches(music, cues, i, j) else { return nil }
                masks[i * (cues.count + 1) + j] = mask
                var best = table[i + 1, j]
                if j < cues.count { best = max(best, table[i, j + 1]) }
                for step in steps(mask, i, j) { best = max(best, value(of: step, in: table)) }
                table[i, j] = best
            }
        }
        return reconstruct(rows: music.count, columns: cues.count + 1, table, masks)
    }

    private static func reconstruct(rows: Int, columns: Int, _ table: ScoreTable, _ masks: [TransitionMask]) -> LRCAlignmentPath {
        var steps: [Step] = []
        var (i, j) = (0, 0)
        while i < rows {
            let target = table[i, j]
            var chosen: Step?
            search: for k in j..<(columns - 1) where target.matched > 0 {
                for step in Self.steps(masks[i * columns + k], i, k) where value(of: step, in: table) == target {
                    chosen = step
                    break search
                }
            }
            guard let chosen else {
                i += 1
                continue
            }
            steps.append(chosen)
            switch chosen {
            case .forward(_, let cue, let span): (i, j) = (i + 1, cue + span)
            case .reverse(_, let cue, let span): (i, j) = (i + span, cue + 1)
            }
        }
        return LRCAlignmentPath(steps: steps)
    }

    /// 遮罩 → 轉移，依重建偏好順序：單行 → 串接 s=2 → s=3 → 反向 t=2 → t=3
    private static func steps(_ mask: TransitionMask, _ i: Int, _ j: Int) -> [Step] {
        guard !mask.isEmpty else { return [] }
        var steps: [Step] = []
        for span in 1...LRCAligner.maxMergedCues where mask.contains(.forward(span)) { steps.append(.forward(music: i, cue: j, span: span)) }
        for span in 2...LRCAligner.maxMergedMusicLines where mask.contains(.reverse(span)) { steps.append(.reverse(music: i, cue: j, span: span)) }
        return steps
    }

    /// 在 (i, j) 哪些配對轉移可行；取消＝nil。串接一旦長到不可能相似就停（再接只會更長）
    private static func matches(_ music: [[Character]], _ cues: [[Character]], _ i: Int, _ j: Int) -> TransitionMask? {
        guard j < cues.count, !cues[j].isEmpty else { return [] }
        var mask: TransitionMask = []
        var joined: [Character] = []
        for span in 1...LRCAligner.maxMergedCues {
            let next = j + span - 1
            guard next < cues.count, !cues[next].isEmpty else { break }
            guard !Task.isCancelled else { return nil }
            joined += cues[next]
            if LRCAligner.isTooLong(joined.count, comparedWith: music[i].count) { break }
            if LRCAligner.isSimilar(music[i], joined) { mask.insert(.forward(span)) }
        }
        var lines = music[i]
        for span in 2...LRCAligner.maxMergedMusicLines {
            let next = i + span - 1
            guard next < music.count else { break }
            guard !Task.isCancelled else { return nil }
            lines += music[next]
            if LRCAligner.isTooLong(lines.count, comparedWith: cues[j].count) { break }
            if LRCAligner.isSimilar(lines, cues[j]) { mask.insert(.reverse(span)) }
        }
        return mask
    }

    private static func value(of step: Step, in table: ScoreTable) -> Score {
        switch step {
        case .forward(let music, let cue, let span):
            return Score(matched: 1, groups: 1) + table[music + 1, cue + span]
        case .reverse(let music, let cue, let span):
            return Score(matched: Int32(span), groups: 1) + table[music + span, cue + 1]
        }
    }
}

/// 一格的可行配對：bit 0–2＝正向 s＝1–3，bit 3–4＝反向 t＝2–3
private struct TransitionMask: OptionSet {
    let rawValue: UInt8

    static func forward(_ span: Int) -> TransitionMask { TransitionMask(rawValue: 1 << (span - 1)) }
    static func reverse(_ span: Int) -> TransitionMask { TransitionMask(rawValue: 1 << (span + 1)) }
}

/// (對上的 Music 行數, 群組數)：字典序比較
private struct Score: Comparable {
    var matched: Int32
    var groups: Int32

    static let zero = Score(matched: 0, groups: 0)

    static func < (lhs: Score, rhs: Score) -> Bool {
        (lhs.matched, lhs.groups) < (rhs.matched, rhs.groups)
    }

    static func + (lhs: Score, rhs: Score) -> Score {
        Score(matched: lhs.matched + rhs.matched, groups: lhs.groups + rhs.groups)
    }
}

/// 扁平的 (rows × columns) 分數表；每格 8 bytes（行數上限 2000 時約 32 MB）
private struct ScoreTable {
    private var cells: [Score]
    private let columns: Int

    init(rows: Int, columns: Int) {
        self.columns = columns
        cells = [Score](repeating: .zero, count: rows * columns)
    }

    subscript(row: Int, column: Int) -> Score {
        get { cells[row * columns + column] }
        set { cells[row * columns + column] = newValue }
    }
}
