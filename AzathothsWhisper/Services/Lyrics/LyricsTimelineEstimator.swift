import Foundation

/// 層 3：從純文字估算時間軸（母計劃 §2.4，永遠可用）。
///
/// 時間窗 `[duration×lead, duration×tail]`；行時長∝字數（不含空白）、下限 `minLineDuration`；
/// 段落間隔＝`gapWeight` 行、間奏標籤＝`interludeWeight` 行。下限總和放不進時間窗時整體等比縮放（仍單調）
enum LyricsTimelineEstimator {
    static let leadFraction = 0.06
    static let tailFraction = 0.94
    static let minLineDuration = 1.2
    static let gapWeight = 0.6
    static let interludeWeight = 3.0

    private enum Item {
        case line(text: String, isChorus: Bool, weight: Double)
        case gap(units: Double)
    }

    static func estimate(lyrics: String, duration: Double) -> LyricsTimeline? {
        guard duration > 0 else { return nil }
        let items = trimmedGaps(items(from: LyricsLines.parse(lyrics)))
        let weights = items.compactMap { item -> Double? in
            if case .line(_, _, let weight) = item { return weight }
            return nil
        }
        guard !weights.isEmpty else { return nil }
        let averageLine = weights.reduce(0, +) / Double(weights.count)
        let window = duration * (tailFraction - leadFraction)
        let durations = allocate(items: items, averageLine: averageLine, window: window)

        var cursor = duration * leadFraction
        var lines: [TimedLine] = []
        for (item, length) in zip(items, durations) {
            if case .line(let text, let isChorus, _) = item {
                lines.append(TimedLine(start: cursor, end: cursor + length, text: text, isChorus: isChorus))
            }
            cursor += length
        }
        return LyricsTimeline(lines: lines, source: .estimated, duration: duration)
    }

    private static func items(from lines: [LyricsLine]) -> [Item] {
        var items: [Item] = []
        for line in lines {
            let next: Item
            switch line {
            case .lyric(let text, let isChorus):
                next = .line(text: text, isChorus: isChorus, weight: Double(max(text.filter { !$0.isWhitespace }.count, 1)))
            case .section(.interlude):
                next = .gap(units: interludeWeight)
            case .section, .blank:
                next = .gap(units: gapWeight)
            }
            // 相鄰的間隔合併成一段，取較長者（空行＋標籤不重複計）
            if case .gap(let units) = next, case .gap(let previous)? = items.last {
                items[items.count - 1] = .gap(units: max(units, previous))
            } else {
                items.append(next)
            }
        }
        return items
    }

    /// 頭尾的間隔丟掉：時間窗本身已留了前奏與尾奏
    private static func trimmedGaps(_ items: [Item]) -> [Item] {
        func isGap(_ item: Item) -> Bool {
            if case .gap = item { return true }
            return false
        }
        return Array(items.drop(while: isGap).reversed().drop(while: isGap).reversed())
    }

    private static func allocate(items: [Item], averageLine: Double, window: Double) -> [Double] {
        let weights = items.map { item -> Double in
            switch item {
            case .line(_, _, let weight): return weight
            case .gap(let units): return units * averageLine
            }
        }
        let isLine = items.map { item -> Bool in
            if case .line = item { return true }
            return false
        }
        var pinned = Set<Int>()
        while true {
            let available = window - Double(pinned.count) * minLineDuration
            let freeWeight = weights.indices.filter { !pinned.contains($0) }.reduce(0) { $0 + weights[$1] }
            guard available > 0, freeWeight > 0 else { break }
            let share = available / freeWeight
            let short = weights.indices.filter { !pinned.contains($0) && isLine[$0] && weights[$0] * share < minLineDuration }
            guard !short.isEmpty else {
                return weights.indices.map { pinned.contains($0) ? minLineDuration : weights[$0] * share }
            }
            pinned.formUnion(short)
        }
        // 下限放不進時間窗：每行先取下限、間隔照比例，再整體縮放進窗
        let raw = weights.indices.map { isLine[$0] ? minLineDuration : weights[$0] * minLineDuration / averageLine }
        let scale = window / raw.reduce(0, +)
        return raw.map { $0 * scale }
    }
}

/// 取得順序的本地部分：內嵌 LRC（層 1）→ 估算（層 3）。外部來源在 C 段加在中間
enum LyricsTimelineBuilder {
    /// LRC 末行沒有下一個時間點、也沒有曲長時，顯示這麼久
    static let lastLineFallback = 5.0

    static func build(lyrics: String, duration: Double) -> LyricsTimeline? {
        if LRCParser.isLRC(lyrics), let timeline = embedded(LRCParser.parse(lyrics), duration: duration) {
            return timeline
        }
        return LyricsTimelineEstimator.estimate(lyrics: lyrics, duration: duration)
    }

    static func lastLineEnd(start: Double, duration: Double) -> Double {
        duration > start ? duration : start + lastLineFallback
    }

    /// 顯示 LRC 自己的行文字（欄位本身就是這份 LRC）；空行只當下一行的結束時刻
    private static func embedded(_ lrc: [LRCLine], duration: Double) -> LyricsTimeline? {
        let lines = lrc.indices.compactMap { index -> TimedLine? in
            let line = lrc[index]
            guard !line.text.isEmpty else { return nil }
            let end = index + 1 < lrc.count ? lrc[index + 1].start : lastLineEnd(start: line.start, duration: duration)
            return TimedLine(start: line.start, end: end, text: line.text, isChorus: false)
        }
        guard let last = lines.last else { return nil }
        return LyricsTimeline(lines: lines, source: .embeddedLRC, duration: max(duration, last.end))
    }
}
