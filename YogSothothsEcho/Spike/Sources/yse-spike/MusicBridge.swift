import AppKit
import Foundation
import ObjectiveC
import ScriptingBridge
import SpikeCore

// yse-spike 唯一 import ScriptingBridge 的檔案（spike_gate.sh 限定）。sprint-0-detail.md §4.2。
// 選擇器以 SpikeAllowList 為準；啟動自檢不等就拒絕執行。只讀 ID 與數值，不讀曲名。

@objc(YSESpikeMusicAppProto) protocol MusicAppProto {
    @objc optional var playerState: UInt32 { get }
    @objc optional var playerPosition: Double { get }
    @objc optional func setPlayerPosition(_ value: Double)
    @objc optional var currentTrack: SBObject { get }
    @objc optional var currentPlaylist: SBObject { get }
    @objc optional var shuffleEnabled: Bool { get }
    @objc optional var songRepeat: UInt32 { get }
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func backTrack()
    @objc optional func tracks() -> SBElementArray
    @objc optional func playlists() -> SBElementArray
    @objc optional func AirPlayDevices() -> SBElementArray
    @objc optional var currentAirPlayDevices: [SBObject] { get }
    @objc optional func setCurrentAirPlayDevices(_ value: [SBObject])
}

@objc(YSESpikeMusicTrackProto) protocol MusicTrackProto {
    @objc optional var persistentID: String { get }
    @objc optional var duration: Double { get }
    @objc optional func playOnce(_ once: Bool)
}

@objc(YSESpikePlaylistProto) protocol PlaylistProto {
    @objc optional var persistentID: String { get }
    @objc optional func tracks() -> SBElementArray
}

@objc(YSESpikeAirPlayProto) protocol AirPlayProto {
    @objc optional var persistentID: String { get }
    @objc optional var selected: Bool { get }
    @objc optional var kind: UInt32 { get }
}

extension SBApplication: MusicAppProto {}
extension SBObject: MusicTrackProto, PlaylistProto, AirPlayProto {}

/// 一次 Apple Event 的結果：值、牆鐘耗時、SB 的錯誤碼
struct Timed<Value> {
    let value: Value
    let milliseconds: Double
    let errorCode: Int?
}

@MainActor
final class MusicBridge {
    static let bundleIdentifier = "com.apple.Music"

    private let app: SBApplication
    private var music: MusicAppProto { app }

    private init(app: SBApplication) {
        self.app = app
    }

    // MARK: 啟動自檢（不建立 Music 連線）

    /// 兩層：①四個協定的選擇器完全等於白名單；②SBApplication／SBObject 採納的協定（系統 NS／OS_ 前綴除外）
    /// 完全等於這四個——另加第五個協定（例如宣告 delete）會在這裡被抓到
    nonisolated static func selfCheck() -> [String: SelectorAudit] {
        var audits = SpikeAllowList.protocols.reduce(into: [String: SelectorAudit]()) { result, entry in
            result[entry.key] = SelectorAudit.compare(declared: declaredSelectors(entry.key), allowed: entry.value)
        }
        let adopted = adoptedProtocols(SBApplication.self).union(adoptedProtocols(SBObject.self))
            .filter { !$0.hasPrefix("NS") && !$0.hasPrefix("OS_") }
        audits["(adopted protocols)"] = SelectorAudit.compare(declared: adopted, allowed: Set(SpikeAllowList.protocols.keys))
        return audits
    }

    nonisolated private static func adoptedProtocols(_ cls: AnyClass) -> Set<String> {
        var count: UInt32 = 0
        guard let list = class_copyProtocolList(cls, &count) else { return [] }
        defer { free(UnsafeMutableRawPointer(list)) }
        return Set((0..<Int(count)).map { NSStringFromProtocol(list[$0]) })
    }

    nonisolated private static func declaredSelectors(_ name: String) -> Set<String> {
        guard let proto = objc_getProtocol(name) else { return [] }
        let kinds: [(required: Bool, instance: Bool)] = [(true, true), (true, false), (false, true), (false, false)]
        let names = kinds.flatMap { kind -> [String] in
            var count: UInt32 = 0
            guard let list = protocol_copyMethodDescriptionList(proto, kind.required, kind.instance, &count) else {
                return []
            }
            defer { free(list) }
            return (0..<Int(count)).compactMap { list[$0].name.map(NSStringFromSelector) }
        }
        return Set(names)
    }

    /// Music 沒開就回 nil——不代為啟動（基本設計 §5.4）。自檢不過也回 nil。
    /// 以程序 ID 綁定（同 Azathoth 的 MusicAppleEventsClient）：Music 中途結束時事件回 -600，不會把它重新拉起。
    static func connect() -> MusicBridge? {
        guard selfCheck().values.allSatisfy(\.isExact),
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              let app = SBApplication(processIdentifier: running.processIdentifier)
        else { return nil }
        return MusicBridge(app: app)
    }

    // MARK: 計時包裝

    private func timed<Value>(_ body: () -> Value) -> Timed<Value> {
        let started = ContinuousClock.now
        let value = body()
        let code = (app.lastError() as NSError?)?.code
        return Timed(value: value, milliseconds: Self.milliseconds(since: started), errorCode: code)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    private static func objects(_ elements: SBElementArray?) -> [SBObject] {
        (elements ?? SBElementArray()).compactMap { $0 as? SBObject }
    }

    private static func trackID(_ object: SBObject) -> String? { (object as MusicTrackProto).persistentID }

    // MARK: 讀取

    func state() -> Timed<PlayerStateValue> {
        timed { PlayerStateCode.decode(music.playerState ?? 0) }
    }

    func currentTrackID() -> Timed<String?> {
        timed { music.currentTrack.flatMap(Self.trackID) }
    }

    func position() -> Timed<Double?> {
        timed { music.playerPosition }
    }

    func currentDuration() -> Timed<Double?> {
        timed { music.currentTrack.flatMap { ($0 as MusicTrackProto).duration } }
    }

    func shuffleAndRepeat() -> Timed<(shuffle: Bool?, repeatMode: UInt32?)> {
        timed { (music.shuffleEnabled, music.songRepeat) }
    }

    /// 播放脈絡上限：逐首讀 ID（每首一次 Apple Event），整個曲庫當脈絡時會送上萬次，故超過就不讀
    static let maxContextTracks = 200

    /// 播放脈絡：current playlist 的身分與 tracks 的 persistentID 序列；超過上限回空序列
    func context() -> Timed<(playlistID: String?, sequence: [String])> {
        timed {
            guard let playlist = music.currentPlaylist.map({ $0 as PlaylistProto }) else { return (nil, []) }
            guard let tracks = playlist.tracks?(), tracks.count <= Self.maxContextTracks else {
                return (playlist.persistentID, [])
            }
            return (playlist.persistentID, Self.objects(tracks).compactMap(Self.trackID))
        }
    }

    /// 唯讀：目前播放脈絡的首數與每首長度（超過上限只回首數）
    func contextDurations() -> (count: Int, durations: [Double]) {
        guard let playlist = music.currentPlaylist.map({ $0 as PlaylistProto }), let tracks = playlist.tracks?() else {
            return (0, [])
        }
        guard tracks.count <= Self.maxContextTracks else { return (tracks.count, []) }
        return (tracks.count, Self.objects(tracks).compactMap { ($0 as MusicTrackProto).duration })
    }

    func airPlaySelection() -> Timed<Set<String>> {
        timed { Set((music.currentAirPlayDevices ?? []).compactMap { ($0 as AirPlayProto).persistentID }) }
    }

    func airPlayDeviceIDs() -> Timed<[String]> {
        timed { Self.objects(music.AirPlayDevices?()).compactMap { ($0 as AirPlayProto).persistentID } }
    }

    // MARK: 控制

    func seek(to seconds: Double) -> Timed<Void> {
        timed { music.setPlayerPosition?(seconds) }
    }

    func playPause() -> Timed<Void> {
        timed { music.playpause?() }
    }

    func next() -> Timed<Void> {
        timed { music.nextTrack?() }
    }

    func previous() -> Timed<Void> {
        timed { music.backTrack?() }
    }

    /// 以 persistentID 找曲目並播放（含查找；B5 計時邊界，§4.3）。查找的耗時另回。
    func play(trackID: String, once: Bool = false) -> Timed<(found: Bool, lookupMs: Double)> {
        timed {
            let lookupStart = ContinuousClock.now
            let match = music.tracks?().filtered(using: NSPredicate(format: "persistentID == %@", trackID)).first
            let lookupMs = Self.milliseconds(since: lookupStart)
            guard let track = match as? SBObject else { return (false, lookupMs) }
            (track as MusicTrackProto).playOnce?(once)
            return (true, lookupMs)
        }
    }

    /// F-P-01 ②：曲目從「以 persistent ID 指定的 playlist」裡取，而非 application 層 tracks（對照 N1）
    func play(trackID: String, inPlaylist playlistID: String) -> Timed<(found: Bool, playlistTrackCount: Int?)> {
        timed {
            let byID = { (id: String) in NSPredicate(format: "persistentID == %@", id) }
            guard let playlist = music.playlists?().filtered(using: byID(playlistID)).first as? SBObject,
                  let tracks = (playlist as PlaylistProto).tracks?()
            else { return (false, nil) }
            guard let track = tracks.filtered(using: byID(trackID)).first as? SBObject else {
                return (false, tracks.count)
            }
            (track as MusicTrackProto).playOnce?(false)
            return (true, tracks.count)
        }
    }

    func selectAirPlay(_ ids: Set<String>) -> Timed<Bool> {
        timed {
            let chosen = Self.objects(music.AirPlayDevices?())
                .filter { ids.contains(($0 as AirPlayProto).persistentID ?? "") }
            guard chosen.count == ids.count else { return false }
            music.setCurrentAirPlayDevices?(chosen)
            return true
        }
    }
}
