import Foundation
import OSLog

/// 進度條拖曳的診斷紀錄（#6-1 F11：下一首後拖進度條偶發不生效）：只記時刻、事件種類、曲目 ID 末 6 碼、秒數與結果，不記曲名。
/// DEBUG 才有：寫 OSLog，並把最近 200 筆覆寫到 Documents/metrics/seek-trace.log（Finder 取出）。Release 為空實作
enum SeekTrace {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "seek")
    private static let capacity = 200
    @MainActor private static var lines: [String] = []
    #endif

    @MainActor
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        let text = line()
        logger.notice("\(text, privacy: .public)")
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullTime, .withFractionalSeconds])
        lines.append("\(stamp) \(text)")
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("metrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: base.appendingPathComponent("seek-trace.log"), atomically: true, encoding: .utf8)
        #endif
    }

    /// 曲目 ID 只留末 6 碼（足以對照 Mac 端紀錄）
    static func short(_ id: String?) -> String { id.map { String($0.suffix(6)) } ?? "-" }
}
