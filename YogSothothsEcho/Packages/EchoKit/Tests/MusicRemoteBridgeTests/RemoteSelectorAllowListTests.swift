#if os(macOS)
import Foundation
import Testing
@testable import MusicRemoteBridge

// 負對照用的協定：只存在於測試 target，名稱不帶 AZW 前綴，不會被任何正式檢查誤認
@objc(YSETestNegativeExtra) private protocol NegativeExtra {
    @objc optional func playpause()
    @objc optional func shuffleEnabled() -> Bool
}

@objc(YSETestNegativeSetter) private protocol NegativeSetter {
    @objc optional func playpause()
    @objc optional func setSoundVolume(_ volume: Int)
}

@objc(YSETestNegativeRequired) private protocol NegativeRequired {
    func playpause()
}

/// CR-006④＋CR-009：四協定逐協定完全等於
struct RemoteSelectorAllowListTests {
    @Test func expectedSetsMatchChangeRequests() {
        #expect(RemoteSelectorAllowList.expected == [
            "AZWMusicRemoteProto": [
                "playpause", "nextTrack", "previousTrack", "playerPosition", "setPlayerPosition:", "playerState",
                "currentTrack", "AirPlayDevices", "currentAirPlayDevices", "setCurrentAirPlayDevices:",
            ],
            "AZWMusicRemoteTrackProto": ["persistentID", "duration", "playOnce:"],
            "AZWMusicRemoteAirPlayProto": ["persistentID", "selected", "kind"],
            "AZWMusicRemoteLibraryProto": ["tracks"],
        ])
    }

    @Test(arguments: ["AZWMusicRemoteProto", "AZWMusicRemoteTrackProto", "AZWMusicRemoteAirPlayProto",
                      "AZWMusicRemoteLibraryProto"])
    func declaredProtocolIsExactlyTheAllowList(name: String) {
        let audit = RemoteSelectorAllowList.audit(protocolName: name)
        #expect(audit.found, "\(name) 沒有註冊到 ObjC 執行期")
        #expect(audit.isExact, "\(name)：missing \(audit.missing.sorted()) extra \(audit.extra.sorted()) required \(audit.requiredCount)")
    }

    @Test func playOnceIsTheOnlyPlaybackSelectorOnTracks() {
        #expect(RemoteSelectorAllowList.expected["AZWMusicRemoteTrackProto"]?.contains("play") == false)
        #expect(RemoteSelectorAllowList.expected.values.allSatisfy { !$0.contains("play") })
    }

    @Test func extraSelectorIsCaught() {
        let audit = RemoteSelectorAllowList.audit(protocolName: "YSETestNegativeExtra", expected: ["playpause"])
        #expect(audit.extra == ["shuffleEnabled"])
        #expect(!audit.isExact)
    }

    @Test func missingSelectorIsCaught() {
        let audit = RemoteSelectorAllowList.audit(protocolName: "YSETestNegativeExtra",
                                                  expected: ["playpause", "shuffleEnabled", "nextTrack"])
        #expect(audit.missing == ["nextTrack"])
        #expect(!audit.isExact)
    }

    @Test func unlistedSetterIsCaught() {
        let audit = RemoteSelectorAllowList.audit(protocolName: "YSETestNegativeSetter", expected: ["playpause"])
        #expect(audit.extra == ["setSoundVolume:"])
        #expect(audit.unlistedSetters == ["setSoundVolume:"])
        #expect(!audit.isExact)
    }

    @Test func requiredMethodIsCaught() {
        let audit = RemoteSelectorAllowList.audit(protocolName: "YSETestNegativeRequired", expected: ["playpause"])
        #expect(audit.requiredCount == 1)
        #expect(!audit.isExact)
    }

    @Test func unknownProtocolIsNotExact() {
        let audit = RemoteSelectorAllowList.audit(protocolName: "YSETestDoesNotExist", expected: [])
        #expect(!audit.found)
        #expect(!audit.isExact)
    }

    // S1 的「S4 之前不得採用」預留測試已依 sprint-1-detail.md §4.2 的約定，在 S4 與 extension 同一個 commit 換成
    // 「採用集合完全等於」：見 MusicLaneTests.swift 的 RemoteProtocolAdoptionTests（D12）
}

/// 型別層：方法集合照基本設計 §5.3；以替身實作證明簽名可被滿足
struct MusicRemoteControllingTests {
    private actor Fake: MusicRemoteControlling {
        private(set) var calls: [String] = []
        func play(trackID: String, context: PlayContext) async throws -> PlayOutcome { calls.append("play"); return .verified }
        func togglePlayPause() async throws { calls.append("toggle") }
        func next() async throws { calls.append("next") }
        func previous() async throws { calls.append("previous") }
        func seek(to seconds: Double) async throws { calls.append("seek") }
        func outputs() async throws -> [OutputDevice] { calls.append("outputs"); return [] }
        func setOutputs(_ deviceIDs: [String]) async throws { calls.append("setOutputs") }
        func state() async throws -> PlaybackSnapshot {
            calls.append("state")
            return PlaybackSnapshot(trackID: nil, state: .stopped, position: 0, duration: nil)
        }
    }

    @Test func fakeSatisfiesTheWholeSurface() async throws {
        let fake = Fake()
        let control: any MusicRemoteControlling = fake
        #expect(try await control.play(trackID: "00000000000000AA", context: .album(id: "00000000000000BB")) == .verified)
        try await control.togglePlayPause()
        try await control.next()
        try await control.previous()
        try await control.seek(to: 12)
        _ = try await control.outputs()
        try await control.setOutputs([])
        _ = try await control.state()
        #expect(await fake.calls == ["play", "toggle", "next", "previous", "seek", "outputs", "setOutputs", "state"])
    }
}
#endif
