// B1／B3／B5 的判定（sprint-0-detail.md §4.3）。判定只吃原始樣本，不吃任何人工結論。

public enum Verdict: String, Codable, Sendable, Equatable {
    case pass, fail, undetermined
}

public enum Stats {
    /// 最近秩法：排序後第 ⌈p·n⌉ 小（1 起算）。`.infinity` 保留，讓逾時樣本能主宰高分位。
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

/// Music 的 `playerState` 解碼後的值；只取判定需要的幾種。
public enum PlayerStateValue: String, Codable, Sendable, Equatable {
    case playing, paused, stopped, other
}

// MARK: B1 以 persistent ID 指定播放

public struct PlayCheck: Codable, Sendable, Equatable {
    public let expectedID: String
    public let readID: String?
    public let state: PlayerStateValue?

    public init(expectedID: String, readID: String?, state: PlayerStateValue?) {
        self.expectedID = expectedID
        self.readID = readID
        self.state = state
    }

    public var isCorrect: Bool { readID == expectedID && state == .playing }
}

public enum B1Verdict {
    public static let requiredSamples = 20

    public static func judge(_ checks: [PlayCheck]) -> Verdict {
        guard checks.count >= requiredSamples else { return .undetermined }
        return checks.allSatisfy(\.isCorrect) ? .pass : .fail
    }
}

// MARK: B3 seek

public struct SeekCheck: Codable, Sendable, Equatable {
    public static let tolerance = 1.0

    public let target: Double
    public let readBack: Double?
    /// 送出 `setPlayerPosition:` 的時刻與讀回的時刻（秒，同一時鐘）
    public let sentAt: Double
    public let readAt: Double
    public let wasPlaying: Bool
    public let trackChanged: Bool

    public init(target: Double, readBack: Double?, sentAt: Double, readAt: Double, wasPlaying: Bool, trackChanged: Bool) {
        self.target = target
        self.readBack = readBack
        self.sentAt = sentAt
        self.readAt = readAt
        self.wasPlaying = wasPlaying
        self.trackChanged = trackChanged
    }

    /// 播放中：[目標 − 1, 目標 + (讀取 − 送出) + 1]；暫停中：|讀回 − 目標| ≤ 1。曲目已換＝失敗。
    public var isWithinTolerance: Bool {
        guard !trackChanged, let readBack else { return false }
        let lower = target - Self.tolerance
        let drift = wasPlaying ? max(readAt - sentAt, 0) : 0
        let upper = target + drift + Self.tolerance
        return readBack >= lower && readBack <= upper
    }
}

public enum B3Verdict {
    public static let requiredSamples = 20

    public static func judge(_ checks: [SeekCheck]) -> Verdict {
        guard checks.count >= requiredSamples else { return .undetermined }
        return checks.allSatisfy(\.isWithinTolerance) ? .pass : .fail
    }
}

// MARK: B4 手動操作後的狀態讀取（§4.3.1）

public struct B4Event: Codable, Sendable, Equatable {
    public enum StartSource: String, Codable, Sendable {
        /// 全域左鍵按下的時間戳（主要做法）
        case mouseDown
        /// 使用者按 Enter 的時刻（備援；含人移動滑鼠的時間，只會偏大）
        case enterKey
    }

    public enum Trigger: String, Codable, Sendable { case notification, poll }

    public let start: Double
    /// 讀到期待狀態的第一刻；nil＝始終沒讀到
    public let detectedAt: Double?
    public let startSource: StartSource
    public let trigger: Trigger?

    public init(start: Double, detectedAt: Double?, startSource: StartSource, trigger: Trigger?) {
        self.start = start
        self.detectedAt = detectedAt
        self.startSource = startSource
        self.trigger = trigger
    }

    public var isWithinLimit: Bool {
        guard let detectedAt else { return false }
        return detectedAt - start <= B4Verdict.limitSeconds
    }
}

public enum B4Verdict {
    public static let requiredEvents = 20
    public static let limitSeconds = 2.0

    /// 主要做法的超時＝不過；備援的超時只能算「不可判定」，須以主要做法重跑完整 20 筆
    public static func judge(_ events: [B4Event]) -> Verdict {
        guard events.count >= requiredEvents else { return .undetermined }
        let late = events.filter { !$0.isWithinLimit }
        if late.contains(where: { $0.startSource == .mouseDown }) { return .fail }
        return late.isEmpty ? .pass : .undetermined
    }
}

// MARK: B5 Apple Event 耗時

public struct TimedSample: Codable, Sendable, Equatable {
    public let milliseconds: Double?
    public let errorCode: Int?

    public init(milliseconds: Double?, errorCode: Int?) {
        self.milliseconds = milliseconds
        self.errorCode = errorCode
    }

    public var isError: Bool { errorCode != nil || milliseconds == nil }
}

public enum B5Verdict {
    public static let requiredSamples = 50
    public static let p95LimitMilliseconds = 300.0

    /// 錯誤或逾時一律保留並判不過（§4.3 共通規則）
    public static func judge(_ samples: [TimedSample]) -> Verdict {
        guard samples.count >= requiredSamples else { return .undetermined }
        guard !samples.contains(where: \.isError) else { return .fail }
        let p95 = Stats.percentile(samples.compactMap(\.milliseconds), 0.95) ?? .infinity
        return p95 <= p95LimitMilliseconds ? .pass : .fail
    }
}
