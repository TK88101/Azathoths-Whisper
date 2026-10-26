#if os(macOS)
import AppKit
import Darwin
import Foundation
import os
import RemoteProtocol

// 所有對 Music 的 Apple Event 都經這條序列（sprint-4-detail.md §3、§4.4）。只承載同步短操作：
// 每個方法內不 await、不睡；等待（時鐘、子行程、Queue.dat 輪詢）一律在呼叫端、lane 之外編排。
// 每次操作前找 Music 的 PID：沒在跑＝notRunning、不建立 SB 物件、不送事件；在跑就綁該 PID 建一個新的腳本物件
// （綁 PID 的 SBApplication 在 Music 結束後回 -600、不會把它叫起來；#4-0 P1-d）。每次新建也讓 lastError 只屬於這次操作。

public enum MusicLaneError: Error, Equatable, Sendable {
    case notRunning
    /// Music 自動化權限被拒（AE -1743）
    case notAuthorized
    /// 其他 Apple Event 錯誤（含逾時 -1712）：該操作視為未生效
    case failed(code: Int)

    static func map(_ code: Int) -> MusicLaneError {
        switch code {
        case -1743: .notAuthorized
        case -600, -609: .notRunning   // procNotFound、connectionInvalid
        default: .failed(code: code)
        }
    }
}

/// Music 的 persistent ID：16 位大寫十六進位（ScriptingBridge 端的形式；協定上一律小寫）。
/// 放在 TrackLookup.swift 之外：該檔依 echo_gate E3 不得出現計數或列舉
enum MusicPersistentID {
    static func isValid(_ id: String) -> Bool {
        id.utf8.count == 16 && id.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x46).contains($0) }
    }
}

/// 一次讀回的播放狀態（ID 一律小寫十六進位）
public struct MusicSnapshot: Sendable, Equatable {
    public let state: PlaybackState
    public let trackID: String?
    public let duration: Double?
    public let position: Double

    /// 公開只為讓 `PlaybackMusic` 的外部替身（Azathoth 的中繼測試）能構造狀態。
    ///
    /// 所有狀態都經這裡：非有限值（串流、電台等邊界）不進事件——事件編碼遇 NaN／∞ 會崩（security review MEDIUM-2）。
    /// 曲長非有限或 ≤ 0＝未知（nil）；位置非有限＝0、負值夾到 0；
    /// 曲目 ID 空字串＝沒有目前曲（#4-1 實測：換歌瞬間 Music 會回報空 ID）
    public init(state: PlaybackState, trackID: String?, duration: Double?, position: Double) {
        self.state = state
        self.trackID = trackID?.isEmpty == true ? nil : trackID
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.position = position.isFinite ? max(0, position) : 0
    }
}

extension PlaybackEvent {
    /// 由一次讀回的狀態建事件（輪詢推送與控制回覆共用）。genius 必填：Bridge 建的事件一律帶值（CR-030）
    init(snapshot: MusicSnapshot, albumID: String?, sampledAt: Double, genius: GeniusAvailability) {
        self.init(availability: .ok, trackID: snapshot.trackID, albumID: albumID, state: snapshot.state,
                  position: snapshot.position, duration: snapshot.duration, sampledAt: sampledAt, genius: genius)
    }

    /// Music 未開或未授權：沒有目前曲
    static func unavailable(_ availability: PlaybackAvailability, at time: Double, genius: GeniusAvailability) -> PlaybackEvent {
        PlaybackEvent(availability: availability, trackID: nil, albumID: nil, state: .stopped, position: 0, duration: nil,
                      sampledAt: time, genius: genius)
    }
}

/// 找 Music 的程序（外部邊界：正式＝NSRunningApplication；測試＝替身）
public protocol MusicProcessLocating: Sendable {
    func musicPID() -> pid_t?
}

/// 程序清單查不到時，退回上一次查到、且以 PID 直接確認仍是 Music 的程序（#4-1 N-01 真機：Music 開著，清單偶爾短暫查不到）。
/// 確認失敗即忘記，不會綁到別的程序。清單以 bundle ID 查到的新 PID 也要確認是 Music 本體（同使用者可自建同 bundle ID 的 app；
/// S4 後半 security LOW-4）；同一個 PID 只確認一次
public struct MusicPIDResolver: Sendable {
    private var remembered: pid_t?
    public init() {}

    mutating func resolve(listed: pid_t?, isMusic: (pid_t) -> Bool) -> pid_t? {
        if let listed {
            guard listed == remembered || isMusic(listed) else { return nil }
            remembered = listed
            return listed
        }
        guard let remembered, isMusic(remembered) else {
            remembered = nil
            return nil
        }
        MusicLane.trace("pid-fallback")
        return remembered
    }

    /// Music 本體的執行檔（系統內建位置固定；只認 `Music.app/Contents/MacOS/Music`）
    static func isMusicExecutable(_ path: String?) -> Bool {
        path?.hasSuffix("/Music.app/Contents/MacOS/Music") == true && path?.hasPrefix("/System/Applications/") == true
    }

    /// 由核心取 PID 的執行檔路徑來確認（不經 LaunchServices：清單查不到的同一瞬間它也會失敗，#4-1 N-01 真機）
    static func processIsMusic(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return isMusicExecutable(String(cString: buffer))
    }
}

/// Music 剛暫停時先回報「上一次暫停的位置」、0.1–0.5 s 後才更新（#4-1 D2 真機）——iPad 進度條會先跳回再跳正，每次暫停也推兩筆。
/// ①上一次讀到同一首「播放中」、這次「暫停」而位置倒退＝舊值，改用它實際停下的位置（上次位置＋經過時間）；
///   之後仍讀到同一個舊值就維持，讀到不再倒退的值就用真值。已在暫停中再倒退＝真的拖回，不動。
/// ②按下暫停的瞬間 Music 可能還回報「播放中」、位置卻已是上次暫停時的值（21:38:03）：位置等於上次暫停的位置、
///   又明顯落後外推值＝舊值，同樣改用外推值。播放中拖回到別的位置不動
struct StalePauseFilter {
    private static let tolerance = 0.5
    private static let sameValue = 0.1
    private var last: (snapshot: MusicSnapshot, at: Double, corrected: Bool)?
    /// 同一首最近一次「真的」暫停位置（Music 之後會拿它當舊值回報）
    private var settledPause: Double?

    mutating func correct(_ snapshot: MusicSnapshot, at now: Double) -> MusicSnapshot {
        if last?.snapshot.trackID != snapshot.trackID { settledPause = nil }
        let stopped = expectedPosition(for: snapshot, at: now)
        var result = snapshot
        var corrected = false
        if let stopped, snapshot.position + Self.tolerance < stopped {
            let capped = snapshot.duration.map { min(stopped, $0) } ?? stopped
            result = MusicSnapshot(state: snapshot.state, trackID: snapshot.trackID, duration: snapshot.duration, position: capped)
            corrected = true
        }
        if result.state == .paused, !corrected { settledPause = result.position }
        last = (result, now, corrected)
        return result
    }

    /// 這次讀回若是舊值時該有的位置；nil＝不是會出現舊值的情形
    private func expectedPosition(for snapshot: MusicSnapshot, at now: Double) -> Double? {
        guard let last, snapshot.trackID != nil, snapshot.trackID == last.snapshot.trackID else { return nil }
        switch (snapshot.state, last.snapshot.state) {
        case (.paused, .playing): return last.snapshot.position + (now - last.at)
        case (.paused, .paused) where last.corrected: return last.snapshot.position
        case (.playing, .playing):
            guard let settledPause, abs(snapshot.position - settledPause) < Self.sameValue else { return nil }
            return last.snapshot.position + (now - last.at)
        default: return nil
        }
    }
}

public final class RunningMusicLocator: MusicProcessLocating, @unchecked Sendable {
    private static let bundleID = "com.apple.Music"
    private let lock = NSLock()
    private var resolver = MusicPIDResolver()

    public init() {}

    public func musicPID() -> pid_t? {
        let listed = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .first { !$0.isTerminated }?.processIdentifier
        return lock.withLock {
            resolver.resolve(listed: listed, isMusic: MusicPIDResolver.processIsMusic)
        }
    }
}

/// 綁定某個 Music 程序的腳本介面（正式＝`SBMusicScripting`；測試＝替身）。同步，只在 MusicLane 的序列上呼叫。
/// 每個方法都只用白名單選擇器（CR-006④）；錯誤以 `takeLastErrorCode()` 取回（取後清除）
public protocol MusicScripting: AnyObject {
    func playerState() -> UInt32?
    func currentTrack() -> (id: String, duration: Double?)?
    func playerPosition() -> Double?
    func setPlayerPosition(_ seconds: Double)
    func playPause()
    func nextTrack()
    func previousTrack()
    /// 以 persistent ID（大寫十六進位）查找並單次播放；查不到回 false
    func playOnce(persistentID: String) -> Bool
    func airPlayDevices() -> [(id: String, kind: UInt32, selected: Bool)]
    func setAirPlayDevices(_ ids: [String]) -> Bool
    func takeLastErrorCode() -> Int?
}

public actor MusicLane {
    public typealias Factory = @Sendable (pid_t) -> any MusicScripting

    private let queue = DispatchSerialQueue(label: "com.ibridgezhao.yse.music-lane")
    private let locator: any MusicProcessLocating
    private let makeScripting: Factory

    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let uptime: @Sendable () -> Double
    private var pauseFilter = StalePauseFilter()

    public init(locator: any MusicProcessLocating = RunningMusicLocator(), makeScripting: @escaping Factory = SBMusicScripting.make,
                uptime: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.locator = locator
        self.makeScripting = makeScripting
        self.uptime = uptime
    }

    /// 一次操作：找 PID → 綁定 → 執行 → 檢查錯誤
    private func perform<T>(_ body: (any MusicScripting) -> T) throws(MusicLaneError) -> T {
        guard let pid = locator.musicPID() else {
            Self.trace("no-pid")
            throw .notRunning
        }
        let scripting = makeScripting(pid)
        let value = body(scripting)
        if let code = scripting.takeLastErrorCode() {
            Self.trace("ae-error code=\(code)")
            throw .map(code)
        }
        return value
    }

    public func snapshot() throws(MusicLaneError) -> MusicSnapshot {
        pauseFilter.correct(try read(), at: uptime())
    }

    private func read() throws(MusicLaneError) -> MusicSnapshot {
        try perform { music in
            let state = Self.state(music.playerState() ?? 0)
            let current = music.currentTrack()
            return MusicSnapshot(state: state, trackID: current.map { $0.id.lowercased() }, duration: current?.duration,
                                 position: music.playerPosition() ?? 0)
        }
    }

    public func togglePlayPause() throws(MusicLaneError) { try perform { $0.playPause() } }
    public func next() throws(MusicLaneError) { try perform { $0.nextTrack() } }
    public func previous() throws(MusicLaneError) { try perform { $0.previousTrack() } }
    public func seek(to seconds: Double) throws(MusicLaneError) { try perform { $0.setPlayerPosition(seconds) } }

    /// 降級「只播這首」（設計 §5.3-4；參數沿用 S0 B1 的 playOnce(false)）
    public func playOnce(trackID: String) throws(MusicLaneError) -> Bool {
        try perform { $0.playOnce(persistentID: trackID.uppercased()) }
    }

    public func outputs() throws(MusicLaneError) -> [OutputDeviceSummary] {
        try perform { music in
            music.airPlayDevices().map { OutputDeviceSummary(id: $0.id.lowercased(), kind: $0.kind, selected: $0.selected) }
        }
    }

    public func setOutputs(_ ids: [String]) throws(MusicLaneError) -> Bool {
        try perform { $0.setAirPlayDevices(ids.map { $0.uppercased() }) }
    }

    /// DEBUG 診斷（#4-1）：只記錯誤代碼；Release 不含
    static func trace(_ message: @autoclosure () -> String) { RelayTrace.notice("lane \(message())") }

    /// Music 的 player state 四字碼：'kPSP' 播放、'kPSF'／'kPSR' 快轉倒轉（視為播放）、'kPSp' 暫停、其餘視為停止
    static func state(_ raw: UInt32) -> PlaybackState {
        switch raw {
        case 0x6B50_5350, 0x6B50_5346, 0x6B50_5352: .playing
        case 0x6B50_5370: .paused
        default: .stopped
        }
    }
}
#endif
