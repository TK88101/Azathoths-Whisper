import Foundation

/// 一次位置讀數（母計劃 §2.2）：過去某時刻的樣本，不是「現在的位置」。
/// 組裝與判斷放在這裡（可測），AE 端只讀原始值——AE 檔被 coverage 豁免、行數有上限（A1 計劃 §1）
struct PlaybackPosition: Equatable, Sendable {
    let persistentID: String
    let seconds: Double
    let state: PlayerState
    let readAt: ContinuousClock.Instant
    let roundTrip: Duration

    static func make(
        state: PlayerState, idBefore: String?, seconds: Double?, idAfter: String?,
        before: ContinuousClock.Instant, after: ContinuousClock.Instant
    ) -> PlaybackPosition? {
        // 只有 playing／paused 有當前曲；兩次 ID 不同＝讀的途中換了歌，位置不知道屬於哪首
        guard state.hasCurrentTrack,
              let id = idBefore, !id.isEmpty, id == idAfter,
              let seconds, seconds.isFinite, seconds >= 0
        else { return nil }
        let roundTrip = after - before
        // readAt 取 position 那次存取前後的中點：Music 是在往返途中某刻取樣的
        return PlaybackPosition(persistentID: id, seconds: seconds, state: state, readAt: before + roundTrip / 2, roundTrip: roundTrip)
    }
}
