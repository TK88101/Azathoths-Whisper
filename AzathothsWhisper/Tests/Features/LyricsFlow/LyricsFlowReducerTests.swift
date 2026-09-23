import Testing

@testable import AzathothsWhisper

// 計劃 §6 畫面狀態機：每列至少一測（含同曲重發、升回取消與 ABA、空寫入、權限恢復）
@Suite("LyricsFlowReducer")
struct LyricsFlowReducerTests {
    private typealias State = LyricsFlowState
    private typealias Event = LyricsFlowEvent

    private func identity(_ key: String) -> NowPlayingIdentity { NowPlayingIdentity(key: key) }

    private func playing(_ key: String, _ status: LyricsStatus, from state: State = State()) -> State {
        LyricsFlowReducer.reduce(state, .nowPlaying(identity(key), persistentID: key, status: status)).0
    }

    private func reduce(_ state: State, _ event: Event) -> (State, [LyricsFlowEffect]) {
        LyricsFlowReducer.reduce(state, event)
    }

    @Test func initialSurfaceIsTheEditorWithNothingPlaying() {
        #expect(State().surface == .editor)
        #expect(State().nowPlaying == nil)
    }

    @Test("真實換歌依狀態決定畫面", arguments: [
        (LyricsStatus.present, LyricsSurface.coverFlow),
        (LyricsStatus.markedNone, LyricsSurface.coverFlow),
        (LyricsStatus.unknown, LyricsSurface.coverFlow),     // 讀不到：不降下
        (LyricsStatus.missing, LyricsSurface.editor),
    ])
    func realChangeFollowsStatus(status: LyricsStatus, expected: LyricsSurface) {
        #expect(playing("A", status).surface == expected)
    }

    /// AC6（兩路評審的 P0）：同曲重發（forceRefresh／停止後再播同曲）不動畫面
    @Test func sameTrackRefreshKeepsTheSurface() {
        let onA = playing("A", .present)
        let (editing, _) = reduce(onA, .tapPlayingCard(isCentered: true))
        let refreshed = playing("A", .present, from: editing)
        #expect(refreshed.surface == .editor)
        #expect(refreshed.occurrence == editing.occurrence)
    }

    @Test func sameTrackRefreshKeepsAPendingRise() {
        let (written, _) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let refreshed = playing("A", .present, from: written)
        #expect(refreshed.pendingRise == written.pendingRise)
        #expect(refreshed.pendingRise != nil)
    }

    /// 使用者拍板①（2026-09-23）：寫入後讀回仍缺詞＝寫入沒生效 → 取消待升回、留在 Editor、提示寫入沒生效
    @Test func readBackMissingCancelsThePendingRise() {
        let (written, _) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let (next, effects) = reduce(written, .nowPlaying(identity("A"), persistentID: "A", status: .missing))
        #expect(next.pendingRise == nil)
        #expect(next.surface == .editor)
        #expect(effects == [.cancelRise, .writeNotConfirmed(persistentID: "A")])
    }

    /// 沒有待升回時，同曲讀回缺詞仍照 AC6 不動畫面
    @Test func sameTrackMissingWithoutAPendingRiseKeepsTheSurface() {
        let refreshed = playing("A", .missing, from: playing("A", .present))
        #expect(refreshed.surface == .coverFlow)
        #expect(refreshed.status == .missing)
    }

    /// 使用者拍板②（2026-09-23）：讀不到 → 確定缺詞，且本場次使用者沒親手選過畫面 → 降下露出 Editor
    @Test func unknownThenMissingLowersTheEditor() {
        let refreshed = playing("A", .missing, from: playing("A", .unknown))
        #expect(refreshed.surface == .editor)
    }

    @Test func unknownThenMissingRespectsTheUsersOwnChoice() {
        let (down, _) = reduce(playing("A", .unknown), .toggleHandle)
        let (up, _) = reduce(down, .toggleHandle)
        let refreshed = playing("A", .missing, from: up)
        #expect(refreshed.surface == .coverFlow, "使用者親手升起過，尊重使用者")
    }

    @Test func anIneffectiveTapIsNotAChoice() {
        let (tapped, _) = reduce(playing("A", .unknown), .tapPlayingCard(isCentered: false))
        let refreshed = playing("A", .missing, from: tapped)
        #expect(refreshed.surface == .editor)
    }

    @Test func aRealChangeForgetsThePreviousChoice() {
        let (down, _) = reduce(playing("A", .unknown), .toggleHandle)
        let (up, _) = reduce(down, .toggleHandle)
        let onB = playing("B", .unknown, from: up)
        let refreshed = playing("B", .missing, from: onB)
        #expect(refreshed.surface == .editor)
    }

    @Test func realChangeCancelsAPendingRise() {
        let (written, _) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let (next, effects) = reduce(written, .nowPlaying(identity("B"), persistentID: "B", status: .present))
        #expect(next.pendingRise == nil)
        #expect(effects.contains(.cancelRise))
    }

    // MARK: 點卡、把手

    @Test func tappingTheCentredPlayingCardOpensTheEditor() {
        let (state, _) = reduce(playing("A", .present), .tapPlayingCard(isCentered: true))
        #expect(state.surface == .editor)
    }

    @Test func tappingWhenNotCentredDoesNothing() {
        let (state, effects) = reduce(playing("A", .present), .tapPlayingCard(isCentered: false))
        #expect(state.surface == .coverFlow)
        #expect(effects.isEmpty)
    }

    @Test func tappingWithNothingPlayingDoesNothing() {
        let (state, _) = reduce(State(surface: .coverFlow), .tapPlayingCard(isCentered: true))
        #expect(state.surface == .coverFlow)
    }

    @Test func handleTogglesBothWays() {
        let onA = playing("A", .present)
        let (down, _) = reduce(onA, .toggleHandle)
        let (up, _) = reduce(down, .toggleHandle)
        #expect(down.surface == .editor)
        #expect(up.surface == .coverFlow)
    }

    // MARK: 寫入與升回

    @Test func successfulWriteOfTheCurrentTrackSchedulesARise() {
        let (state, effects) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let token = try? #require(state.pendingRise)
        #expect(token != nil)
        #expect(effects.contains(.scheduleRise(token!)))
        #expect(effects.contains(.forceRefresh), "補上 busy 期間漏掉的換歌")
        #expect(state.status == .present)
        #expect(state.surface == .editor, "彩帶撒完才升回")
    }

    @Test func riseDueWithTheLiveTokenRaisesCoverFlow() {
        let (written, _) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let (risen, _) = reduce(written, .riseDue(written.pendingRise!))
        #expect(risen.surface == .coverFlow)
        #expect(risen.pendingRise == nil)
    }

    /// ABA：A 寫入 → 換 B → 回 A，舊計時到期不得升回
    @Test func staleRiseAfterABADoesNothing() {
        let (written, _) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let staleToken = written.pendingRise!
        let onB = playing("B", .missing, from: written)
        let backOnA = playing("A", .missing, from: onB)
        let (after, _) = reduce(backOnA, .riseDue(staleToken))
        #expect(after.surface == .editor)
    }

    @Test("使用者操作取消待升回", arguments: [
        LyricsFlowEvent.toggleHandle,
        LyricsFlowEvent.editorTextEdited,
    ])
    func userActionsCancelThePendingRise(event: LyricsFlowEvent) {
        let (written, _) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let (after, effects) = reduce(written, event)
        #expect(after.pendingRise == nil)
        #expect(effects.contains(.cancelRise))
    }

    @Test func emptyWriteDoesNotRise() {
        let (state, effects) = reduce(playing("A", .present), .writeSucceeded(persistentID: "A", resultingStatus: .missing))
        #expect(state.pendingRise == nil)
        #expect(state.status == .missing)
        #expect(effects == [.forceRefresh])
    }

    /// 對抗覆核 P1②：寫入有詞（待升回）後又寫入空字串——待升回必須取消，否則到期把缺詞曲升回
    @Test func emptyWriteAfterASuccessfulWriteCancelsThePendingRise() {
        let (written, _) = reduce(playing("A", .missing), .writeSucceeded(persistentID: "A", resultingStatus: .present))
        let (cleared, effects) = reduce(written, .writeSucceeded(persistentID: "A", resultingStatus: .missing))
        #expect(cleared.pendingRise == nil)
        #expect(effects == [.cancelRise, .forceRefresh])
        let (after, _) = reduce(cleared, .riseDue(written.pendingRise!))
        #expect(after.surface == .editor, "缺詞＝Editor")
    }

    @Test func writeOfANonCurrentTrackDoesNotMoveTheSurface() {
        let onB = playing("B", .missing)
        let (state, effects) = reduce(onB, .writeSucceeded(persistentID: "A", resultingStatus: .present))
        #expect(state.surface == .editor)
        #expect(state.pendingRise == nil)
        #expect(effects == [.forceRefresh])
    }

    @Test func failedWriteOnlyRefreshes() {
        let onA = playing("A", .missing)
        let (state, effects) = reduce(onA, .writeFailed(persistentID: "A"))
        #expect(state == onA)
        #expect(effects == [.forceRefresh])
    }

    // MARK: 標記無詞

    @Test func markingTheCurrentTrackRaisesAndCancelsAutoFetch() {
        let (state, effects) = reduce(playing("A", .missing), .markedNone(persistentID: "A"))
        #expect(state.surface == .coverFlow)
        #expect(state.status == .markedNone)
        #expect(effects.contains(.cancelAutoFetch(persistentID: "A")))
    }

    /// 對抗覆核 P2（Codex 修正版）：只有已知「缺詞」的當前曲可標記；有詞或讀不到時整個動作不生效
    /// （不改狀態、不動畫面、不取消待升回）——「沒讀到」不能當成「沒有」
    @Test("有詞與讀不到的當前曲不可標記", arguments: [LyricsStatus.present, LyricsStatus.unknown])
    func markingIsIgnoredUnlessTheCurrentTrackIsMissing(status: LyricsStatus) {
        let (editing, _) = reduce(playing("A", status), .toggleHandle)
        let (state, effects) = reduce(editing, .markedNone(persistentID: "A"))
        #expect(state == editing)
        #expect(effects.isEmpty)
    }

    @Test func markingANonCurrentTrackOnlyCancelsItsAutoFetch() {
        let onB = playing("B", .missing)
        let (state, effects) = reduce(onB, .markedNone(persistentID: "A"))
        #expect(state.surface == .editor)
        #expect(effects == [.cancelAutoFetch(persistentID: "A")])
    }

    // MARK: 權限

    @Test func permissionDeniedShowsTheEditorOnce() {
        let onA = playing("A", .present)
        let (denied, _) = reduce(onA, .permissionDenied)
        let (toggled, _) = reduce(denied, .toggleHandle)
        let (again, _) = reduce(toggled, .permissionDenied)
        #expect(denied.surface == .editor)
        #expect(again.surface == .coverFlow, "每 tick 重發的拒絕不得覆蓋使用者的把手操作")
    }

    @Test func recoveringFromDenialOnTheSameTrackReappliesItsStatus() {
        let (denied, _) = reduce(playing("A", .present), .permissionDenied)
        let recovered = playing("A", .present, from: denied)
        #expect(recovered.surface == .coverFlow)
        #expect(!recovered.isDenied)
    }

    @Test func notPlayingChangesNothing() {
        let onA = playing("A", .present)
        let (state, effects) = reduce(onA, .notPlaying)
        #expect(state == onA)
        #expect(effects.isEmpty)
    }
}
