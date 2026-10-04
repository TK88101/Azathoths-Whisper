import Foundation

/// 外部時間軸「只借時間、不借文字」（母計劃 §2.4，Codex R1-4）。
///
/// Music 的每個歌詞行在 LRC 中單調向前找相似度 ≥ `lineSimilarityThreshold` 的行；
/// 對上的比例 ≥ `alignmentRateThreshold` 才採用（否則視為別盤／別曲／別版本）；
/// 未對上的行在相鄰已對上行之間等距內插。顯示文字永遠是 Music 的
enum LRCAligner {
    static let lineSimilarityThreshold = 0.8
    static let alignmentRateThreshold = 0.7

    static func align(lyrics: String, lrc: [LRCLine], duration: Double, source: TimingSource) -> LyricsTimeline? {
        let music = LyricsLines.parse(lyrics).compactMap { line -> (text: String, isChorus: Bool)? in
            if case .lyric(let text, let isChorus) = line { return (text, isChorus) }
            return nil
        }
        guard !music.isEmpty else { return nil }
        let anchors = matchedStarts(music.map(\.text), lrc: lrc)
        let matched = anchors.compactMap { $0 }.count
        guard Double(matched) / Double(music.count) >= alignmentRateThreshold else { return nil }

        let starts = interpolated(anchors, duration: duration)
        let lines = music.indices.map { index in
            let end = index + 1 < starts.count
                ? starts[index + 1]
                : LyricsTimelineBuilder.lastLineEnd(start: starts[index], duration: duration)
            return TimedLine(start: starts[index], end: end, text: music[index].text, isChorus: music[index].isChorus)
        }
        return LyricsTimeline(lines: lines, source: source, duration: max(duration, lines.last?.end ?? 0))
    }

    /// 1 −（編輯距離／較長者長度），兩邊先正規化（小寫、只留字母與數字）；兩邊皆空＝0
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = Array(normalized(a))
        let right = Array(normalized(b))
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 0 }
        return 1 - Double(editDistance(left, right)) / Double(longest)
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func matchedStarts(_ texts: [String], lrc: [LRCLine]) -> [Double?] {
        var cursor = 0
        return texts.map { text in
            guard let hit = lrc.indices.dropFirst(cursor).first(where: { similarity(text, lrc[$0].text) >= lineSimilarityThreshold })
            else { return nil }
            cursor = hit + 1
            return lrc[hit].start
        }
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

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, right) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
