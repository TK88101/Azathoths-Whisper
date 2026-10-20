import Foundation
import OSLog

/// 查找的本機診斷事件（C 段計劃 §3.9）：只有來源、結果類別、對齊率、耗時——不含曲名、歌詞、URL
enum TimingDiagnosticEvent: Sendable {
    /// 來源給了帶時間的行；`alignment?.isAccepted` 決定它是不是答案
    case answer(StoredTimingSource, alignment: LRCAligner.Alignment?, elapsed: TimeInterval)
    case noTiming(StoredTimingSource, NoTimingReason, elapsed: TimeInterval)
    case failure(StoredTimingSource, ProviderFailure, elapsed: TimeInterval)
    case skipped(TimingResolution.SkipReason)
    case storeFailed
}

protocol TimingDiagnostics: Sendable {
    func record(_ event: TimingDiagnosticEvent)
}

struct NoopTimingDiagnostics: TimingDiagnostics {
    func record(_ event: TimingDiagnosticEvent) {}
}

/// OSLog（subsystem 既有、category `timings`）：每次問一個來源記一行，每 20 次記一行累計（C 段計劃 §3.9）。
/// 事件型別裡本來就沒有曲名、歌詞、URL：日誌不可能帶出它們
final class OSLogTimingDiagnostics: TimingDiagnostics, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "timings")
    private let lock = NSLock()
    private var tally = TimingTally()

    func record(_ event: TimingDiagnosticEvent) {
        Self.log.info("\(Self.line(for: event), privacy: .public)")
        if let summary = lock.withLock({ tally.add(event) }) {
            Self.log.info("\(summary, privacy: .public)")
        }
    }

    static func line(for event: TimingDiagnosticEvent) -> String {
        switch event {
        case .answer(let source, let alignment, let elapsed):
            let accepted = alignment?.isAccepted == true
            let scores = alignment.map {
                " music=\(format($0.musicRate)) lrc=\(format($0.lrcCoverage)) anchors=\($0.anchors.compactMap { $0 }.count)"
            } ?? ""
            return "source=\(source.rawValue) result=\(accepted ? "answer" : "alignFail")\(scores) ms=\(milliseconds(elapsed))"
        case .noTiming(let source, let reason, let elapsed):
            return "source=\(source.rawValue) result=\(reason.rawValue) ms=\(milliseconds(elapsed))"
        case .failure(let source, let failure, let elapsed):
            return "source=\(source.rawValue) result=failure kind=\(name(failure)) ms=\(milliseconds(elapsed))"
        case .skipped(let reason):
            return "result=skipped reason=\(reason)"
        case .storeFailed:
            return "result=storeFailed"
        }
    }

    static func name(_ failure: ProviderFailure) -> String {
        switch failure {
        case .rateLimited: return "rateLimited"
        case .blocked(let status): return "blocked\(status)"
        case .server(let status): return "server\(status)"
        case .transport: return "transport"
        case .timedOut: return "timedOut"
        case .unparsable: return "unparsable"
        case .cancelled: return "cancelled"
        case .circuitOpen: return "circuitOpen"
        }
    }

    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
    private static func milliseconds(_ seconds: TimeInterval) -> Int { Int((seconds * 1000).rounded()) }
}

/// 累計：各來源命中數、各失敗種類次數；每 `interval` 次來源請求吐一行
struct TimingTally {
    static let interval = 20

    private var queries = 0
    private var answers: [String: Int] = [:]
    private var failures: [String: Int] = [:]

    mutating func add(_ event: TimingDiagnosticEvent) -> String? {
        switch event {
        case .answer(let source, let alignment, _):
            queries += 1
            if alignment?.isAccepted == true { answers[source.rawValue, default: 0] += 1 }
        case .noTiming:
            queries += 1
        case .failure(_, let failure, _):
            queries += 1
            failures[OSLogTimingDiagnostics.name(failure), default: 0] += 1
        case .skipped, .storeFailed:
            return nil
        }
        guard queries.isMultiple(of: Self.interval) else { return nil }
        return "summary queries=\(queries) answers \(Self.list(answers)) failures \(Self.list(failures))"
    }

    private static func list(_ counts: [String: Int]) -> String {
        counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }
}
