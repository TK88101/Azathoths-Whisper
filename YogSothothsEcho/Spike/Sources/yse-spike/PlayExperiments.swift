import Foundation
import iTunesLibrary
import SpikeCore

// B1、B5、N1、N2 的播放類實驗（sprint-0-detail.md §4.3、§4.5）。
@MainActor
extension Experiments {
    static let sampleSeed: UInt64 = 20_261_014
    static let warmUp = 3
    static let b5Samples = 50

    // MARK: sample-ids（唯讀 ITLibrary，只取 ID 與位置類型）

    static func sampleIDs() throws -> [String] {
        let library = try ITLibrary(apiVersion: "1.0")
        let songs = library.allMediaItems.filter { $0.mediaKind == .kindSong }.map { item in
            (id: String(format: "%016llX", item.persistentID.uint64Value), kind: String(describing: item.locationType.rawValue))
        }
        return StratifiedSampler.sample(songs, count: 20, seed: sampleSeed)
    }

    // MARK: B1

    static func b1(ids: [String]) async -> Bool {
        await run("b1", budget: .b1) { session in
            var checks: [PlayCheck] = []
            for id in ids {
                _ = try await session.command { session.bridge.play(trackID: id) }
                let read = await session.waitFor({ () -> Timed<(String?, PlayerStateValue)> in
                    let track = session.bridge.currentTrackID()
                    return Timed(value: (track.value, session.bridge.state().value), milliseconds: track.milliseconds,
                                 errorCode: track.errorCode)
                }) { $0.0 == id && $0.1 == .playing }
                checks.append(PlayCheck(expectedID: id, readID: read.value.0, state: read.value.1))
            }
            print("B1 判定：", B1Verdict.judge(checks).rawValue)
            return checks
        }
    }

    // MARK: B5（四種不換脈絡＋指定曲播放；背景開 relay-load）

    struct B5Record: Encodable {
        let kind: String
        let sample: TimedSample
        let lookupMilliseconds: Double?
    }

    static func b5(interval: Double) async -> Bool {
        await run("b5-\(Int(interval * 1000))ms", budget: .b5, background: interval) { session in
            var forward = true
            var records = try await measure(session, kinds: ["playpause"]) { [session.bridge.playPause()] }
            // 下一首／上一首交替送出：每一對各記一筆，播放位置留在序列內（§4.3.3）
            records += try await measure(session, kinds: ["next", "previous"]) {
                [session.bridge.next(), session.bridge.previous()]
            }
            records += try await measure(session, kinds: ["seek"]) {
                forward.toggle()
                return [session.bridge.seek(to: forward ? 30 : 40)]
            }
            return records
        }
    }

    /// 每輪送出 `kinds.count` 個指令，第 i 個結果記為 kinds[i]；前 3 輪 warm-up 不計
    private static func measure(_ session: Session, kinds: [String],
                                round: () -> [Timed<Void>]) async throws -> [B5Record] {
        var records: [B5Record] = []
        for i in 0..<(warmUp + b5Samples) {
            try session.reserve(kinds.count)
            let results = round()
            try await Task.sleep(for: Session.commandGap)
            guard i >= warmUp else { continue }
            for (kind, result) in zip(kinds, results) {
                records.append(B5Record(kind: kind, sample: TimedSample(milliseconds: result.milliseconds,
                                                                         errorCode: result.errorCode),
                                        lookupMilliseconds: nil))
            }
        }
        for kind in kinds {
            print("B5 \(kind)：", B5Verdict.judge(records.filter { $0.kind == kind }.map(\.sample)).rawValue)
        }
        return records
    }

    static func b5Play(ids: [String], interval: Double) async -> Bool {
        // 53 次點歌＋背景 seek 15 次 ＝ 68 ≤ 上限 70（點歌一輪約 30 s，每 3 s 一次 seek）
        await run("b5-play", budget: .b5Play, background: interval, backgroundSeeks: 15) { session in
            var records: [B5Record] = []
            for i in 0..<(warmUp + b5Samples) {
                let result = try await session.command { session.bridge.play(trackID: ids[i % ids.count]) }
                guard i >= warmUp else { continue }
                let error = result.value.found ? result.errorCode : (result.errorCode ?? -1728)
                records.append(B5Record(kind: "play", sample: TimedSample(milliseconds: result.milliseconds, errorCode: error),
                                        lookupMilliseconds: result.value.lookupMs))
            }
            print("B5 play：", B5Verdict.judge(records.map(\.sample)).rawValue)
            return records
        }
    }
}
