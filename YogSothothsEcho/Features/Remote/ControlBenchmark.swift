#if DEBUG
import Foundation
import Observation
import RemoteProtocol
import RemoteTransport
import UIKit

// N-01／B6／D2 量測工具（sprint-4-detail.md §4.12）：只在 DEBUG 編入。序列器每次都等前一次結果才送下一次
// （點歌另等目標曲的到達事件），種子固定；結果寫成只含數值的 JSON（ID 以序號代替、白名單鍵），經 Finder 取出

// 百分位：`PercentileJudge`（LibraryMeasurement.swift；Release 的量測紀錄也要用，不在 DEBUG 內）

enum BenchmarkPlan {
    enum Kind: String, CaseIterable, Sendable { case toggle, seek, next, previous, play }

    enum Step: Equatable, Sendable {
        case toggle, next, previous
        /// 目標位置＝曲長的比例（5 %–95 %，避開曲首曲尾）
        case seek(Double)
        case play(String)
        /// 批間回到起點：要確認到達才開始下一批，不計樣本
        case warmup(String)
        /// 上一首的前置：等結果的下一首，不計樣本
        case untimedNext
    }

    static let samples = 50
    static let batch = 25

    static func steps(_ kind: Kind, songs: [TrackSummary], seed: UInt64) -> [Step] {
        var random = SeededGenerator(seed: seed)
        switch kind {
        case .toggle:
            return Array(repeating: .toggle, count: samples)
        case .seek:
            return (0..<samples).map { _ in .seek(Double.random(in: 0.05...0.95, using: &random)) }
        case .next:
            guard let start = songs.first else { return [] }
            let one = [Step.warmup(start.id)] + Array(repeating: Step.next, count: batch)
            return one + one
        case .previous:
            // 點歌的佇列只有「點的那首到專輯結尾」（CR-005）：先不計時往前走 25 首留下可退的歷史，再計時往回（#4-1 實測）
            guard let start = songs.first else { return [] }
            let one = [Step.warmup(start.id)] + Array(repeating: Step.untimedNext, count: batch) + Array(repeating: Step.previous, count: batch)
            return one + one
        case .play:
            guard !songs.isEmpty else { return [] }
            return (0..<samples).map { _ in .play(songs[Int.random(in: 0..<songs.count, using: &random)].id) }
        }
    }
}

/// 量測紀錄：只含數值與環境（不含曲名、曲目 ID）
struct BenchmarkRecord: Encodable {
    static let protocolVersion = 1
    static let allowedKeys: Set<String> = [
        "protocolVersion", "kind", "seed", "device", "osVersion", "build", "startState", "samplesMs", "p95Ms", "p99Ms",
        "resultMs", "outcomes", "trackChanges", "pacingMs", "indeterminateReasons", "warmups", "missingArrivals", "errors", "seekDurations",
    ]

    let kind: BenchmarkPlan.Kind
    let seed: UInt64
    var startState: String = "unknown"
    /// 延遲（毫秒）：點歌＝送出 → 目標曲的事件；其餘＝送出 → 回覆
    var samplesMs: [Double] = []
    /// 點歌：送出 → play.result（觀測值）
    var resultMs: [Double] = []
    var outcomes: [String: Int] = [:]
    /// 上一首／下一首：回覆的目前曲與送出前不同＝trackChanged、相同＝sameTrack（上一首回到開頭）
    var trackChanges: [String: Int] = [:]
    var indeterminateReasons: [String] = []
    var warmups: [String] = []
    var missingArrivals = 0
    var errors: [String: Int] = [:]
    var seekDurations: [Double] = []

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, kind, seed, device, osVersion, build, startState, samplesMs, p95Ms, p99Ms, resultMs, outcomes, trackChanges, pacingMs
        case indeterminateReasons, warmups, missingArrivals, errors, seekDurations
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.protocolVersion, forKey: .protocolVersion)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(seed, forKey: .seed)
        try c.encode(MeasurementRecord.deviceIdentifier, forKey: .device)
        try c.encode(UIDevice.current.systemVersion, forKey: .osVersion)
        try c.encode(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-", forKey: .build)
        try c.encode(startState, forKey: .startState)
        try c.encode(samplesMs, forKey: .samplesMs)
        try c.encodeIfPresent(PercentileJudge.nearestRank(samplesMs, 0.95), forKey: .p95Ms)
        try c.encodeIfPresent(PercentileJudge.nearestRank(samplesMs, 0.99), forKey: .p99Ms)
        try c.encode(resultMs, forKey: .resultMs)
        try c.encode(outcomes, forKey: .outcomes)
        try c.encode(trackChanges, forKey: .trackChanges)
        try c.encode(PlaybackLimits.gateSettle * 1000, forKey: .pacingMs)
        try c.encode(indeterminateReasons, forKey: .indeterminateReasons)
        try c.encode(warmups, forKey: .warmups)
        try c.encode(missingArrivals, forKey: .missingArrivals)
        try c.encode(errors, forKey: .errors)
        try c.encode(seekDurations, forKey: .seekDurations)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    var summary: String {
        let p95 = PercentileJudge.nearestRank(samplesMs, 0.95).map { String(format: "%.0f", $0) } ?? "-"
        let p99 = PercentileJudge.nearestRank(samplesMs, 0.99).map { String(format: "%.0f", $0) } ?? "-"
        return "\(kind.rawValue) n=\(samplesMs.count) p95=\(p95)ms p99=\(p99)ms missing=\(missingArrivals) errors=\(errors.values.reduce(0, +))"
    }
}

/// D2 的一筆回條（iPad 端）：送出時刻是 iPad 單調鐘，只用來看間隔；跨裝置的對應靠請求 ID
struct ReceiptRecord: Encodable, Equatable {
    let seq: Int
    let requestID: String
    let sentAt: Double
    let state: String
    let trackOrdinal: Int
}

struct ReceiptsRecord: Encodable {
    static let protocolVersion = 1
    let receipts: [ReceiptRecord]

    private enum CodingKeys: String, CodingKey { case protocolVersion, kind, device, osVersion, build, receipts }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.protocolVersion, forKey: .protocolVersion)
        try c.encode("d2", forKey: .kind)
        try c.encode(MeasurementRecord.deviceIdentifier, forKey: .device)
        try c.encode(UIDevice.current.systemVersion, forKey: .osVersion)
        try c.encode(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-", forKey: .build)
        try c.encode(receipts, forKey: .receipts)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

@MainActor
@Observable
final class ControlBenchmark {
    private(set) var running: BenchmarkPlan.Kind?
    private(set) var done = 0
    private(set) var total = 0
    private(set) var lastSummary: String?
    /// D2：收到 event.playback 就送回條（catalog.page limit 1），Mac 以請求到達時間當「iPad 收到」的上界
    private(set) var receiptMode = false
    private(set) var loadRunning = false
    /// D2 回條紀錄（依送出順序）；以請求 ID 與 Mac 的到達紀錄逐筆對應（Scripts/d2_pair.py）
    private(set) var receipts: [ReceiptRecord] = []

    @ObservationIgnored private let now: @Sendable () -> Double
    @ObservationIgnored private let arrivalTimeout: Duration
    /// 換曲成功後、送下一個之前的等待（Mac 佇列在換曲後保留 gateSettle；CR-006「不量排隊等待」）
    @ObservationIgnored private let pace: @Sendable (Duration) async -> Void
    static let pacing: Duration = .seconds(PlaybackLimits.gateSettle)
    @ObservationIgnored var current: () -> PlaybackEvent? = { nil }
    @ObservationIgnored var position: () -> Double? = { nil }
    @ObservationIgnored private var client: (any PlaybackClient)?
    @ObservationIgnored private var sendReceipt: (@Sendable (UUID) async -> Void)?
    @ObservationIgnored private var receiptSink: AsyncStream<PlaybackEvent>.Continuation?
    @ObservationIgnored private var trackOrdinals: [String: Int] = [:]
    @ObservationIgnored private var arrival: (target: String, at: Double?)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    static let loadInterval: Duration = .seconds(3)

    init(now: @escaping @Sendable () -> Double = MonotonicNow.seconds, arrivalTimeout: Duration = .seconds(40),
         pace: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.now = now
        self.arrivalTimeout = arrivalTimeout
        self.pace = pace
    }

    func attach(_ client: any PlaybackClient, receipt: @escaping @Sendable (UUID) async -> Void) {
        self.client = client
        sendReceipt = receipt
    }

    func detach() {
        client = nil
        sendReceipt = nil
        setReceiptMode(false)
        stopLoad()
    }

    /// 由組裝根接到 NowPlayingViewModel 採用的每一筆事件
    func eventArrived(_ event: PlaybackEvent) {
        if let target = arrival?.target, arrival?.at == nil, event.trackID == target { arrival = (target, now()) }
        if receiptMode { receiptSink?.yield(event) }
    }

    /// 開：之後每筆事件依序送一個回條（前一個回來才送下一個，送出與到達順序才一致）。關：寫出本次紀錄
    func setReceiptMode(_ on: Bool) {
        guard on != receiptMode else { return }
        receiptMode = on
        guard on else {
            receiptSink?.finish()
            receiptSink = nil
            if !receipts.isEmpty { MetricsFile.write(try? receiptsRecord().encoded(), name: "control-d2") }
            return
        }
        receipts = []
        trackOrdinals = [:]
        let (stream, sink) = AsyncStream<PlaybackEvent>.makeStream()
        receiptSink = sink
        Task { [weak self] in
            for await event in stream {
                guard let self, let send = self.sendReceipt else { continue }
                let id = UUID()
                self.receipts.append(ReceiptRecord(seq: self.receipts.count + 1, requestID: id.uuidString, sentAt: self.now(),
                                                   state: event.state.rawValue, trackOrdinal: self.ordinal(event.trackID)))
                await send(id)
            }
        }
    }

    /// 曲目以出現順序編號（紀錄不含曲目 ID）；沒有目前曲＝0
    private func ordinal(_ trackID: String?) -> Int {
        guard let trackID else { return 0 }
        if let known = trackOrdinals[trackID] { return known }
        trackOrdinals[trackID] = trackOrdinals.count + 1
        return trackOrdinals.count
    }

    func receiptsRecord() -> ReceiptsRecord { ReceiptsRecord(receipts: receipts) }

    /// 使用者在 iPad 選好專輯後按「開始」：跑完寫 Documents/metrics
    func start(_ kind: BenchmarkPlan.Kind, albumID: String, songs: [TrackSummary], seed: UInt64) {
        guard running == nil, let client else { return }
        Task {
            let record = await run(kind, albumID: albumID, songs: songs, client: client, seed: seed)
            MetricsFile.write(try? record.encoded(), name: "control-\(kind.rawValue)")
        }
    }

    func run(_ kind: BenchmarkPlan.Kind, albumID: String, songs: [TrackSummary], client: any PlaybackClient,
             seed: UInt64) async -> BenchmarkRecord {
        await run(steps: BenchmarkPlan.steps(kind, songs: songs, seed: seed), kind: kind, albumID: albumID, client: client, seed: seed)
    }

    /// 量測都在同一張專輯內（點歌與暖身都帶這個 albumID）
    func run(steps: [BenchmarkPlan.Step], kind: BenchmarkPlan.Kind, albumID: String, client: any PlaybackClient,
             seed: UInt64) async -> BenchmarkRecord {
        running = kind
        done = 0
        total = steps.count
        var record = BenchmarkRecord(kind: kind, seed: seed)
        record.startState = current()?.state.rawValue ?? "unknown"
        for step in steps {
            await perform(step, albumID: albumID, client: client, into: &record)
            done += 1
        }
        running = nil
        lastSummary = record.summary
        return record
    }

    private func perform(_ step: BenchmarkPlan.Step, albumID: String, client: any PlaybackClient,
                         into record: inout BenchmarkRecord) async {
        switch step {
        case .toggle: await timed(&record) { () throws(EchoRequestError) in try await client.toggle() }
        case .next: await timed(&record, tracksChange: true) { () throws(EchoRequestError) in try await client.next() }
        case .previous: await timed(&record, tracksChange: true) { () throws(EchoRequestError) in try await client.previous() }
        case .untimedNext:
            do {
                if try await client.next().outcome == .applied { await pace(Self.pacing) }
            } catch {
                record.errors["untimedNext:" + Self.label(error), default: 0] += 1
            }
        case .seek(let fraction):
            guard let event = current(), let track = event.trackID, let duration = event.duration else {
                record.errors["noCurrentTrack", default: 0] += 1
                return
            }
            record.seekDurations.append(duration)
            await timed(&record) { () throws(EchoRequestError) in try await client.seek(trackID: track, seconds: duration * fraction) }
        case .play(let id):
            await play(id, albumID: albumID, client: client, into: &record, warmup: false)
        case .warmup(let id):
            await play(id, albumID: albumID, client: client, into: &record, warmup: true)
        }
    }

    private func timed(_ record: inout BenchmarkRecord, tracksChange: Bool = false,
                       _ send: () async throws(EchoRequestError) -> ControlResult) async {
        let trackBefore = current()?.trackID
        let sent = now()
        do {
            let reply = try await send()
            record.samplesMs.append((now() - sent) * 1000)
            record.outcomes[reply.outcome.rawValue, default: 0] += 1
            if tracksChange { record.trackChanges[reply.playback.trackID == trackBefore ? "sameTrack" : "trackChanged", default: 0] += 1 }
            if tracksChange, reply.outcome == .applied { await pace(Self.pacing) }
        } catch {
            record.errors[Self.label(error), default: 0] += 1
        }
    }

    private func play(_ id: String, albumID: String, client: any PlaybackClient, into record: inout BenchmarkRecord,
                      warmup: Bool) async {
        arrival = (id, nil)
        let sent = now()
        let result: Result<PlayResult, EchoRequestError>
        do { result = .success(try await client.play(trackID: id, albumID: albumID)) } catch { result = .failure(error) }
        let replied = now()
        let arrivedAt = await waitForArrival()
        arrival = nil
        if warmup {
            record.warmups.append((arrivedAt == nil ? "missing:" : "arrived:") + Self.label(result))
            return
        }
        if let arrivedAt { record.samplesMs.append((arrivedAt - sent) * 1000) } else { record.missingArrivals += 1 }
        switch result {
        case .success(let outcome):
            record.resultMs.append((replied - sent) * 1000)
            record.outcomes[outcome.outcome.rawValue, default: 0] += 1
            if outcome.outcome == .indeterminate { record.indeterminateReasons.append(outcome.reason?.rawValue ?? "-") }
        case .failure(let error):
            record.errors[Self.label(error), default: 0] += 1
        }
    }

    private func waitForArrival() async -> Double? {
        let deadline = ContinuousClock.now + arrivalTimeout
        while arrival?.at == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return arrival?.at
    }

    // MARK: B6 負載：每 3 s 送一次 seek 到目前位置（不改聽感）

    func startLoad() {
        guard loadTask == nil, let client else { return }
        loadRunning = true
        loadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.loadInterval)
                guard let self, let track = self.current()?.trackID, let position = self.position() else { continue }
                _ = try? await client.seek(trackID: track, seconds: position)
            }
        }
    }

    func stopLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadRunning = false
    }

    private static func label(_ error: EchoRequestError) -> String {
        switch error {
        case .remote(let code): code.rawValue
        case .timeout: "timeout"
        case .disconnected: "disconnected"
        case .invalidResponse: "invalidResponse"
        case .cancelled: "cancelled"
        }
    }

    private static func label(_ result: Result<PlayResult, EchoRequestError>) -> String {
        switch result {
        case .success(let value): value.outcome.rawValue
        case .failure(let error): label(error)
        }
    }
}

#endif
