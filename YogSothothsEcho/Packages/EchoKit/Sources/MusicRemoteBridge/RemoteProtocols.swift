#if os(macOS)
import Foundation
import ScriptingBridge

// 執行期白名單（基本設計 §8、CR-006④）：Music 的 @objc 協定，選擇器逐協定完全等於 RemoteSelectorAllowList.expected。
// `tracks` 不在這裡：它在 TrackLookup.swift 的 fileprivate 協定（CR-009）。
// S1 不加 `extension SBApplication／SBObject`：Azathoth 的 H-20 測試在 S4 與 extension 一起改（sprint-1-detail.md §4.2）。

@objc(AZWMusicRemoteProto) public protocol MusicRemoteAppProto {
    @objc optional func playpause()
    @objc optional func nextTrack()
    /// CR-015：`previous track`（直接到前一首）；不用 `back track`（會先回曲頭）
    @objc optional func previousTrack()
    @objc optional var playerPosition: Double { get }
    @objc optional func setPlayerPosition(_ position: Double)
    @objc optional var playerState: UInt32 { get }
    @objc optional var currentTrack: SBObject { get }
    @objc optional func AirPlayDevices() -> SBElementArray
    @objc optional var currentAirPlayDevices: [SBObject] { get }
    @objc optional func setCurrentAirPlayDevices(_ devices: [SBObject])
}

@objc(AZWMusicRemoteTrackProto) public protocol MusicRemoteTrackProto {
    @objc optional var persistentID: String { get }
    @objc optional var duration: Double { get }
    @objc optional func playOnce(_ once: Bool)
}

@objc(AZWMusicRemoteAirPlayProto) public protocol MusicRemoteAirPlayProto {
    @objc optional var persistentID: String { get }
    @objc optional var selected: Bool { get }
    @objc optional var kind: UInt32 { get }
}
#endif
