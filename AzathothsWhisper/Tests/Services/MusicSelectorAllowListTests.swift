import Foundation
import ScriptingBridge
import Testing

@testable import AzathothsWhisper

/// 負對照：刻意宣告四種違規（命令、選擇器名≠命令名、隱式 setter、改名藏起命令）。
/// 只存在於測試 target，**不掛到任何 SB 類別**、從不用來送 Apple Event
@objc(AZWGateNegativeControl) private protocol GateNegativeControl {
    @objc optional func playpause()
    @objc optional func playOnce(_ once: Bool)
    @objc optional var shuffleEnabled: Bool { get set }
    @objc(nextTrack) optional func innocuous()
}

// 計劃 AC9 ②：Music `@objc` 協議只准唯讀 getter＋setLyrics:（無播控、不改 Music 狀態）
@Suite("MusicSelectorAllowList")
struct MusicSelectorAllowListTests {
    static let appAllowed: Set<String> = ["playerState", "currentTrack", "tracks", "playerPosition"]
    static let trackAllowed: Set<String> = [
        "name", "artist", "album", "persistentID", "lyrics", "discNumber", "trackNumber", "artworks",
        "genre", "duration",   // 歌詞特效 A1（計劃 2026-10-04-lyrics-fx-a1 §3.1）：唯讀
    ]

    @Test func appProtocolDeclaresOnlyAllowedGetters() {
        #expect(SelectorAllowList.violations(protocolName: "AZWMusicAppProto", allowed: Self.appAllowed).isEmpty)
    }

    @Test func trackProtocolDeclaresOnlyAllowedGettersAndSetLyrics() {
        let violations = SelectorAllowList.violations(
            protocolName: "AZWMusicTrackProto", allowed: Self.trackAllowed, allowedSetters: ["setLyrics:"]
        )
        #expect(violations.isEmpty, "\(violations)")
    }

    @Test func negativeControlIsCaughtFourTimes() {
        _ = GateNegativeControl.self
        let violations = SelectorAllowList.violations(protocolName: "AZWGateNegativeControl", allowed: ["shuffleEnabled"])
        #expect(violations.count == 4, "\(violations)")
    }

    /// 防「另開一個協議再 extension 到 SB 類別」繞過白名單。
    /// YSE S4（D12，sprint-1-detail.md §4.2；H-20／H-27）：允許集合擴充 EchoKit MusicRemoteBridge 的四個 AZWMusicRemote* 協定，
    /// 與 Bridge 的 extension 同一個 commit；新增下方「採用集合完全等於」
    @Test func scriptingBridgeClassesCarryOnlyTheAllowedAppProtocols() {
        let allowed: Set<String> = ["AZWMusicAppProto", "AZWMusicTrackProto", "AZWMusicRemoteProto", "AZWMusicRemoteTrackProto",
                                    "AZWMusicRemoteAirPlayProto", "AZWMusicRemoteLibraryProto"]
        for cls in [SBObject.self, SBApplication.self] as [AnyClass] {
            let found = Set(SelectorAllowList.protocols(on: cls, prefix: "AZW"))
            #expect(found.isSubset(of: allowed), "\(NSStringFromClass(cls)) 掛了 \(found.subtracting(allowed))")
        }
    }

    /// YSE S4（D12）：SB 類別採用的 AZW 協定集合**完全等於**指定集合（多一個、少一個都紅）
    @Test func scriptingBridgeClassesAdoptExactlyTheSpecifiedProtocols() {
        #expect(Set(SelectorAllowList.protocols(on: SBApplication.self, prefix: "AZW"))
                == ["AZWMusicAppProto", "AZWMusicRemoteProto", "AZWMusicRemoteLibraryProto"])
        #expect(Set(SelectorAllowList.protocols(on: SBObject.self, prefix: "AZW"))
                == ["AZWMusicTrackProto", "AZWMusicRemoteTrackProto", "AZWMusicRemoteAirPlayProto"])
    }

    @Test func processNotFoundMapsToNotRunning() {
        #expect(MusicAppleEventsClient.mapError(NSError(domain: NSOSStatusErrorDomain, code: -600)) == .notRunning)
        #expect(MusicAppleEventsClient.mapError(NSError(domain: NSOSStatusErrorDomain, code: -1743)) == .permissionDenied)
    }
}
