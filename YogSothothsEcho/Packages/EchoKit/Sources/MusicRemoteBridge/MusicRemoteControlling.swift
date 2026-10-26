#if os(macOS)
// 型別層的播控邊界（基本設計 §3、§5.3；N-06）：播控方法只宣告在這裡。
// Azathoth 既有 Features／Services 不得 import 本模組（no_playback_gate.sh R5）。S1 只有協定與型別，實作在 S4。

public protocol MusicRemoteControlling: Sendable {
    func play(trackID: String, context: PlayContext) async throws -> PlayOutcome
    func togglePlayPause() async throws
    func next() async throws
    func previous() async throws
    func seek(to seconds: Double) async throws
    func outputs() async throws -> [OutputDevice]
    func setOutputs(_ deviceIDs: [String]) async throws
    func state() async throws -> PlaybackSnapshot
}

public enum PlayContext: Sendable, Equatable {
    case album(id: String)
}

/// `play.result` 的三種結果（基本設計 §4.3、CR-005）；原因碼在 S4 定為列舉
public enum PlayOutcome: Sendable, Equatable {
    case verified
    case degraded(reason: String)
    case indeterminate(reason: String)
}

public struct OutputDevice: Sendable, Equatable {
    public let id: String
    public let name: String
    public let selected: Bool

    public init(id: String, name: String, selected: Bool) {
        self.id = id
        self.name = name
        self.selected = selected
    }
}

public enum PlayerState: String, Sendable, Equatable {
    case playing, paused, stopped
}

public struct PlaybackSnapshot: Sendable, Equatable {
    public let trackID: String?
    public let state: PlayerState
    public let position: Double
    public let duration: Double?

    public init(trackID: String?, state: PlayerState, position: Double, duration: Double?) {
        self.trackID = trackID
        self.state = state
        self.position = position
        self.duration = duration
    }
}
#endif
