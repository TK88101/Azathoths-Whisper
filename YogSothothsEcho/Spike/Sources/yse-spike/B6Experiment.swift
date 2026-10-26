import AppKit
import Foundation
import SpikeCore

// B6：量正在運行的 Azathoth 的換歌偵測延遲（sprint-0-detail.md §4.5）。
// 起點＝本程序收到 Music playerInfo 通知的 mach_continuous_time；終點＝Azathoth monitor 紀錄的 machTimestamp。
@MainActor
extension Experiments {
    static let azathothBundleID = "com.ibridgezhao.azathothswhisper"
    static let monitorPredicate = "subsystem == \"\(azathothBundleID)\" AND category == \"monitor\""
    static let sampleSpacing: TimeInterval = 4
    static let quietTimeout: TimeInterval = 10

    struct B6Record: Encodable {
        let round: String
        let interval: Double?
        let outcomes: [String]
        let latenciesMilliseconds: [Double?]
        let invalidSamples: Int
        let p95Milliseconds: Double?
    }

    /// interval 為 nil＝基準 ①（不開 relay-load）
    static func b6(interval: Double?) async -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: azathothBundleID).isEmpty else {
            print("Azathoth's Whisper 沒開：B6 不可判定")
            return false
        }
        let stream = LogStream(predicate: monitorPredicate)
        do { try stream.start() } catch { print("log stream 無法啟動：\(error)"); return false }
        defer { stream.stop() }
        let name = interval.map { "b6-\(Int($0 * 1000))ms" } ?? "b6-baseline"
        return await run(name, budget: interval == nil ? .b6Baseline : .b6Loaded, background: interval) { session in
            try await waitForMonitorLines(stream)
            let (oracle, identity) = try await prepare(session)
            try await resetToStart(session, oracle: oracle)
            let pump = EventPump()
            pump.startNotifications()
            defer { pump.stop() }
            var outcomes: [B6Pairing.Outcome] = []
            var invalid = 0
            while outcomes.filter(\.isCounted).count < B6Verdict.requiredSamples {
                guard invalid <= maxInvalidPerItem else { throw Session.Stop.precondition("無效樣本過多") }
                try assertContext(session, identity: identity)
                let outcome = try await b6Sample(session, oracle: oracle, stream: stream, pump: pump)
                if outcome.isCounted { outcomes.append(outcome) } else { invalid += 1 }
            }
            return [b6Record(name: name, interval: interval, outcomes: outcomes, invalid: invalid)]
        }
    }

    /// §4.5：Azathoth 的 monitor 紀錄要先看得到（它每 3 s 輪詢一次），否則不可判定
    private static func waitForMonitorLines(_ stream: LogStream) async throws {
        for _ in 0..<60 where stream.lines().isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        guard !stream.lines().isEmpty else {
            throw Session.Stop.precondition("看不到 Azathoth 的 monitor 紀錄：B6 不可判定")
        }
    }

    private static func b6Sample(_ session: Session, oracle: PlaybackOracle, stream: LogStream,
                                 pump: EventPump) async throws -> B6Pairing.Outcome {
        if let duration = session.bridge.currentDuration().value, let position = session.bridge.position().value,
           duration - position < 10 {
            _ = try await session.command { session.bridge.seek(to: duration / 2) }
        }
        guard await waitQuiet(stream, pump: pump) else { return .invalidNotQuiet }
        let expected = session.bridge.currentTrackID().value.flatMap(oracle.expectedNext)
        let mark = Mach.now()
        _ = try await session.command { session.bridge.next() }
        while Mach.seconds(Mach.now()) - Mach.seconds(mark) < 3, pump.notifications(after: mark).isEmpty { pump.pump() }
        // 沒收到通知＝起點不存在，樣本無效（不計入、重做）
        guard let start = pump.notifications(after: mark).first?.at else { return .invalidNoStartEvent }
        while Mach.seconds(Mach.now()) - Mach.seconds(start) < B6Pairing.window + 0.2 { pump.pump() }
        let reads = stream.lines().compactMap { MonitorRead.parse(message: $0.message, timestamp: Mach.seconds($0.machTimestamp)) }
        let outcome = B6Pairing.pair(start: Mach.seconds(start), reads: reads,
                                     targetMatched: session.bridge.currentTrackID().value == expected)
        while Mach.seconds(Mach.now()) - Mach.seconds(mark) < sampleSpacing { pump.pump() }
        return outcome
    }

    /// 最近 1.5 s 沒有 changed=true 才算靜默；10 s 內不靜默＝無效
    private static func waitQuiet(_ stream: LogStream, pump: EventPump) async -> Bool {
        let deadline = Date(timeIntervalSinceNow: quietTimeout)
        while Date() < deadline {
            let now = Mach.seconds(Mach.now())
            let recent = stream.lines().contains { line in
                MonitorRead.parse(message: line.message, timestamp: 0)?.changed == true
                    && now - Mach.seconds(line.machTimestamp) < B6Pairing.quietPeriod
            }
            if !recent { return true }
            pump.pump(0.1)
        }
        return false
    }

    private static func b6Record(name: String, interval: Double?, outcomes: [B6Pairing.Outcome], invalid: Int) -> B6Record {
        let latencies: [Double?] = outcomes.map { if case .paired(let ms) = $0 { ms } else { nil } }
        let forP95 = latencies.map { $0 ?? .infinity }
        return B6Record(round: name, interval: interval, outcomes: outcomes.map { "\($0)" },
                        latenciesMilliseconds: latencies, invalidSamples: invalid,
                        p95Milliseconds: Stats.percentile(forP95, 0.95))
    }
}
