import Foundation

/// 本 app 觀察到的換曲歷史——只在 `History.dat` 不可讀時當左側來源（計劃 AC8b、R3-7）。
///
/// 有序集合：重播移到尾端、不重複；上限 50；空 persistentID 不進（不同的歌會共用同一個空鍵）。
/// 只在記憶體（D3）。
struct ListeningHistory: Equatable, Sendable {
    struct Play: Equatable, Sendable {
        let persistentID: String
        /// 真實換歌場次：同曲重播是不同場次，卡 ID 才能區分（R5-2）
        let occurrence: Int
    }

    static let capacity = 50

    /// 由舊到新
    private(set) var plays: [Play] = []

    func recording(_ play: Play) -> ListeningHistory {
        guard !play.persistentID.isEmpty else { return self }
        let kept = plays.filter { $0.persistentID != play.persistentID } + [play]
        return ListeningHistory(plays: Array(kept.suffix(Self.capacity)))
    }
}
