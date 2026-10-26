import Foundation
import os
import SpikeCore

// `/usr/bin/log stream --level debug --style ndjson` 的子程序包裝（sprint-0-detail.md §4.5）。
// 注意：zsh 有同名內建 `log`，一律用絕對路徑。
final class LogStream: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var parsed: [OSLogLine] = []

    init(predicate: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--level", "debug", "--style", "ndjson", "--predicate", predicate]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
    }

    func start() throws {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // EOF（log stream 結束）後不再回呼，免得空轉吃 CPU 干擾量測
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.append(data)
        }
        try process.run()
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    func lines() -> [OSLogLine] {
        lock.lock()
        defer { lock.unlock() }
        return parsed
    }

    private func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer = Data(buffer[buffer.index(after: newline)...])
            if let entry = OSLogLine.parse(line) { parsed.append(entry) }
        }
    }
}

enum Mach {
    static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// OSLog 的 machTimestamp 含睡眠時間（logcheck 實測：用 mach_absolute_time 比對會差一段固定的睡眠時長），
    /// 故以 mach_continuous_time 為同一時鐘域
    static func now() -> UInt64 { mach_continuous_time() }

    static func seconds(_ ticks: UInt64) -> Double {
        MachTime.seconds(ticks: ticks, numer: timebase.numer, denom: timebase.denom)
    }
}

/// §4.5 時鐘域實證：自己寫 debug 紀錄並記下 mach 時間，比對串流中同一筆的 machTimestamp
enum LogCheck {
    static let subsystem = "com.ibridgezhao.yse-spike"

    struct Record: Encodable {
        let experiment = "logcheck"
        let received: Int
        let expected: Int
        let deltasMilliseconds: [Double]
        let usable: Bool
    }

    static func run(samples: Int = 5) async throws -> Record {
        let stream = LogStream(predicate: "subsystem == \"\(subsystem)\"")
        try stream.start()
        defer { stream.stop() }
        try await Task.sleep(for: .seconds(2))
        let logger = Logger(subsystem: subsystem, category: "probe")
        var sent: [Int: UInt64] = [:]
        for i in 0..<samples {
            sent[i] = Mach.now()
            logger.debug("probe \(i, privacy: .public)")
            try await Task.sleep(for: .milliseconds(200))
        }
        try await Task.sleep(for: .seconds(2))
        let deltas = stream.lines().compactMap { line -> Double? in
            guard let i = Int(line.message.replacingOccurrences(of: "probe ", with: "")), let at = sent[i] else { return nil }
            return (Mach.seconds(line.machTimestamp) - Mach.seconds(at)) * 1000
        }
        let usable = deltas.count == samples && deltas.allSatisfy { abs($0) <= 5 }
        return Record(received: deltas.count, expected: samples, deltasMilliseconds: deltas, usable: usable)
    }
}
