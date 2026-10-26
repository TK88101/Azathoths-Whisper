#if DEBUG
import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S4 T13（sprint-4-detail.md §4.12）：N-01／B6／D2 量測工具——判定器、序列計畫、序列器（等前一個結果）、JSON 白名單

struct PercentileJudgeTests {
    @Test func nearestRankOnFiftySamples() {
        let values = (1...50).map(Double.init).shuffled()
        #expect(PercentileJudge.nearestRank(values, 0.95) == 48)
        #expect(PercentileJudge.nearestRank(values, 0.99) == 50)
    }

    @Test func nearestRankOnTwentySamples() {
        #expect(PercentileJudge.nearestRank((1...20).map(Double.init), 0.95) == 19)
    }

    @Test func emptyHasNoPercentile() {
        #expect(PercentileJudge.nearestRank([], 0.95) == nil)
    }
}

struct BenchmarkPlanTests {
    private let songs = (1...12).map { PlaybackSamples.song(String(format: "%016llx", UInt64($0)), $0) }

    @Test func toggleIsFiftyAlternations() {
        #expect(BenchmarkPlan.steps(.toggle, songs: songs, seed: 1) == Array(repeating: .toggle, count: 50))
    }

    @Test func seekTargetsStayWithinFiveToNinetyFivePercentAndRepeatPerSeed() {
        let steps = BenchmarkPlan.steps(.seek, songs: songs, seed: 7)
        #expect(steps.count == 50)
        let fractions = steps.compactMap { if case .seek(let f) = $0 { f } else { nil } }
        #expect(fractions.count == 50 && fractions.allSatisfy { (0.05...0.95).contains($0) })
        #expect(BenchmarkPlan.steps(.seek, songs: songs, seed: 7) == steps)
        #expect(BenchmarkPlan.steps(.seek, songs: songs, seed: 8) != steps)
    }

    /// 下一首：從第 1 首起每批 25 次、共 2 批，批間以點歌回到起點（暖身，不計）
    @Test func nextRunsTwoBatchesFromTheFirstSong() {
        let steps = BenchmarkPlan.steps(.next, songs: songs, seed: 1)
        let batch = [BenchmarkPlan.Step.warmup(songs[0].id)] + Array(repeating: .next, count: 25)
        #expect(steps == batch + batch)
    }

    /// 上一首：點歌的佇列只有「點的那首到專輯結尾」（CR-005），點最後一首當起點時前面沒有歌可退、只會一直回開頭（#4-1 實測）。
    /// 改為每批先點第 1 首、不計時按 25 次下一首走到第 26 首（留下可退的歷史），再計時按 25 次上一首
    @Test func previousWalksForwardUntimedThenRunsTwoBatchesBack() {
        let steps = BenchmarkPlan.steps(.previous, songs: songs, seed: 1)
        let batch = [BenchmarkPlan.Step.warmup(songs[0].id)] + Array(repeating: .untimedNext, count: 25)
            + Array(repeating: .previous, count: 25)
        #expect(steps == batch + batch)
    }

    /// 不計時的下一首：等結果才送下一個，不進樣本
    @MainActor @Test func untimedNextIsNotSampled() async {
        let runner = ControlBenchmark(now: ManualNow().now, arrivalTimeout: .milliseconds(50), pace: { _ in })
        let client = FakePlaybackClient()
        let record = await runner.run(steps: [.untimedNext, .previous], kind: .previous, albumID: PlaybackSamples.album, client: client, seed: 1)
        #expect(client.recorded == ["next", "previous"])
        #expect(record.samplesMs.count == 1)
    }

    @Test func playSamplesFiftySongsBySeed() {
        let steps = BenchmarkPlan.steps(.play, songs: songs, seed: 3)
        let ids = steps.compactMap { if case .play(let id) = $0 { id } else { nil } }
        #expect(ids.count == 50 && Set(ids).isSubset(of: Set(songs.map(\.id))))
        #expect(BenchmarkPlan.steps(.play, songs: songs, seed: 3) == steps)
    }
}

@MainActor
struct ControlBenchmarkRunnerTests {
    let client = FakePlaybackClient()
    let now = ManualNow()
    let songs = (1...3).map { PlaybackSamples.song(String(format: "%016llx", UInt64($0)), $0) }

    /// 序列器每次都等前一個結果才送下一個
    @Test func waitsForEachResultBeforeSendingTheNext() async {
        let runner = ControlBenchmark(now: now.now, arrivalTimeout: .seconds(5), pace: { _ in })
        client.lock.withLock { client.holdControl = true }
        let task = Task { await runner.run(.toggle, albumID: PlaybackSamples.album, songs: songs, client: client, seed: 1) }
        while client.heldControls == 0 { await Task.yield() }
        #expect(client.recorded == ["toggle"])
        for _ in 0..<5 { await Task.yield() }
        #expect(client.recorded == ["toggle"])
        client.lock.withLock { client.holdControl = false }
        client.releaseControls()
        let record = await task.value
        #expect(record.samplesMs.count == 50 && client.recorded.count == 50)
    }

    /// 點歌：延遲終點＝收到目標曲的事件（不是 play.result）；結果比率另記
    @Test func playLatencyEndsAtArrivalEventNotResult() async {
        let runner = ControlBenchmark(now: now.now, arrivalTimeout: .seconds(5), pace: { _ in })
        client.lock.withLock {
            client.holdPlay = true
            client.playResults = [.success(PlayResult(outcome: .degraded, reason: .shortcutMissing))]
        }
        let steps: [BenchmarkPlan.Step] = [.play(songs[1].id)]
        let task = Task { await runner.run(steps: steps, kind: .play, albumID: PlaybackSamples.album, client: client, seed: 9) }
        while client.heldPlays == 0 { await Task.yield() }
        now.advance(1.25)   // 二進位可精確表示，相減不帶浮點誤差
        runner.eventArrived(PlaybackSamples.event(songs[1].id, at: 1))
        now.advance(3)
        client.releasePlay()
        let record = await task.value
        #expect(record.samplesMs == [1250])
        #expect(record.resultMs == [4250])
        #expect(record.outcomes == ["degraded": 1])
    }

    @Test func missingArrivalIsCountedNotTimed() async {
        let runner = ControlBenchmark(now: now.now, arrivalTimeout: .milliseconds(50), pace: { _ in })
        let record = await runner.run(steps: [.play(songs[0].id)], kind: .play, albumID: PlaybackSamples.album, client: client, seed: 1)
        #expect(record.samplesMs.isEmpty && record.missingArrivals == 1)
    }

    /// D2：回條一個接一個送（事件順序），每筆記下請求 ID、送出時刻、事件的狀態與曲目序號；JSON 不含曲目 ID
    @Test func receiptsAreSentOneAtATimeAndRecordedByRequestID() async throws {
        let runner = ControlBenchmark(now: now.now, arrivalTimeout: .milliseconds(50), pace: { _ in })
        let sent = Locked<[UUID]>([])
        let gate = ReceiptGate()
        runner.attach(client, receipt: { id in
            sent.withLock { $0.append(id) }
            await gate.wait()      // 每個回條停住，直到測試放行
        })
        runner.setReceiptMode(true)
        runner.eventArrived(PlaybackSamples.event(songs[0].id, .playing, at: 1))
        now.advance(0.5)
        runner.eventArrived(PlaybackSamples.event(songs[0].id, .paused, at: 2))
        runner.eventArrived(PlaybackSamples.event(songs[1].id, .playing, at: 3))
        for _ in 0..<50 { await Task.yield() }
        #expect(sent.withLock { $0.count } == 1)      // 第一個還沒回來，第二個不送
        for _ in 0..<3 { gate.release(); for _ in 0..<50 { await Task.yield() } }
        #expect(sent.withLock { $0.count } == 3)
        let records = runner.receipts
        let sentIDs = sent.withLock { $0.map(\.uuidString) }
        #expect(records.map(\.requestID) == sentIDs)
        #expect(records.map(\.state) == ["playing", "paused", "playing"] && records.map(\.trackOrdinal) == [1, 1, 2])
        let text = String(decoding: try runner.receiptsRecord().encoded(), as: UTF8.self)
        #expect(!songs.contains { text.contains($0.id) })
    }

    /// 控制的結果也計數；上一首／下一首另分「換了歌」與「同一首（回到開頭）」（thecure 2026-10-18）
    @Test func controlOutcomesAndTrackChangesAreCounted() async throws {
        let runner = ControlBenchmark(now: now.now, arrivalTimeout: .milliseconds(50), pace: { _ in })
        runner.current = { PlaybackSamples.event(PlaybackSamples.t1) }
        client.lock.withLock { client.controlResult = .success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(PlaybackSamples.t2))) }
        let changed = await runner.run(steps: [.next, .next], kind: .next, albumID: PlaybackSamples.album, client: client, seed: 1)
        #expect(changed.outcomes == ["applied": 2] && changed.trackChanges == ["trackChanged": 2])
        client.lock.withLock { client.controlResult = .success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(PlaybackSamples.t1))) }
        let rewound = await runner.run(steps: [.previous], kind: .previous, albumID: PlaybackSamples.album, client: client, seed: 1)
        #expect(rewound.trackChanges == ["sameTrack": 1])
        client.lock.withLock { client.controlResult = .success(ControlResult(outcome: .notApplied, playback: PlaybackSamples.event())) }
        let toggled = await runner.run(steps: [.toggle], kind: .toggle, albumID: PlaybackSamples.album, client: client, seed: 1)
        #expect(toggled.outcomes == ["notApplied": 1] && toggled.trackChanges.isEmpty)
        let object = try #require(try JSONSerialization.jsonObject(with: changed.encoded()) as? [String: Any])
        #expect(Set(object.keys).isSubset(of: BenchmarkRecord.allowedKeys) && object["trackChanges"] != nil)
    }

    /// 換曲成功後先等 gateSettle 再送下一個（CR-006「不量排隊等待」：Mac 佇列在換曲後保留 1 s；thecure 2026-10-18）；
    /// 未生效不等。等待不進樣本，JSON 記 pacingMs
    @Test func appliedSkipsArePacedOutsideTheSample() async throws {
        let paced = Locked<[Duration]>([])
        let runner = ControlBenchmark(now: now.now, arrivalTimeout: .milliseconds(50), pace: { d in paced.withLock { $0.append(d) } })
        runner.current = { PlaybackSamples.event(PlaybackSamples.t1) }
        client.lock.withLock { client.controlResult = .success(ControlResult(outcome: .applied, playback: PlaybackSamples.event(PlaybackSamples.t2))) }
        let record = await runner.run(steps: [.untimedNext, .next, .toggle], kind: .next, albumID: PlaybackSamples.album, client: client, seed: 1)
        #expect(paced.withLock { $0 } == [.seconds(1), .seconds(1)])
        client.lock.withLock { client.controlResult = .success(ControlResult(outcome: .notApplied, playback: PlaybackSamples.event())) }
        _ = await runner.run(steps: [.previous], kind: .previous, albumID: PlaybackSamples.album, client: client, seed: 1)
        #expect(paced.withLock { $0 }.count == 2)
        let object = try #require(try JSONSerialization.jsonObject(with: record.encoded()) as? [String: Any])
        #expect(object["pacingMs"] as? Double == 1000 && Set(object.keys).isSubset(of: BenchmarkRecord.allowedKeys))
    }

    /// JSON 只含白名單鍵、只有數值：不含曲目 ID 或曲名
    @Test func recordJSONIsWhitelistedAndAnonymous() async throws {
        let runner = ControlBenchmark(now: now.now, arrivalTimeout: .milliseconds(50), pace: { _ in })
        let record = await runner.run(.next, albumID: PlaybackSamples.album, songs: songs, client: client, seed: 2)
        let data = try record.encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys).isSubset(of: BenchmarkRecord.allowedKeys))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!songs.contains { text.contains($0.id) || text.contains($0.title) })
        #expect(record.warmups.count == 2)
    }
}
/// 回條替身的閘門：每次 wait 停住，release 放行一個
final class ReceiptGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async { await withCheckedContinuation { c in lock.withLock { waiting.append(c) } } }
    func release() { lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }?.resume() }
}
#endif
