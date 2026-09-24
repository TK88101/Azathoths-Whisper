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
    static let appAllowed: Set<String> = ["playerState", "currentTrack", "tracks"]
    static let trackAllowed: Set<String> = [
        "name", "artist", "album", "persistentID", "lyrics", "discNumber", "trackNumber", "artworks",
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

    /// 防「另開一個協議再 extension 到 SB 類別」繞過白名單
    @Test func scriptingBridgeClassesCarryOnlyTheAllowedAppProtocols() {
        let allowed: Set<String> = ["AZWMusicAppProto", "AZWMusicTrackProto"]
        for cls in [SBObject.self, SBApplication.self] as [AnyClass] {
            let found = Set(SelectorAllowList.protocols(on: cls, prefix: "AZW"))
            #expect(found.isSubset(of: allowed), "\(NSStringFromClass(cls)) 掛了 \(found.subtracting(allowed))")
        }
    }

    @Test func processNotFoundMapsToNotRunning() {
        #expect(MusicAppleEventsClient.mapError(NSError(domain: NSOSStatusErrorDomain, code: -600)) == .notRunning)
        #expect(MusicAppleEventsClient.mapError(NSError(domain: NSOSStatusErrorDomain, code: -1743)) == .permissionDenied)
    }
}
