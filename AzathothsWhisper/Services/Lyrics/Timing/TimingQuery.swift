import Foundation

/// 對外查時間軸時**唯一**送出的三樣資料（C 段計劃 §3.2；使用者口令「外部只送 artist／title／duration」）
struct TimingQuery: Equatable, Sendable {
    let artist: String
    let title: String
    /// 秒；有限且 > 0 才會被送出（§3.5 前置條件）
    let duration: Double
}

/// 來源回來的候選曲目（只用來比對，不落地）
struct MatchedTrack: Equatable, Sendable {
    let artist: String
    let title: String
    /// 秒；nil＝來源沒給（→ 不採用，§3.3）
    let duration: Double?
}
