import Foundation

/// 外部時間軸「只借時間、不借文字」（母計劃 §2.4，Codex R1-4；C 段計劃 §3.4）。
///
/// Music 歌詞行與 LRC 行以相似度 ≥ `lineSimilarityThreshold` 做**單調最優**對齊（`LRCAlignmentPath`，revision 3）：
/// 一個 Music 行可對連續 1–`maxMergedCues` 個 LRC 行（Genius 把 LRC 兩行合成一行，錨到第一行起點；
/// docs/plans/2026-10-19-lyrics-fx-merged-line-align.md），連續 2–`maxMergedMusicLines` 個 Music 行也可對一個 LRC 行
/// （Music 把 LRC 一行拆開，docs/plans/2026-11-06-lyrics-timing-fix.md）。採用條件全部成立：
/// Music 側對上比例 ≥ `alignmentRateThreshold`、LRC 側（非空行）被對上的群組比例 ≥ `lrcCoverageThreshold`、
/// 群組數 ≥ `minimumAnchors`（否則視為別盤／別曲／別版本，或重複副歌錯錨）。
/// 未對上的行在相鄰已對上行之間等距內插。顯示文字永遠是 Music 的
enum LRCAligner {
    static let lineSimilarityThreshold = 0.8
    static let alignmentRateThreshold = 0.7
    /// 擋「Music 漏了前段、LRC 有兩段相同副歌」整段錨到前一段（Codex R2）；2026-10-19 探針達標 5 首最低 0.618
    static let lrcCoverageThreshold = 0.6
    static let minimumAnchors = 3
    /// Music 一行最多對上幾行連續的 LRC（不跨空行）
    static let maxMergedCues = 3
    /// 幾行連續的 Music 最多對上一個 LRC 行（Music 把 LRC 一行拆開）
    static let maxMergedMusicLines = 3
    /// 對齊演算法版本：1＝一對一、2＝加串接、3＝單調最優＋反向群組。新寫入的記錄記下它；notFound 低於它就重查一次
    static let revision = 3
    /// found 錨點仍可信的最低版本：found 低於它才重查，跨機比較 found 新舊一律用 `effectiveRevision`（⑩ 計劃 §4.3）。
    /// **升級它之前必須先把 `alignerRevision` 拆成「錨點產生版本」與「已重查版本」兩欄**（⑩ 計劃 §8 R5）：
    /// 現行 `TimingRecord.merged` 保留舊錨點時會把版本升到已查版本，兩義共用一欄
    static let foundCompatibleRevision = 2

    /// 比較 found 新舊用的版本：達到 `foundCompatibleRevision` 的一律同級
    static func effectiveRevision(_ revision: Int) -> Int { min(revision, foundCompatibleRevision) }
    /// 外部 cue 與存檔時間可以比曲長晚這麼多（曲長取整、尾奏淡出）
    static let durationSlack: Double = 5

    /// 一次對齊的結果：`anchors[i]`＝Music 第 i 行對上的 LRC 開始秒數（nil＝未對上）
    struct Alignment: Equatable, Sendable {
        let anchors: [Double?]
        let musicRate: Double
        let lrcCoverage: Double
        /// 直接 cue 群組數（反向群組只算 1）：`minimumAnchors` 與 `lrcCoverage` 都以它計
        let groups: Int

        /// `groups` 省略＝每個非 nil 錨點各自一群組（沒有反向群組時的值）
        init(anchors: [Double?], musicRate: Double, lrcCoverage: Double, groups: Int? = nil) {
            self.anchors = anchors
            self.musicRate = musicRate
            self.lrcCoverage = lrcCoverage
            self.groups = groups ?? anchors.compactMap { $0 }.count
        }

        var isAccepted: Bool {
            groups >= LRCAligner.minimumAnchors
                && musicRate >= LRCAligner.alignmentRateThreshold
                && lrcCoverage >= LRCAligner.lrcCoverageThreshold
        }

        /// 存檔存每個已定起點的行（直接錨點與反向群組的切分點；index＝`LyricsLines.lyricTexts` 序號），讀回時用同一個內插重建
        var lineStarts: [TimingRecord.LineStart] {
            anchors.enumerated().compactMap { index, start in start.map { TimingRecord.LineStart(index: index, start: $0) } }
        }
    }

    static func align(lyrics: String, lrc: [LRCLine], duration: Double, source: TimingSource) -> LyricsTimeline? {
        guard let alignment = alignment(lyrics: lyrics, lrc: lrc, duration: duration), alignment.isAccepted else { return nil }
        return timeline(lyrics: lyrics, anchors: alignment.anchors, duration: duration, source: source)
    }

    /// Music 沒有歌詞行＝nil
    /// Music 沒有歌詞行、或被取消＝nil。`duration` 只用於最後一個 cue 上的反向群組（上界＝`lastLineEnd`）
    static func alignment(lyrics: String, lrc: [LRCLine], duration: Double = 0) -> Alignment? {
        let texts = LyricsLines.lyricTexts(lyrics)
        guard !texts.isEmpty else { return nil }
        // 兩邊各正規化一次（不在 M×L 的配對迴圈裡重算）
        let music = texts.map { Array(normalized($0)) }
        let cues = lrc.map { Array(normalized($0.text)) }
        guard let path = LRCAlignmentPath.find(music: music, cues: cues) else { return nil }
        var anchors = [Double?](repeating: nil, count: texts.count)
        for step in path.steps {
            switch step {
            case .forward(let line, let cue, _):
                anchors[line] = lrc[cue].start
            case .reverse(let line, let cue, let span):
                let start = lrc[cue].start
                let end = nextCueStart(after: cue, in: lrc, cues: cues)
                    ?? LyricsTimelineBuilder.lastLineEnd(start: start, duration: duration)
                let starts = groupStarts(weights: music[line..<(line + span)].map(\.count), start: start, end: end)
                for (offset, value) in starts.enumerated() { anchors[line + offset] = value }
            }
        }
        // LRC 側覆蓋率以群組數計：沒有反向群組時＝對上的 Music 行數（與 revision 2 逐值相同，串接不放寬，Codex M1-Q2）
        let comparable = cues.filter { !$0.isEmpty }.count
        return Alignment(
            anchors: anchors,
            musicRate: Double(path.matchedMusicLines) / Double(texts.count),
            lrcCoverage: comparable == 0 ? 0 : Double(path.steps.count) / Double(comparable),
            groups: path.steps.count
        )
    }

    /// 反向群組在 `[start, end)` 內按權重（正規化字數）切分起點；權重總和為 0 時等分。首行＝`start`，單調不減
    static func groupStarts(weights: [Int], start: Double, end: Double) -> [Double] {
        let total = weights.reduce(0, +)
        let span = end - start
        var cumulative = 0
        return weights.indices.map { index in
            defer { cumulative += weights[index] }
            let fraction = total == 0 ? Double(index) / Double(weights.count) : Double(cumulative) / Double(total)
            return start + span * fraction
        }
    }

    private static func nextCueStart(after cue: Int, in lrc: [LRCLine], cues: [[Character]]) -> Double? {
        cues.indices.dropFirst(cue + 1).first { !cues[$0].isEmpty }.map { lrc[$0].start }
    }

    /// 外部 cue 的邊界驗證（Codex R1 #8）：丟掉非有限、負值、超過曲長＋slack 的；依時間穩定排序；同一時間只留第一行
    static func sanitizedCues(_ lrc: [LRCLine], duration: Double) -> [LRCLine] {
        let limit = duration + durationSlack
        let valid = lrc.enumerated()
            .filter { $0.element.start.isFinite && $0.element.start >= 0 && $0.element.start <= limit }
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
        return valid.enumerated().filter { $0.offset == 0 || valid[$0.offset - 1].start != $0.element.start }.map(\.element)
    }

    /// 由存檔錨點重建（Codex R1 #7）：index 在目前歌詞行數內且遞增、時間有限、單調不減、不超過曲長＋slack；不合＝nil
    static func timeline(lyrics: String, stored: [TimingRecord.LineStart], duration: Double, source: TimingSource) -> LyricsTimeline? {
        let count = LyricsLines.lyricTexts(lyrics).count
        guard storedLinesFit(stored, lineCount: count, durationLimit: duration + durationSlack) else { return nil }
        var anchors = [Double?](repeating: nil, count: count)
        for line in stored { anchors[line.index] = line.start }
        return timeline(lyrics: lyrics, anchors: anchors, duration: duration, source: source)
    }

    /// 存檔錨點能不能套在這份歌詞上：非空、index 在行數內且遞增、時間有限、非負、單調不減、不超過上限
    static func storedLinesFit(_ stored: [TimingRecord.LineStart], lineCount: Int, durationLimit: Double = .infinity) -> Bool {
        !stored.isEmpty && stored.areWellFormedAnchors
            && stored.allSatisfy { $0.index < lineCount && $0.start <= durationLimit }
    }

    private static func timeline(lyrics: String, anchors: [Double?], duration: Double, source: TimingSource) -> LyricsTimeline? {
        let music = LyricsLines.parse(lyrics).compactMap { line -> (text: String, isChorus: Bool)? in
            if case .lyric(let text, let isChorus) = line { return (text, isChorus) }
            return nil
        }
        guard !music.isEmpty, music.count == anchors.count else { return nil }
        let starts = interpolated(anchors, duration: duration)
        guard !starts.isEmpty else { return nil }
        let lines = music.indices.map { index in
            let end = index + 1 < starts.count
                ? starts[index + 1]
                : LyricsTimelineBuilder.lastLineEnd(start: starts[index], duration: duration)
            let text = music[index].text
            return TimedLine(
                start: starts[index], end: end, text: text, isChorus: music[index].isChorus,
                revealEnd: WordPacing.revealEnd(text: text, start: starts[index], lineEnd: end)
            )
        }
        return LyricsTimeline(lines: lines, source: source, duration: max(duration, lines.last?.end ?? 0))
    }

    /// 1 −（編輯距離／較長者長度），兩邊先正規化（小寫、只留字母與數字）；兩邊皆空＝0。
    /// **達門檻時是精確值；低於門檻時只保證低於門檻**（提早結束，不算完整距離）——只能拿來和門檻比較
    static func similarity(_ a: String, _ b: String) -> Double {
        similarity(Array(normalized(a)), Array(normalized(b)))
    }

    /// 較長的一邊已長到不可能達門檻（差距超過允許的編輯距離）：串接時用來提早停，再接只會更不相似
    static func isTooLong(_ longer: Int, comparedWith shorter: Int) -> Bool {
        longer > shorter && longer - shorter > allowedDistance(longest: longer)
    }

    static func isSimilar(_ left: [Character], _ right: [Character]) -> Bool {
        similarity(left, right) >= lineSimilarityThreshold
    }

    /// 門檻內允許的最大編輯距離；向上取整只會少提早結束，不會誤判
    static func allowedDistance(longest: Int) -> Int {
        Int((Double(longest) * (1 - lineSimilarityThreshold)).rounded(.up))
    }

    private static func similarity(_ left: [Character], _ right: [Character]) -> Double {
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 0 }
        let allowed = allowedDistance(longest: longest)
        return 1 - Double(EditDistance.between(left, right, limit: allowed)) / Double(longest)
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 前段以 `duration×lead`、末段以 `duration×tail` 為邊界（已對上的時間超出邊界時以它為準）
    private static func interpolated(_ anchors: [Double?], duration: Double) -> [Double] {
        let known = anchors.indices.filter { anchors[$0] != nil }
        guard let first = known.first, let last = known.last else { return [] }
        var starts = anchors.map { $0 ?? 0 }
        let low = min(duration * LyricsTimelineEstimator.leadFraction, starts[first])
        for index in 0..<first {
            starts[index] = low + (starts[first] - low) * Double(index) / Double(first)
        }
        for (from, to) in zip(known, known.dropFirst()) where to - from > 1 {
            for index in (from + 1)..<to {
                starts[index] = starts[from] + (starts[to] - starts[from]) * Double(index - from) / Double(to - from)
            }
        }
        let tailCount = anchors.count - 1 - last
        let high = max(duration * LyricsTimelineEstimator.tailFraction, starts[last])
        for step in stride(from: 1, through: tailCount, by: 1) {
            starts[last + step] = starts[last] + (high - starts[last]) * Double(step) / Double(tailCount + 1)
        }
        return starts
    }
}
