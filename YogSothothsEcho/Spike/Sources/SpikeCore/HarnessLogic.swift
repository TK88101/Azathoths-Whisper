import Foundation

// 量測工具的守衛與配對邏輯（sprint-0-detail.md §4.2、§4.4、§4.5）。

// MARK: 選擇器白名單（§4.2 啟動自檢）

public struct SelectorAudit: Sendable, Equatable {
    public let missing: Set<String>
    public let extra: Set<String>

    public var isExact: Bool { missing.isEmpty && extra.isEmpty }

    /// 宣告的選擇器必須「完全等於」白名單：少一個、多一個都不放行
    public static func compare(declared: Set<String>, allowed: Set<String>) -> SelectorAudit {
        SelectorAudit(missing: allowed.subtracting(declared), extra: declared.subtracting(allowed))
    }
}

/// spike 協定的選擇器白名單（§4.2）。候選組＝基本設計 §8 的候選；其餘為量測輔助組（唯讀），不自動進正式白名單。
/// 不含任何會寫曲庫的選擇器；setter 只有 seek 與切 AirPlay。
public enum SpikeAllowList {
    public static let protocols: [String: Set<String>] = [
        "YSESpikeMusicAppProto": [
            // 候選組
            "playpause", "nextTrack", "backTrack", "playerPosition", "setPlayerPosition:", "playerState",
            "currentTrack", "AirPlayDevices", "currentAirPlayDevices", "setCurrentAirPlayDevices:",
            // 量測輔助組
            "tracks", "currentPlaylist", "shuffleEnabled", "songRepeat",
            // F-P-01 ②：以 persistent ID 明確指定資料庫清單再點歌（s0-report.md「N1 後續方案」）
            "playlists",
        ],
        "YSESpikeMusicTrackProto": ["persistentID", "duration", "playOnce:"],
        "YSESpikePlaylistProto": ["persistentID", "tracks"],
        "YSESpikeAirPlayProto": ["persistentID", "selected", "kind"],
    ]
}

// MARK: 結果檔路徑（§4.4：只寫進 S0_RESULTS_DIR，檔名格式固定）

public enum ResultPath {
    public enum Failure: Error, Equatable {
        case invalidExperimentName(String)
        case escapesDirectory
    }

    public static func make(directory: URL, experiment: String, at instant: Date) throws(Failure) -> URL {
        guard experiment.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil else {
            throw .invalidExperimentName(experiment)
        }
        let url = directory.appendingPathComponent("\(experiment)-\(stamp(instant)).jsonl")
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw .escapesDirectory
        }
        return url
    }

    private static func stamp(_ instant: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

// MARK: Azathoth monitor 的 OSLog 紀錄（NowPlayingMonitor.swift:197 的格式）

public struct MonitorRead: Sendable, Equatable {
    public let serial: Int
    public let changed: Bool
    /// OSLog 事件本身的發生時間（秒），不是收到串流的時間（§4.5）
    public let timestamp: Double

    public init(serial: Int, changed: Bool, timestamp: Double) {
        self.serial = serial
        self.changed = changed
        self.timestamp = timestamp
    }

    public static func parse(message: String, timestamp: Double) -> MonitorRead? {
        guard let match = message.wholeMatch(of: /read (\d+) (\S+) changed=(true|false) (\d+)ms/),
              let serial = Int(match.1)
        else { return nil }
        return MonitorRead(serial: serial, changed: match.3 == "true", timestamp: timestamp)
    }
}

// MARK: `log stream --style ndjson` 的一行（§4.5）

/// 用事件本身的 `machTimestamp`（與本機 mach_absolute_time 同一時鐘域），不用收到串流的時間、也不解析帶時區的字串
public struct OSLogLine: Sendable, Equatable {
    public let machTimestamp: UInt64
    public let subsystem: String
    public let category: String
    public let message: String

    public init(machTimestamp: UInt64, subsystem: String, category: String, message: String) {
        self.machTimestamp = machTimestamp
        self.subsystem = subsystem
        self.category = category
        self.message = message
    }

    /// 非 JSON 的表頭行、缺欄位或型別不符的行一律略過
    public static func parse(_ line: String) -> OSLogLine? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ticks = (object["machTimestamp"] as? NSNumber)?.uint64Value,
              let message = object["eventMessage"] as? String
        else { return nil }
        return OSLogLine(machTimestamp: ticks, subsystem: object["subsystem"] as? String ?? "",
                         category: object["category"] as? String ?? "", message: message)
    }
}

public enum MachTime {
    public static func seconds(ticks: UInt64, numer: UInt32, denom: UInt32) -> Double {
        Double(ticks) * Double(numer) / Double(denom) / 1e9
    }
}

// MARK: B6 配對與判定（§4.5）

public enum B6Pairing {
    public static let quietPeriod = 1.5
    public static let window = 3.0

    public enum Outcome: Sendable, Equatable {
        case paired(milliseconds: Double)
        case timeout
        case invalidNotQuiet
        case invalidAmbiguous
        case invalidWrongTrack
        /// 送出下一首後沒收到 Music 的通知：起點不存在（量測管線問題，不是配對歧義）
        case invalidNoStartEvent

        /// 計入 20 筆的樣本：配對成功或逾時；其餘無效、要重做
        public var isCounted: Bool {
            switch self {
            case .paired, .timeout: true
            case .invalidNotQuiet, .invalidAmbiguous, .invalidWrongTrack, .invalidNoStartEvent: false
            }
        }

        var latency: Double? {
            switch self {
            case .paired(let ms): ms
            case .timeout: .infinity
            default: nil
            }
        }
    }

    /// 起點前 1.5 s 須靜默；[起點, 起點 + 3 s] 內恰好一筆 changed=true 才配對
    public static func pair(start: Double, reads: [MonitorRead], targetMatched: Bool) -> Outcome {
        let changes = reads.filter(\.changed).map(\.timestamp)
        if changes.contains(where: { $0 >= start - quietPeriod && $0 < start }) {
            return .invalidNotQuiet
        }
        let inWindow = changes.filter { $0 >= start && $0 <= start + window }
        switch inWindow.count {
        case 0: return .timeout
        case 1: break
        default: return .invalidAmbiguous
        }
        guard targetMatched else { return .invalidWrongTrack }
        return .paired(milliseconds: ((inWindow[0] - start) * 1_000_000).rounded() / 1000)
    }
}

public enum B6Verdict {
    public static let requiredSamples = 20
    public static let maxP95IncreaseMilliseconds = 200.0

    public static func judge(baseline: [B6Pairing.Outcome], loaded: [B6Pairing.Outcome]) -> Verdict {
        let base = baseline.compactMap(\.latency)
        let load = loaded.compactMap(\.latency)
        guard base.count >= requiredSamples, load.count >= requiredSamples else { return .undetermined }
        // 基準本身有逾時＝量法壞了，差值無意義
        guard !base.contains(.infinity), let baseP95 = Stats.percentile(base, 0.95) else { return .undetermined }
        guard !load.contains(.infinity), let loadP95 = Stats.percentile(load, 0.95) else { return .fail }
        return loadP95 - baseP95 <= maxP95IncreaseMilliseconds ? .pass : .fail
    }
}

// MARK: N4 TLS-PSK 本機迴路（§4.3 n4）

public struct N4Result: Codable, Sendable, Equatable {
    public let positiveHandshake: Bool
    public let positiveEcho: Bool
    /// 兩端 PSK 不同時是否仍握手成功（成功＝PSK 沒被驗證）
    public let negativeHandshake: Bool
    public let negotiatedVersion: String?

    public init(positiveHandshake: Bool, positiveEcho: Bool, negativeHandshake: Bool, negotiatedVersion: String?) {
        self.positiveHandshake = positiveHandshake
        self.positiveEcho = positiveEcho
        self.negativeHandshake = negativeHandshake
        self.negotiatedVersion = negotiatedVersion
    }

    /// 正例成、負例敗、版本 1.3 才算「可行」
    public var isFeasible: Bool {
        positiveHandshake && positiveEcho && !negativeHandshake && negotiatedVersion == "TLSv1.3"
    }
}

// MARK: N3 ITLibrary 規模（§4.3 n3）

public struct N3Result: Codable, Sendable, Equatable {
    public static let maxSeconds = 10.0
    public static let maxFootprintDeltaMB = 300.0

    public let seconds: Double
    public let footprintDeltaMB: Double
    public let songCount: Int
    public let albumCount: Int
    /// ITLibrary 回報的位置類型 → 曲數（B1 分層抽樣的依據）
    public let locationKinds: [String: Int]

    public init(seconds: Double, footprintDeltaMB: Double, songCount: Int, albumCount: Int, locationKinds: [String: Int]) {
        self.seconds = seconds
        self.footprintDeltaMB = footprintDeltaMB
        self.songCount = songCount
        self.albumCount = albumCount
        self.locationKinds = locationKinds
    }

    /// 期望（非阻斷）：≤ 10 s、常駐記憶體增加 ≤ 300 MB；超過則 S3 改分批
    public var meetsExpectation: Bool {
        seconds <= Self.maxSeconds && footprintDeltaMB <= Self.maxFootprintDeltaMB
    }
}

// MARK: 指令硬上限（§6）

/// 每個實驗對 Music 送出的指令數（讀取不計）。達上限即停，須重新取得使用者同意，不「另計」。
public struct OperationBudget: Sendable, Equatable {
    public enum Experiment: String, Codable, Sendable, CaseIterable {
        case preflight, b3, b2, b4, b6Baseline, b6Loaded, b5, b5Play, b1, n1, n2, fp01, restore

        /// sprint-0-detail.md §6 硬上限表
        public var cap: Int {
            switch self {
            case .preflight: 40
            case .b3: 60
            case .b2: 220
            case .b4: 100
            case .b6Baseline: 110
            case .b6Loaded: 170
            case .b5: 320
            case .b5Play: 70
            case .b1: 30
            case .n1: 4
            case .n2: 8
            // F-P-01 ③：捷徑 preflight 成功路徑 1＋正式 20 次＋重做餘裕（s0-report.md「N1 後續方案」）
            case .fp01: 30
            case .restore: 70
            }
        }
    }

    public let experiment: Experiment
    public private(set) var used = 0

    public init(experiment: Experiment) {
        self.experiment = experiment
    }

    public var remaining: Int { experiment.cap - used }

    /// 預扣 `count` 次；超過上限就整筆拒絕、不扣
    public mutating func spend(_ count: Int = 1) -> Bool {
        guard used + count <= experiment.cap else { return false }
        used += count
        return true
    }
}

// MARK: 快照與還原（§4.4）

public struct MusicSnapshot: Codable, Sendable, Equatable {
    public let trackID: String?
    public let position: Double?
    public let state: PlayerStateValue
    public let airPlayDeviceIDs: Set<String>
    public let contextHash: String?
    public let queueHash: String?

    public init(trackID: String?, position: Double?, state: PlayerStateValue, airPlayDeviceIDs: Set<String>,
                contextHash: String?, queueHash: String?) {
        self.trackID = trackID
        self.position = position
        self.state = state
        self.airPlayDeviceIDs = airPlayDeviceIDs
        self.contextHash = contextHash
        self.queueHash = queueHash
    }
}

public struct RestoreCheck: Sendable, Equatable {
    public enum MustRestore: String, Codable, Sendable { case track, position, state, airPlay }
    public enum RecordOnly: String, Codable, Sendable { case context, queue }

    public static let positionTolerance = 2.0

    public let unrestored: [MustRestore]
    public let recordOnlyChanges: [RecordOnly]

    public init(before: MusicSnapshot, after: MusicSnapshot) {
        let mustRestore: [(MustRestore, Bool)] = [
            (.track, before.trackID == after.trackID),
            (.position, Self.positionMatches(before.position, after.position)),
            (.state, before.state == after.state),
            (.airPlay, before.airPlayDeviceIDs == after.airPlayDeviceIDs),
        ]
        unrestored = mustRestore.filter { !$0.1 }.map(\.0)

        let recordOnly: [(RecordOnly, Bool)] = [
            (.context, before.contextHash == after.contextHash),
            (.queue, before.queueHash == after.queueHash),
        ]
        recordOnlyChanges = recordOnly.filter { !$0.1 }.map(\.0)
    }

    private static func positionMatches(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a - b) <= positionTolerance
    }
}
