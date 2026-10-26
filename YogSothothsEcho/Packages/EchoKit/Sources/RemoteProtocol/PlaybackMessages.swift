import Foundation

// 播放控制訊息的 body（sprint-4-detail.md §4.3；kind 已在 MessageKind）。`isValid` 只驗形狀，
// Mac 收到時不合法＝invalidRequest、不執行；「合法但狀態已變」（曲目不是目前曲、超過曲長）由 Mac 回 notApplied。
// ID 一律 16 位小寫十六進位（persistent ID；Music 給的大寫由 Bridge 轉小寫）。

public struct TrackSummary: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// 逐曲歌手（CR-017；唱片標籤用）。沒有時空字串
    public let artist: String
    public let disc: Int
    public let number: Int
    /// 秒；ITLibrary 沒有時為 nil
    public let duration: Double?

    public init(id: String, title: String, artist: String = "", disc: Int, number: Int, duration: Double?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.disc = disc
        self.number = number
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey { case id, title, artist, disc, number, duration }

    /// 舊 Mac（CR-017 前）的回覆沒有 artist：解成空字串，協定版本維持 v1
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        disc = try c.decode(Int.self, forKey: .disc)
        number = try c.decode(Int.self, forKey: .number)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
    }
}

/// S4 控制用極簡曲目選擇器（CR-013(f)）；依完整訊息位元組預算分頁，結束與否只看 nextCursor
public struct AlbumTracksRequest: Codable, Sendable, Equatable {
    public let albumID: String
    public let cursor: String?

    public init(albumID: String, cursor: String?) {
        self.albumID = albumID
        self.cursor = cursor
    }

    public var isValid: Bool { HexID.isValid(albumID) && (cursor.map { CatalogCursor.decode($0) != nil } ?? true) }
}

public struct AlbumTracksResponse: Codable, Sendable, Equatable {
    public let albumID: String
    public let version: String
    /// 命名用 songs：echo_gate E3 禁止 Bridge 內出現 `tracks` 一詞（CR-009），Bridge 要建這個回應
    public let songs: [TrackSummary]
    public let nextCursor: String?
    /// 許可閘門結果：false＝點歌只會播這首（iPad 事先提示）
    public let contextPlayable: Bool

    public init(albumID: String, version: String, songs: [TrackSummary], nextCursor: String?, contextPlayable: Bool) {
        self.albumID = albumID
        self.version = version
        self.songs = songs
        self.nextCursor = nextCursor
        self.contextPlayable = contextPlayable
    }
}

public struct PlayTrackRequest: Codable, Sendable, Equatable {
    public let trackID: String
    public let albumID: String

    public init(trackID: String, albumID: String) {
        self.trackID = trackID
        self.albumID = albumID
    }

    public var isValid: Bool { HexID.isValid(trackID) && HexID.isValid(albumID) }
}

public enum PlayOutcomeKind: String, Codable, Sendable {
    case verified, degraded, indeterminate
}

/// play.result 的原因碼；每個原因只屬於一種結果（CR-014：不再有事前內容校驗的 modified／unverified）
public enum PlayReason: String, Codable, Sendable, CaseIterable {
    case gateEmptyTitle, gateInconsistentTitle, gateAmbiguousTitle, gateOrderUndefined
    case shortcutMissing, shortcutFailed, queueMismatch
    case targetTimeout, queueTimeout, shortcutUnresponsive, lateChange, manualChange, fallbackFailed

    public var outcome: PlayOutcomeKind {
        switch self {
        case .gateEmptyTitle, .gateInconsistentTitle, .gateAmbiguousTitle, .gateOrderUndefined,
             .shortcutMissing, .shortcutFailed, .queueMismatch: .degraded
        case .targetTimeout, .queueTimeout, .shortcutUnresponsive, .lateChange, .manualChange, .fallbackFailed: .indeterminate
        }
    }
}

public struct PlayResult: Codable, Sendable, Equatable {
    public let outcome: PlayOutcomeKind
    public let reason: PlayReason?

    public init(outcome: PlayOutcomeKind, reason: PlayReason?) {
        self.outcome = outcome
        self.reason = reason
    }

    /// verified 不帶原因；其餘必須帶屬於自己的原因（兩端解碼後都驗）
    public var isValid: Bool { outcome == .verified ? reason == nil : reason?.outcome == outcome }
}

public struct SeekRequest: Codable, Sendable, Equatable {
    /// 只對這首生效：送達時目前曲已換＝notApplied
    public let trackID: String
    public let seconds: Double

    public init(trackID: String, seconds: Double) {
        self.trackID = trackID
        self.seconds = seconds
    }

    public var isValid: Bool { HexID.isValid(trackID) && seconds.isFinite && seconds >= 0 }
}

public enum PlaybackState: String, Codable, Sendable, Equatable {
    case playing, paused, stopped

    /// 照常播放的話，`elapsed` 秒後的位置：播放中才往前走（不夾到曲長或 0——邊界由各呼叫端自己處理）
    public func projected(_ position: Double, after elapsed: Double) -> Double {
        self == .playing ? position + elapsed : position
    }
}

public enum PlaybackAvailability: String, Codable, Sendable, Equatable {
    case ok, musicNotRunning, automationDenied
}

/// Mac 端能不能按 Genius（CR-030）：權限屬 Azathoth 本身，與 Music 是否在跑無關
public enum GeniusAvailability: String, Codable, Sendable, Equatable {
    case ready, needsAccessibility
}

public struct PlaybackEvent: Codable, Sendable, Equatable {
    public let availability: PlaybackAvailability
    public let trackID: String?
    public let albumID: String?
    public let state: PlaybackState
    public let position: Double
    public let duration: Double?
    /// Mac 單調時鐘秒數：只用來丟棄同一連線世代內的亂序事件，不跨裝置相減（§4.8）
    public let sampledAt: Double
    /// 新 Mac 每筆事件都帶；nil＝舊 Mac（不支援 Genius，iPad 不顯示鈕）。未知值解碼失敗
    public let genius: GeniusAvailability?

    public init(availability: PlaybackAvailability, trackID: String?, albumID: String?, state: PlaybackState,
                position: Double, duration: Double?, sampledAt: Double, genius: GeniusAvailability? = nil) {
        self.availability = availability
        self.trackID = trackID
        self.albumID = albumID
        self.state = state
        self.position = position
        self.duration = duration
        self.sampledAt = sampledAt
        self.genius = genius
    }
}

public enum ControlOutcome: String, Codable, Sendable {
    case applied, notApplied
}

/// toggle／next／previous／seek 的回覆：讀回的狀態放在同一則回覆裡（CR-013(g)）
public struct ControlResult: Codable, Sendable, Equatable {
    public let outcome: ControlOutcome
    public let playback: PlaybackEvent

    public init(outcome: ControlOutcome, playback: PlaybackEvent) {
        self.outcome = outcome
        self.playback = playback
    }
}

/// 白名單沒有 `name`（CR-006④）：只給 kind 與是否選取，iPad 以「kind＋序號」顯示
public struct OutputDeviceSummary: Codable, Sendable, Equatable {
    public let id: String
    public let kind: UInt32
    public let selected: Bool

    public init(id: String, kind: UInt32, selected: Bool) {
        self.id = id
        self.kind = kind
        self.selected = selected
    }
}

public struct OutputListResponse: Codable, Sendable, Equatable {
    public let devices: [OutputDeviceSummary]
    public init(devices: [OutputDeviceSummary]) { self.devices = devices }
}

public struct OutputSetRequest: Codable, Sendable, Equatable {
    public let deviceIDs: [String]
    public init(deviceIDs: [String]) { self.deviceIDs = deviceIDs }

    public var isValid: Bool {
        (1...PlaybackLimits.maxOutputDevices).contains(deviceIDs.count)
            && Set(deviceIDs).count == deviceIDs.count && deviceIDs.allSatisfy(HexID.isValid)
    }
}
