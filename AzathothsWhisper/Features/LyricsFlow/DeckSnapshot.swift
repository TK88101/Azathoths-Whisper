import Foundation

/// Cover Flow 上的一張卡
struct DeckCard: Identifiable, Equatable, Sendable {
    enum Side: Equatable, Sendable {
        case played
        case current
        case upcoming
    }

    let id: String
    let persistentID: String
    let side: Side
}

/// 某一刻的牌組（計劃 AC8、AC8e）：左＝播過（Music 履歴，或退回時本 app 觀察到的歷史）、
/// 中＝正在播、右＝清單中當前之後。不可變。
///
/// 卡 ID（AC8 唯一規格）：佇列項 `q:<epoch>:<itID>`（中心與右側共用——下一首成為中心時 ID 不變，
/// 條帶才能平滑平移，S5）；履歴 `h:<pid>#<自最新起第幾次>`；觀察到的播放 `o:<pid>#<場次>`
/// （退回模式的中心也用它，播完移到左側時 ID 不變）。
struct DeckSnapshot: Equatable, Sendable {
    /// 右側的狀態：`pending` 不顯示任何提示（短暫空窗），`unavailable` 才顯示「接下來的歌暫時讀不到」
    enum Upcoming: Equatable, Sendable {
        case available
        case pending
        case unavailable
    }

    enum PlayedSource: Equatable, Sendable {
        case musicHistory(HistorySnapshot)
        case observed(ListeningHistory)
    }

    /// 待入履歴的暫定左鄰卡（計劃 2026-09-27-coverflow-f1-f2 §12）：剛順向離開正中、Music 還沒寫進履歴的那首
    /// （Music 換歌後約 5 秒才寫）。沿用它離開正中前的卡 ID——平移的暫留卡就是它，落定時畫面不動
    struct PendingPlayed: Equatable, Sendable {
        let persistentID: String
        let cardID: String
    }

    struct NowPlaying: Equatable, Sendable {
        let persistentID: String
        let occurrence: Int
    }

    let cards: [DeckCard]
    let currentCardID: String?
    let upcoming: Upcoming

    static let empty = DeckSnapshot(cards: [], currentCardID: nil, upcoming: .pending)

    static func build(
        nowPlaying: NowPlaying?, played: PlayedSource, pendingPlayed: PendingPlayed? = nil, queue: QueueSession, window: Int
    ) -> DeckSnapshot {
        let left = playedCards(played, window: window)
        // 觀察模式在換歌當下就記下前一首，不需要暫定卡
        let pending: DeckCard? = if case .musicHistory = played, let pendingPlayed {
            DeckCard(id: pendingPlayed.cardID, persistentID: pendingPlayed.persistentID, side: .played)
        } else {
            nil
        }
        guard let nowPlaying else {
            return DeckSnapshot(cards: unique(left), currentCardID: nil, upcoming: .pending)
        }
        if let snapshot = queue.snapshot, let index = queue.currentIndex,
           snapshot.entries[index].persistentID == nowPlaying.persistentID {
            let current = DeckCard(id: queue.cardID(at: index), persistentID: nowPlaying.persistentID, side: .current)
            // 先算剩餘容量再相加：window 可能極大，直接相加會溢位（對抗覆核 P2）
            let rightCount = min(max(window, 0), snapshot.entries.count - index - 1)
            let right = ((index + 1)..<(index + 1 + rightCount)).map {
                DeckCard(id: queue.cardID(at: $0), persistentID: snapshot.entries[$0].persistentID, side: .upcoming)
            }
            return DeckSnapshot(
                cards: around(current, left: left, pending: pending, right: right, window: window),
                currentCardID: current.id, upcoming: .available
            )
        }
        let current = DeckCard(
            id: "o:\(nowPlaying.persistentID)#\(nowPlaying.occurrence)",
            persistentID: nowPlaying.persistentID,
            side: .current
        )
        let upcoming: Upcoming = queue.upcoming == .available ? .pending : queue.upcoming
        return DeckSnapshot(
            cards: around(current, left: left, pending: pending, right: [], window: window),
            currentCardID: current.id, upcoming: upcoming
        )
    }

    /// 中心卡＝播放中，永遠在：兩側若有與它同 ID 的卡，剔兩側、保中心（對抗覆核 P2）
    /// 暫定卡排在左鄰、履歴讓出最舊的一張（左側張數不變）；它的 ID 若與牌內任何一張衝突就不放——
    /// 寧可少一張暫定卡，也不讓 `unique` 靜默吃掉正式的卡
    private static func around(
        _ current: DeckCard, left: [DeckCard], pending: DeckCard?, right: [DeckCard], window: Int
    ) -> [DeckCard] {
        let others = { (cards: [DeckCard]) in cards.filter { $0.id != current.id } }
        var played = others(left)
        if let pending, !([current] + right + played).contains(where: { $0.id == pending.id }) {
            played = Array(played.suffix(max(0, window - 1))) + [pending]
        }
        return unique(played + [current] + others(right))
    }

    private static func playedCards(_ source: PlayedSource, window: Int) -> [DeckCard] {
        switch source {
        case .musicHistory(let history):
            let recent = Array(history.recent.suffix(max(0, window)))
            // 自最新起數第幾次：新的一筆追加時，其他歌的 ID 不動（檔案若有上限、最舊的被擠掉也不動）
            var seen: [String: Int] = [:]
            let newestFirst = recent.reversed().map { entry -> DeckCard in
                let nth = seen[entry.persistentID, default: 0]
                seen[entry.persistentID] = nth + 1
                return DeckCard(id: "h:\(entry.persistentID)#\(nth)", persistentID: entry.persistentID, side: .played)
            }
            return newestFirst.reversed()
        case .observed(let history):
            return history.plays.suffix(max(0, window)).map {
                DeckCard(id: "o:\($0.persistentID)#\($0.occurrence)", persistentID: $0.persistentID, side: .played)
            }
        }
    }

    /// `ForEach` 的前提：牌內 ID 唯一。規則上已保證，這裡是防禦
    private static func unique(_ cards: [DeckCard]) -> [DeckCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }
}
