import CryptoKit
import Foundation

// 播放狀態解碼、上下首 oracle、佇列 ID 序列、B2 判定（sprint-0-detail.md §4.3、§4.3.2）。

public enum PlayerStateCode {
    /// Music 的 `player state` 四字碼：'kPSP' 播放、'kPSp' 暫停、'kPSS' 停止
    public static func decode(_ raw: UInt32) -> PlayerStateValue {
        switch raw {
        case 0x6B50_5350: .playing
        case 0x6B50_5370: .paused
        case 0x6B50_5353: .stopped
        default: .other
        }
    }
}

/// 以播放脈絡（`current playlist` 的 tracks 序列）推算下一首／上一首。序列有重複曲目時位置不唯一，拒收。
public struct PlaybackOracle: Sendable, Equatable {
    public let sequence: [String]
    private let index: [String: Int]

    public init?(sequence: [String]) {
        var index: [String: Int] = [:]
        for (position, id) in sequence.enumerated() {
            guard index.updateValue(position, forKey: id) == nil else { return nil }
        }
        self.sequence = sequence
        self.index = index
    }

    public func expectedNext(after id: String) -> String? {
        guard let i = index[id], i + 1 < sequence.count else { return nil }
        return sequence[i + 1]
    }

    public func expectedPrevious(before id: String) -> String? {
        guard let i = index[id], i > 0 else { return nil }
        return sequence[i - 1]
    }

    /// 從第 1 首起跑、前進 `steps` 首都還在序列內（§4.3.3）
    public func hasRoom(forSteps steps: Int) -> Bool { sequence.count > steps }

    /// 脈絡身分的一部分：序列內容與順序的雜湊（§4.3.2 每樣本比對）
    public var contextHash: String {
        SHA256.hash(data: Data(sequence.joined(separator: ",").utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// Music 的佇列檔（二進位 plist）→ persistentID 序列。格式同 Azathoth `QueueSnapshot.parse`；
/// 只讀順序模式，任何一項缺 `tID` 或結構不符就整份不可用（不捏造）。
public enum QueueIDs {
    public static func parse(_ data: Data) -> [String]? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let segments = root["sega"] as? [[String: Any]], segments.count == 1,
              let items = segments[0]["items"] as? [String: Any],
              (items["shuffleMode"] as? String ?? "off") == "off",
              let list = (items["list"] as? [String: Any])?["items"] as? [String: Any],
              let raw = list["iar"] as? [[String: Any]]
        else { return nil }
        let ids = raw.compactMap { entry -> String? in
            guard let spec = (entry["pm"] as? [String: Any])?["piObjSpec"] as? [String: Any],
                  let trackID = (spec["tID"] as? NSNumber)?.int64Value
            else { return nil }
            return String(format: "%016llX", UInt64(bitPattern: trackID))
        }
        return ids.count == raw.count ? ids : nil
    }
}

// MARK: B1 抽樣（§4.3 sample-ids：依位置類型分層、固定種子）

/// SplitMix64：固定種子即可重現抽樣結果
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum StratifiedSampler {
    /// 每種位置類型先各取 1 首，其餘從剩下的曲目隨機補滿；同一首不會被取兩次
    public static func sample(_ items: [(id: String, kind: String)], count: Int, seed: UInt64) -> [String] {
        var generator = SeededGenerator(seed: seed)
        let groups = Dictionary(grouping: items, by: \.kind)
            .sorted { $0.key < $1.key }
            .map { $0.value.map(\.id).shuffled(using: &generator) }
        let firsts = groups.compactMap(\.first)
        let rest = groups.flatMap { $0.dropFirst() }.shuffled(using: &generator)
        return Array((firsts + rest).prefix(count))
    }
}

// MARK: B2 暫停／繼續、下一首、上一首

public struct B2Check: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case pause, resume, next, previous }

    public let kind: Kind
    public let expectedID: String?
    public let readID: String?
    public let expectedState: PlayerStateValue
    public let readState: PlayerStateValue?

    public init(kind: Kind, expectedID: String?, readID: String?, expectedState: PlayerStateValue,
                readState: PlayerStateValue?) {
        self.kind = kind
        self.expectedID = expectedID
        self.readID = readID
        self.expectedState = expectedState
        self.readState = readState
    }

    public var isCorrect: Bool {
        expectedID != nil && readID == expectedID && readState == expectedState
    }
}

public enum B2Verdict {
    public static let requiredPerKind = 20

    /// 四種各 20 筆、全部正確才通過（上游「各 20 次全部生效，且讀回的狀態正確」）
    public static func judge(_ checks: [B2Check]) -> Verdict {
        let byKind = Dictionary(grouping: checks, by: \.kind)
        guard B2Check.Kind.allCases.allSatisfy({ (byKind[$0]?.count ?? 0) >= requiredPerKind }) else {
            return .undetermined
        }
        return checks.allSatisfy(\.isCorrect) ? .pass : .fail
    }
}
