#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// CR-030 G3（s6-61-genius.md §6 G3）：真的對 Music 的選單列做 AX 的整合測試，預設不跑。執行的程序（終端機）要被允許輔助使用。
// A 段（YSE_LIVE_MUSIC=1）只讀：定位到 Genius 項，按下前撤回（不按）。
// B 段（再加 YSE_LIVE_MUSIC_PLAY=1；使用者在場）按一次：會換掉「接下來」並開始播。只記數字，不記曲名。

private let live = ProcessInfo.processInfo.environment["YSE_LIVE_MUSIC"] == "1"
private let livePlay = live && ProcessInfo.processInfo.environment["YSE_LIVE_MUSIC_PLAY"] == "1"
/// CR-031 G8-0：停止＋「接下來」清空時按 Genius（使用者在場先清空並 ⌘. 停止）
private let liveIdle = live && ProcessInfo.processInfo.environment["YSE_LIVE_MUSIC_IDLE"] == "1"

@Suite(.serialized, .enabled(if: live, "YSE_LIVE_MUSIC=1 才跑（會讀 Music 的選單列）"))
struct LiveGeniusMenuReadTests {
    @Test func locatesGeniusAndWithdrawsBeforePressing() async throws {
        try #require(RunningMusicLocator().musicPID() != nil, "先打開 Music")
        let start = ContinuousClock.now
        let result = await GeniusMenu().pressGenius(prepare: { false }, stillWanted: { true })
        print("live-genius locate ms=\(Int((ContinuousClock.now - start).secondsValue * 1000)) result=\(result)")
        #expect(result == .withheld, "withheld＝定位成功且未按；accessibilityDenied＝終端機沒有輔助使用權限；notApplied＝結構不符")
    }
}

@Suite(.serialized, .enabled(if: livePlay, "YSE_LIVE_MUSIC_PLAY=1 才跑（會換掉「接下來」，使用者在場）"))
struct LiveGeniusMenuPressTests {
    @Test func pressingGeniusChangesTheCurrentSongAndPlays() async throws {
        let lane = MusicLane()
        let before = try await lane.snapshot()
        let start = ContinuousClock.now
        let result = await GeniusMenu().pressGenius(prepare: { true }, stillWanted: { true })
        try #require(result == .pressed, "沒有按下：\(result)")
        var snapshot = try await lane.snapshot()
        while snapshot.trackID == before.trackID || snapshot.trackID == nil,
              ContinuousClock.now - start < .seconds(PlaybackLimits.gateNoChangeDeadline + 2) {
            try await Task.sleep(for: .milliseconds(100))
            snapshot = try await lane.snapshot()
        }
        print("live-genius press→change ms=\(Int((ContinuousClock.now - start).secondsValue * 1000)) state=\(snapshot.state) "
              + "before=\(before.state)")
        #expect(snapshot.trackID != nil && snapshot.trackID != before.trackID)
        #expect(snapshot.state == .playing)
    }
}
@Suite(.serialized, .enabled(if: liveIdle, "YSE_LIVE_MUSIC_IDLE=1 才跑（停止＋清空後按 Genius，使用者在場）"))
struct LiveGeniusMenuIdleTests {
    /// 前置不成立（還有目前曲或不是停止）＝失敗：不得以一般播放情境冒充（G8 Codex R2-1）
    @Test func pressingGeniusWhileStoppedWithNoSongStartsPlaying() async throws {
        let lane = MusicLane()
        let before = try await lane.snapshot()
        try #require(before.trackID == nil && before.state == .stopped,
                     "前置不成立：trackID=\(before.trackID == nil ? "nil" : "有") state=\(before.state)（請清空『再生を続ける』並 ⌘. 停止）")
        let start = ContinuousClock.now
        let result = await GeniusMenu().pressGenius(prepare: { true }, stillWanted: { true })
        try #require(result == .pressed, "沒有按下：\(result)（notApplied＝定位失敗或項目停用）")
        var snapshot = try await lane.snapshot()
        while snapshot.trackID == nil, ContinuousClock.now - start < .seconds(PlaybackLimits.gateNoChangeDeadline + 2) {
            try await Task.sleep(for: .milliseconds(100))
            snapshot = try await lane.snapshot()
        }
        print("live-genius idle press→song ms=\(Int((ContinuousClock.now - start).secondsValue * 1000)) state=\(snapshot.state)")
        #expect(snapshot.trackID != nil)
        #expect(snapshot.state == .playing)
    }
}
#endif

