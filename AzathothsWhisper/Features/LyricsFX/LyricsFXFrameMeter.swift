import Foundation
import OSLog

/// 每幀耗時的純記帳（A2 計劃 §3.7）：最近 `capacity` 幀的微秒數與畫出的字數，滿了覆寫最舊的
struct LyricsFXFrameSamples: Sendable {
    struct Summary: Equatable, Sendable {
        let frames: Int
        let p50: Int
        let p95: Int
        let max: Int
        let minGlyphs: Int
        let maxGlyphs: Int
    }

    let capacity: Int
    private var micros: [Int] = []
    private var glyphs: [Int] = []
    private var next = 0

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func record(micros value: Int, glyphs count: Int) {
        if micros.count < capacity {
            micros.append(value)
            glyphs.append(count)
        } else {
            micros[next] = value
            glyphs[next] = count
        }
        next = (next + 1) % capacity
    }

    var summary: Summary? {
        guard !micros.isEmpty else { return nil }
        let sorted = micros.sorted()
        // nearest-rank 百分位
        let rank = { (fraction: Double) in sorted[Int((fraction * Double(sorted.count)).rounded(.up)) - 1] }
        return Summary(
            frames: sorted.count, p50: rank(0.5), p95: rank(0.95), max: sorted[sorted.count - 1],
            minGlyphs: glyphs.min() ?? 0, maxGlyphs: glyphs.max() ?? 0
        )
    }
}

#if DEBUG
/// 量測用（只在 DEBUG）：記「主執行緒 plan＋Canvas 指令編碼」的耗時，每 5 秒以 OSLog 記一次摘要。
/// 只有數字，不記歌詞（CLAUDE.md 日誌脫敏）。不含 render server 的光柵化（A2 計劃 §3.7，Codex R1 #2）
@MainActor
final class LyricsFXFrameMeter {
    static let shared = LyricsFXFrameMeter()
    private static let logInterval: Duration = .seconds(5)
    private static let log = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "lyricsFXFrame")

    private var samples = LyricsFXFrameSamples(capacity: 600)
    private var lastLog = ContinuousClock.now

    func record(_ elapsed: Duration, glyphs: Int) {
        samples.record(micros: Int(elapsed.inSeconds * 1_000_000), glyphs: glyphs)
        let now = ContinuousClock.now
        guard now - lastLog >= Self.logInterval, let summary = samples.summary else { return }
        lastLog = now
        Self.log.info(
            "frames \(summary.frames, privacy: .public) p50 \(summary.p50, privacy: .public)us p95 \(summary.p95, privacy: .public)us max \(summary.max, privacy: .public)us glyphs \(summary.minGlyphs, privacy: .public)-\(summary.maxGlyphs, privacy: .public)"
        )
    }
}
#endif
