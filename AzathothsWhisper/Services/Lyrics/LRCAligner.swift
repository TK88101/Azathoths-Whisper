import Foundation

/// 外部時間軸「只借時間、不借文字」（母計劃 §2.4，Codex R1-4；C 段計劃 §3.4）。
///
/// Music 的每個歌詞行在 LRC 中單調向前找相似度 ≥ `lineSimilarityThreshold` 的行（一對一）。採用條件全部成立：
/// Music 側對上比例 ≥ `alignmentRateThreshold`、LRC 側（非空行）被對上比例 ≥ `lrcCoverageThreshold`、
/// 直接錨點 ≥ `minimumAnchors`（否則視為別盤／別曲／別版本，或重複副歌錯錨）。
/// 未對上的行在相鄰已對上行之間等距內插。顯示文字永遠是 Music 的
enum LRCAligner {
    static let lineSimilarityThreshold = 0.8
    static let alignmentRateThreshold = 0.7
    /// 擋「Music 漏了前段、LRC 有兩段相同副歌」整段錨到前一段（Codex R2）；2026-10-19 探針達標 5 首最低 0.618
    static let lrcCoverageThreshold = 0.6
    static let minimumAnchors = 3
    /// 外部 cue 與存檔時間可以比曲長晚這麼多（曲長取整、尾奏淡出）
    static let durationSlack: Double = 5

    /// 一次對齊的結果：`anchors[i]`＝Music 第 i 行對上的 LRC 開始秒數（nil＝未對上）
    struct Alignment: Equatable, Sendable {
        let anchors: [Double?]
        let musicRate: Double
        let lrcCoverage: Double

        var isAccepted: Bool {
            anchors.compactMap { $0 }.count >= LRCAligner.minimumAnchors
                && musicRate >= LRCAligner.alignmentRateThreshold
                && lrcCoverage >= LRCAligner.lrcCoverageThreshold
        }

        /// 存檔只存直接錨點（index＝`LyricsLines.lyricTexts` 序號），讀回時用同一個內插重建
        var lineStarts: [TimingRecord.LineStart] {
            anchors.enumerated().compactMap { index, start in start.map { TimingRecord.LineStart(index: index, start: $0) } }
        }
    }

    static func align(lyrics: String, lrc: [LRCLine], duration: Double, source: TimingSource) -> LyricsTimeline? {
        guard let alignment = alignment(lyrics: lyrics, lrc: lrc), alignment.isAccepted else { return nil }
        return timeline(lyrics: lyrics, anchors: alignment.anchors, duration: duration, source: source)
    }

    /// Music 沒有歌詞行＝nil
    static func alignment(lyrics: String, lrc: [LRCLine]) -> Alignment? {
        let texts = LyricsLines.lyricTexts(lyrics)
        guard !texts.isEmpty else { return nil }
        // 兩邊各正規化一次（不在 M×L 的配對迴圈裡重算）
        let music = texts.map { Array(normalized($0)) }
        let cues = lrc.map { Array(normalized($0.text)) }
        guard let hits = matchedIndices(music, cues: cues) else { return nil }
        let anchors = hits.map { $0.map { lrc[$0].start } }
        let matched = hits.compactMap { $0 }.count
        let comparable = cues.filter { !$0.isEmpty }.count
        return Alignment(
            anchors: anchors,
            musicRate: Double(matched) / Double(texts.count),
            lrcCoverage: comparable == 0 ? 0 : Double(matched) / Double(comparable)
        )
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
            return TimedLine(start: starts[index], end: end, text: music[index].text, isChorus: music[index].isChorus)
        }
        return LyricsTimeline(lines: lines, source: source, duration: max(duration, lines.last?.end ?? 0))
    }

    /// 1 −（編輯距離／較長者長度），兩邊先正規化（小寫、只留字母與數字）；兩邊皆空＝0。
    /// **達門檻時是精確值；低於門檻時只保證低於門檻**（提早結束，不算完整距離）——只能拿來和門檻比較
    static func similarity(_ a: String, _ b: String) -> Double {
        similarity(Array(normalized(a)), Array(normalized(b)))
    }

    private static func similarity(_ left: [Character], _ right: [Character]) -> Double {
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 0 }
        // 門檻內允許的最大距離；向上取整只會少提早結束，不會誤判
        let allowed = Int((Double(longest) * (1 - lineSimilarityThreshold)).rounded(.up))
        return 1 - Double(EditDistance.between(left, right, limit: allowed)) / Double(longest)
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 單調前向、一對一：每行回傳對上的 LRC 序號。每次比對前檢查取消（20 s 時限與 shutdown 才管得到它）；取消＝nil
    private static func matchedIndices(_ music: [[Character]], cues: [[Character]]) -> [Int?]? {
        var cursor = 0
        var hits: [Int?] = []
        for line in music {
            var hit: Int?
            for index in cues.indices.dropFirst(cursor) {
                guard !Task.isCancelled else { return nil }
                if similarity(line, cues[index]) >= lineSimilarityThreshold {
                    hit = index
                    break
                }
            }
            if let hit { cursor = hit + 1 }
            hits.append(hit)
        }
        return hits
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
