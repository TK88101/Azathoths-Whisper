import Foundation
import SpikeCore

// 中繼的模擬負載（sprint-0-detail.md §4.3 relay-load、§4.5）：另一個程序、自己的 SBApplication。
// 以指定間隔讀狀態三項；每 3 s 送一次 seek 到當前位置（不換歌）。
// seek 配額由父程序從該實驗的 OperationBudget 預扣後以參數傳入（§6 背景 seek 計入各實驗上限）。
// 父程序消失（被 kill）時自行結束，不成為孤兒持續操控 Music。
enum RelayLoad {
    static let controlEvery: Duration = .seconds(3)
    /// 一輪 B5／B6 約 150 s，每 3 s 一次 seek
    static let seekQuota = 50
    /// 絕對壽命上限：一輪實驗遠短於此，任何情況下都不會無限輪詢
    static let maxLifetime: Duration = .seconds(600)

    static func spawn(interval: Double, maxSeeks: Int) -> Process? {
        guard let executable = Bundle.main.executablePath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["relay-load", String(interval), String(maxSeeks)]
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            return process
        } catch {
            print("relay-load 無法啟動：\(error)")
            return nil
        }
    }

    /// 還原前呼叫：停掉並等它真的結束，免得它的 seek 蓋掉還原結果
    static func stop(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    @MainActor
    static func run(interval: Double, maxSeeks: Int) async {
        guard let bridge = MusicBridge.connect() else { return }
        let parent = getppid()
        let deadline = ContinuousClock.now + maxLifetime
        var lastControl = ContinuousClock.now
        var seeks = 0
        while getppid() == parent, ContinuousClock.now < deadline {
            _ = bridge.state()
            _ = bridge.currentTrackID()
            let position = bridge.position().value
            if seeks < maxSeeks, ContinuousClock.now - lastControl >= controlEvery, let position {
                _ = bridge.seek(to: position)
                seeks += 1
                lastControl = ContinuousClock.now
            }
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}

// MARK: N1、N2（只記事實）

@MainActor
extension Experiments {
    struct N1Record: Encodable {
        let once: Bool
        let startIndex: Int
        let albumFollowing: [String]
        let contextAfter: [String]
        let queueAfter: [String]?
    }

    /// 從專輯第 3 首點歌（once 分別為 false／true），記下播放脈絡與佇列檔的序列
    static func n1() async -> Bool {
        await run("n1", budget: .n1) { session in
            let (oracle, _) = try oracle(session)
            let startIndex = 2
            var records: [N1Record] = []
            for once in [false, true] {
                _ = try await session.command { session.bridge.play(trackID: oracle.sequence[startIndex], once: once) }
                try await Task.sleep(for: .seconds(2))
                records.append(N1Record(once: once, startIndex: startIndex,
                                        albumFollowing: Array(oracle.sequence.dropFirst(startIndex + 1)),
                                        contextAfter: session.bridge.context().value.sequence,
                                        queueAfter: MusicFileReader.queue().ids))
            }
            return records
        }
    }

    struct N2Record: Encodable {
        let devices: Int
        let switched: Bool
        let switchMilliseconds: Double?
        let readBackMatched: Bool
        let restored: Bool
    }

    static func n2() async -> Bool {
        await run("n2", budget: .n2) { session in
            let original = session.bridge.airPlaySelection().value
            let devices = session.bridge.airPlayDeviceIDs().value
            guard let other = devices.first(where: { !original.contains($0) }) else {
                return [N2Record(devices: devices.count, switched: false, switchMilliseconds: nil,
                                 readBackMatched: false, restored: true)]
            }
            let switched = try await session.command { session.bridge.selectAirPlay([other]) }
            let readBack = await session.waitFor(session.bridge.airPlaySelection) { $0 == [other] }
            let back = try await session.command { session.bridge.selectAirPlay(original) }
            return [N2Record(devices: devices.count, switched: switched.value, switchMilliseconds: switched.milliseconds,
                             readBackMatched: readBack.matchedAt != nil, restored: back.value)]
        }
    }
}
