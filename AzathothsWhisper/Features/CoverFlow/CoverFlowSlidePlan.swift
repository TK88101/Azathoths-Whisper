import Foundation

/// 換歌方向的佐證，由 `QueueSession.slideHint(to:)` 在解析新位置之前取得
/// （計劃 `docs/plans/2026-09-26-coverflow-follow-playback-slide.md` §3.1-4 (iii)）
struct SlideHint: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case next
        case previous
    }

    let oldCardID: String
    let oldPersistentID: String
    let targetPersistentID: String
    let direction: Direction
}

/// 給條帶的平移指令
struct CoverFlowSlideRequest: Equatable, Sendable {
    let generation: Int
    /// 內容位移的卡距數：+1＝下一首（舊當前卡在目標左鄰）；−1＝上一首（在右鄰）
    let slots: Int
}

/// 進行中的一次換歌平移。顯示牌組由「canonical 牌組＋它」算出，不另存（計劃 §3.3）
struct SlideTransition: Equatable, Sendable {
    let generation: Int
    /// 暫留的舊當前卡（原 ID；左右已改成它在新牌組中的那一側）
    let old: DeckCard
    let target: String
    let slots: Int
    /// 進入過渡時目標卡在顯示牌組中的位次；之後每次重算都必須相同，捲動位置才不必改
    let targetIndex: Int
}

/// 真實換歌要不要平移、平移時條帶吃哪一副牌（計劃 §3.1、§3.2）。純函式
enum CoverFlowSlidePlan: Equatable {
    case direct
    case slide(old: DeckCard, target: String, slots: Int, targetIndex: Int)

    /// - Parameters:
    ///   - previousDisplay: 換歌前條帶吃的牌
    ///   - old: 換歌前的當前卡（畫面正停在它上面）
    ///   - canonical: 換歌後的正式牌組
    static func make(previousDisplay: [DeckCard], old: DeckCard, canonical: DeckSnapshot,
                     hint: SlideHint?, limit: Int) -> CoverFlowSlidePlan {
        guard let target = canonical.currentCardID, target != old.id,
              let targetCard = canonical.cards.first(where: { $0.id == target }),
              let oldIndex = previousDisplay.firstIndex(where: { $0.id == old.id }),
              let slots = slots(previousDisplay: previousDisplay, old: old, target: targetCard, canonical: canonical, hint: hint)
        else { return .direct }
        // 暫留卡不再是當前卡：左右改成它在新牌組中的那一側
        let kept = DeckCard(id: old.id, persistentID: old.persistentID, side: slots > 0 ? .played : .upcoming)
        // 位次條件：目標卡的新位次＝舊當前卡的原位次，捲動位置的數值才不必改
        guard display(canonical: canonical, old: kept, target: target, slots: slots, targetIndex: oldIndex, limit: limit) != nil
        else { return .direct }
        return .slide(old: kept, target: target, slots: slots, targetIndex: oldIndex)
    }

    /// 過渡顯示牌組。回 nil＝過渡撐不下去（當前卡換了身分、暫留卡放不進去、目標卡位次變了）
    static func display(canonical: DeckSnapshot, old: DeckCard, target: String, slots: Int,
                        targetIndex: Int, limit: Int) -> [DeckCard]? {
        guard canonical.currentCardID == target, slots == 1 || slots == -1 else { return nil }
        let cards = keeping(old, in: canonical.cards, besideTarget: target, slots: slots, limit: limit)
        guard Set(cards.map(\.id)).count == cards.count,
              cards.indices.contains(targetIndex), cards[targetIndex].id == target,
              cards.indices.contains(targetIndex - slots), cards[targetIndex - slots].id == old.id
        else { return nil }
        return cards
    }

    // MARK: - 內部

    /// 把暫留卡放到目標卡旁邊。放不進去時原樣回傳，由呼叫端的檢查判定失敗
    private static func keeping(_ old: DeckCard, in cards: [DeckCard], besideTarget target: String,
                                slots: Int, limit: Int) -> [DeckCard] {
        guard !cards.contains(where: { $0.id == old.id }),
              let targetIndex = cards.firstIndex(where: { $0.id == target })
        else { return cards }
        let neighbour = targetIndex - slots
        // 履歴已追上：緊鄰的是同一首歌的另一張卡 → 原位取代，張數不變
        if cards.indices.contains(neighbour), cards[neighbour].persistentID == old.persistentID {
            return Array(cards[..<neighbour]) + [old] + Array(cards[(neighbour + 1)...])
        }
        if slots > 0 {
            // 插在左鄰會把目標卡往右推一格：剔掉最左一張補回來
            guard targetIndex >= 1 else { return cards }
            return Array(cards[1..<targetIndex]) + [old] + Array(cards[targetIndex...])
        }
        let inserted = Array(cards[...targetIndex]) + [old] + Array(cards[(targetIndex + 1)...])
        return inserted.count > limit ? Array(inserted.dropLast()) : inserted
    }

    /// 方向要有證據，而且所有拿得到的證據必須一致（計劃 §3.1-4）
    private static func slots(previousDisplay: [DeckCard], old: DeckCard, target: DeckCard,
                              canonical: DeckSnapshot, hint: SlideHint?) -> Int? {
        let proofs = [
            offset(from: old.id, to: target.id, in: previousDisplay),
            offset(from: old.id, to: target.id, in: canonical.cards),
            hint.flatMap { offset(for: $0, old: old, target: target) },
        ].compactMap { $0 }
        guard let first = proofs.first, first == 1 || first == -1, proofs.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// 兩張卡都在這副牌裡時，目標卡在舊當前卡右邊幾格
    private static func offset(from old: String, to target: String, in cards: [DeckCard]) -> Int? {
        guard let oldIndex = cards.firstIndex(where: { $0.id == old }),
              let targetIndex = cards.firstIndex(where: { $0.id == target })
        else { return nil }
        return targetIndex - oldIndex
    }

    private static func offset(for hint: SlideHint, old: DeckCard, target: DeckCard) -> Int? {
        guard hint.oldCardID == old.id, hint.oldPersistentID == old.persistentID,
              hint.targetPersistentID == target.persistentID
        else { return nil }
        return hint.direction == .next ? 1 : -1
    }
}
