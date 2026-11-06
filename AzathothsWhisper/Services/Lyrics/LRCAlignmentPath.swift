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

        var music: Int {
            switch self { case .forward(let music, _, _), .reverse(let music, _, _): music }
        }

        var cue: Int {
            switch self { case .forward(_, let cue, _), .reverse(_, let cue, _): cue }
        }

        /// 這一步吃掉的 Music 行數與 cue 數
        var advance: (music: Int, cue: Int) {
            switch self {
            case .forward(_, _, let span): (1, span)
            case .reverse(_, _, let span): (span, 1)
            }
        }
    }

    let steps: [Step]

    var matchedMusicLines: Int { steps.reduce(0) { $0 + $1.advance.music } }

    /// Music 行數上限：比照外部 LRC 的 `ProviderOutcome.maximumTimedLines`（超過不是一首歌），表最壞 2000×2000（約 36 MB）
    static let maximumMusicLines = ProviderOutcome.maximumTimedLines

    /// 每個 cue 最多吃 `maxMergedMusicLines` 行：連這個理論上限都到不了 `alignmentRateThreshold` 就不可能採用
    static func canReachRate(musicLines: Int, comparableCues: Int) -> Bool {
        Double(LRCAligner.maxMergedMusicLines * comparableCues) >= LRCAligner.alignmentRateThreshold * Double(musicLines)
    }

    /// 取消＝nil（配置表之前、每次相似度比較前、重建每一行前都檢查：20 s 時限與 shutdown 才管得到它）。
    /// Music 超過上限、或理論上限到不了門檻：不配置 M×L 表、回空路徑（＝不採用；本機歌詞行數沒有上限，安全評審 F2、codex R2）
    static func find(music: [[Character]], cues: [[Character]]) -> LRCAlignmentPath? {
        guard !Task.isCancelled else { return nil }
        guard music.count <= maximumMusicLines, canReachRate(musicLines: music.count, comparableCues: cues.count(where: { !$0.isEmpty })) else {
            return LRCAlignmentPath(steps: [])
        }
        var table = Grid(rows: music.count + 1, columns: cues.count + 1, filledWith: Score.zero)
        // 每格可行的配對轉移只算一次（相似度是主要成本），重建時直接讀
        var masks = Grid(rows: music.count, columns: cues.count + 1, filledWith: TransitionMask())
        for i in stride(from: music.count - 1, through: 0, by: -1) {
            for j in stride(from: cues.count, through: 0, by: -1) {
                guard let mask = matches(music, cues, i, j) else { return nil }
                masks[i, j] = mask
                var best = table[i + 1, j]
                if j < cues.count { best = max(best, table[i, j + 1]) }
                for step in steps(mask, i, j) { best = max(best, value(of: step, in: table)) }
                table[i, j] = best
            }
        }
        return reconstruct(rows: music.count, cueCount: cues.count, table, masks)
    }

    private static func reconstruct(rows: Int, cueCount: Int, _ table: Grid<Score>, _ masks: Grid<TransitionMask>) -> LRCAlignmentPath? {
        var steps: [Step] = []
        var (i, j) = (0, 0)
        while i < rows {
            guard !Task.isCancelled else { return nil }
            guard let step = earliestOptimalStep(i, from: j, cueCount: cueCount, table, masks) else {
                i += 1
                continue
            }
            steps.append(step)
            (i, j) = (i + step.advance.music, step.cue + step.advance.cue)
        }
        return LRCAlignmentPath(steps: steps)
    }

    /// Music 行 i 從 cue j 起、最早一個達到最佳分數的轉移；沒有＝跳過這一行
    private static func earliestOptimalStep(_ i: Int, from j: Int, cueCount: Int, _ table: Grid<Score>, _ masks: Grid<TransitionMask>) -> Step? {
        let target = table[i, j]
        guard target.matched > 0 else { return nil }
        for k in j..<cueCount {
            if let step = steps(masks[i, k], i, k).first(where: { value(of: $0, in: table) == target }) { return step }
        }
        return nil
    }

    /// 遮罩 → 轉移，依重建偏好順序：單行 → 串接 s=2 → s=3 → 反向 t=2 → t=3
    private static func steps(_ mask: TransitionMask, _ i: Int, _ j: Int) -> [Step] {
        guard !mask.isEmpty else { return [] }
        let forward = (1...LRCAligner.maxMergedCues).compactMap { mask.contains(.forward($0)) ? Step.forward(music: i, cue: j, span: $0) : nil }
        let reverse = (2...LRCAligner.maxMergedMusicLines).compactMap { mask.contains(.reverse($0)) ? Step.reverse(music: i, cue: j, span: $0) : nil }
        return forward + reverse
    }

    /// 在 (i, j) 哪些配對轉移可行；取消＝nil
    private static func matches(_ music: [[Character]], _ cues: [[Character]], _ i: Int, _ j: Int) -> TransitionMask? {
        guard j < cues.count, !cues[j].isEmpty else { return [] }
        let cueRun = cues[j..<min(j + LRCAligner.maxMergedCues, cues.count)].prefix { !$0.isEmpty }   // 串接不跨空 cue
        let musicRun = music[i..<min(i + LRCAligner.maxMergedMusicLines, music.count)]
        guard let forward = similarSpans(music[i], cueRun, from: 1, as: TransitionMask.forward),
              let reverse = similarSpans(cues[j], musicRun, from: 2, as: TransitionMask.reverse)
        else { return nil }
        return forward.union(reverse)
    }

    /// `single` 與 `run` 前 1、2、… 段（段數上限＝`run` 的長度，由呼叫端切）的串接比相似度，段數 ≥ `minSpan` 且相似者記進遮罩；取消＝nil。
    /// 先比累加長度：一旦長到不可能相似就停（再接只會更長），通過才真的串接（單行極長時不白複製，安全評審 F4）
    private static func similarSpans(
        _ single: [Character], _ run: ArraySlice<[Character]>, from minSpan: Int, as bit: (Int) -> TransitionMask
    ) -> TransitionMask? {
        var length = 0
        var mask: TransitionMask = []
        for (offset, piece) in run.enumerated() {
            guard !Task.isCancelled else { return nil }
            length += piece.count
            if LRCAligner.isTooLong(length, comparedWith: single.count) { break }
            let span = offset + 1
            if span >= minSpan, LRCAligner.isSimilar(single, Array(run.prefix(span).joined())) { mask.insert(bit(span)) }
        }
        return mask
    }

    private static func value(of step: Step, in table: Grid<Score>) -> Score {
        let advance = step.advance
        return Score(matched: Int32(advance.music), groups: 1) + table[step.music + advance.music, step.cue + advance.cue]
    }
}

/// 一格的可行配對：低位起依序為正向 s＝1…`maxMergedCues`、反向 t＝2…`maxMergedMusicLines`（目前共 5 位）
private struct TransitionMask: OptionSet {
    let rawValue: UInt8

    static func forward(_ span: Int) -> TransitionMask { TransitionMask(rawValue: 1 << (span - 1)) }
    static func reverse(_ span: Int) -> TransitionMask { TransitionMask(rawValue: 1 << (LRCAligner.maxMergedCues + span - 2)) }
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

/// 扁平的 (rows × columns) 表。分數每格 8 bytes、遮罩 1 byte
private struct Grid<Element> {
    private var cells: [Element]
    private let columns: Int

    init(rows: Int, columns: Int, filledWith value: Element) {
        self.columns = columns
        cells = [Element](repeating: value, count: rows * columns)
    }

    subscript(row: Int, column: Int) -> Element {
        get { cells[row * columns + column] }
        set { cells[row * columns + column] = newValue }
    }
}
