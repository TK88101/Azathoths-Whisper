#if os(macOS)
import Foundation
import ScriptingBridge

// MusicScripting 的正式實作：ScriptingBridge 對 Music.app，只經白名單內的四個 @objc 協定（CR-006④、CR-009）。
// D12（sprint-1-detail.md §4.2）：SB 類別採用協定的 extension 與 Azathoth 白名單測試的允許集合擴充同一個 commit。

extension SBApplication: MusicRemoteAppProto {}
extension SBObject: MusicRemoteTrackProto, MusicRemoteAirPlayProto {}

public final class SBMusicScripting: MusicScripting {
    /// AE reply 的等待上限（ticks＝1/60 s）：PlaybackLimits.appleEventTimeout 2 s
    static let timeoutTicks = 120
    /// errAENoSuchObject：沒有目前曲目時讀 currentTrack 的屬性會回它，不算錯誤
    static let noSuchObject = -1728

    private let app: SBApplication
    private var music: MusicRemoteAppProto { app }

    init(app: SBApplication) {
        self.app = app
        app.timeout = Self.timeoutTicks
    }

    /// 綁定 PID（不以 bundle id 建立：那樣送事件時會把 Music 叫起來）；建不出來回一個永遠回 -600 的替代
    @Sendable public static func make(_ pid: pid_t) -> any MusicScripting {
        guard let app = SBApplication(processIdentifier: pid) else { return Unbound() }
        return SBMusicScripting(app: app)
    }

    public func playerState() -> UInt32? { music.playerState }

    public func currentTrack() -> (id: String, duration: Double?)? {
        guard let track = music.currentTrack, let id = (track as MusicRemoteTrackProto).persistentID else { return nil }
        return (id, (track as MusicRemoteTrackProto).duration)
    }

    public func playerPosition() -> Double? { music.playerPosition }
    public func setPlayerPosition(_ seconds: Double) { music.setPlayerPosition?(seconds) }
    public func playPause() { music.playpause?() }
    public func nextTrack() { music.nextTrack?() }
    public func previousTrack() { music.previousTrack?() }

    public func playOnce(persistentID: String) -> Bool {
        guard let track = TrackLookup.find(persistentID: persistentID, in: app) else { return false }
        (track as MusicRemoteTrackProto).playOnce?(false)
        return true
    }

    public func airPlayDevices() -> [(id: String, kind: UInt32, selected: Bool)] {
        guard let all = music.AirPlayDevices?() else { return [] }
        var result: [(id: String, kind: UInt32, selected: Bool)] = []
        for case let device as SBObject in all {
            let proto = device as MusicRemoteAirPlayProto
            guard let id = proto.persistentID else { continue }
            result.append((id, proto.kind ?? 0, proto.selected ?? false))
        }
        return result
    }

    public func setAirPlayDevices(_ ids: [String]) -> Bool {
        guard let all = music.AirPlayDevices?() else { return false }
        var chosen: [SBObject] = []
        for case let device as SBObject in all {
            if let id = (device as MusicRemoteAirPlayProto).persistentID, ids.contains(id) { chosen.append(device) }
        }
        guard chosen.count == ids.count else { return false }
        music.setCurrentAirPlayDevices?(chosen)
        return true
    }

    /// lastError 沒有清除 API；每次操作新建本物件，所以它只屬於這次操作。
    /// 沒有目前曲目（-1728）不算錯誤：讀 currentTrack 的屬性時才會出現，查找不到則由 playOnce 的回傳值表達
    public func takeLastErrorCode() -> Int? {
        guard let code = (app.lastError() as NSError?)?.code, code != 0, code != Self.noSuchObject else { return nil }
        return code
    }
}

/// 綁不到 PID（程序剛好結束）：一律回「程序不存在」
private final class Unbound: MusicScripting {
    func playerState() -> UInt32? { nil }
    func currentTrack() -> (id: String, duration: Double?)? { nil }
    func playerPosition() -> Double? { nil }
    func setPlayerPosition(_ seconds: Double) {}
    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func playOnce(persistentID: String) -> Bool { false }
    func airPlayDevices() -> [(id: String, kind: UInt32, selected: Bool)] { [] }
    func setAirPlayDevices(_ ids: [String]) -> Bool { false }
    func takeLastErrorCode() -> Int? { -600 }
}
#endif
