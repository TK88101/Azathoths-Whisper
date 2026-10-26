#if os(macOS)
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

/// DEBUG 診斷文字的特性測試（2026-10-19 simplify 重構前寫下）：`log show` 判讀與 Scripts/d2_pair.py 依賴這些字面，
/// 原因改成列舉、紀錄收斂成一處之後也要逐字相同
struct RelayTraceTextTests {
    private func snap(_ track: String?, _ state: PlaybackState, _ position: Double) -> MusicSnapshot {
        MusicSnapshot(state: state, trackID: track, duration: 200, position: position)
    }

    @Test func manualChangeReasonsKeepTheirWording() {
        var paused = ManualChangeDetector(expected: [], anchor: snap("0000000000000001", .playing, 10), at: 0)
        let pausedManual = paused.observe(snap("0000000000000001", .paused, 10.5), at: 1, local: [])
        #expect(pausedManual)
        #expect(paused.lastReason.map { String(describing: $0) } == "state playing→paused")

        var jumped = ManualChangeDetector(expected: [], anchor: snap("0000000000000001", .playing, 10), at: 0)
        let jumpedManual = jumped.observe(snap("0000000000000001", .playing, 50), at: 1, local: [])
        #expect(jumpedManual)
        #expect(jumped.lastReason.map { String(describing: $0) } == "jump predicted=11.00 actual=50.00 state=playing")

        var moved = ManualChangeDetector(expected: [], anchor: snap("0000000000000001", .playing, 10), at: 0)
        let movedManual = moved.observe(snap("0000000000000002", .playing, 0), at: 1, local: [])
        #expect(movedManual)
        #expect(moved.lastReason.map { String(describing: $0) } == "track 0000000000000001→0000000000000002")
    }

    @Test func pushLineKeepsItsWording() {
        let event = PlaybackEvent(availability: .ok, trackID: "0000000000000001", albumID: nil, state: .paused, position: 12.345,
                                  duration: 200, sampledAt: 0)
        #expect(PlaybackStatePoller.pushLine("control", event) == "push reason=control state=paused pos=12.35 track=0000000000000001")
    }

    @Test func gateLineKeepsItsWording() {
        #expect(RemoteCommandQueue.gateLine(forward: true, path: "none", sendSeconds: 0.004, detectSeconds: 3.1)
                == "gate dir=next path=none sendMs=4 detectMs=3100")
    }
}
#endif
