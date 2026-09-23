import Foundation

/// 佇列 session：最後一份有效的 `QueueSnapshot`＋當前出現位置＋itID epoch（計劃 AC8、R3-1、R4-4、AC8b）。
/// 值型別：每個操作回傳新值。
///
/// - 位置推進（R3-1）：按下一首時 Music **不重寫**檔案（事實 21），當前位置只能由「上次位置之後第一個相符」
///   推算；同曲在清單出現多次、又沒有上次位置可參考 → 不猜，視為未解析。
/// - 重寫（插歌／Genius）時以 itID 把上次位置帶到新清單（事實 23：既有項 itID 不變）。
/// - itID 只是 session 內身分：同一 itID 在新快照指向別首歌 → epoch 加一，卡 ID 隨之不同（R4-4）。
struct QueueSession: Equatable, Sendable {
    private(set) var snapshot: QueueSnapshot?
    private(set) var currentIndex: Int?
    private var consecutiveMisses = 0
    /// 從未拿到有效快照、且讀取已失敗過
    private var readFailed = false
    private var epochs: [Int64: ItemEpoch] = [:]

    private struct ItemEpoch: Equatable, Sendable {
        let persistentID: String
        let value: Int
    }

    /// 右側可用性（AC8b）：第一次找不到先 `pending`（專輯點播的 3 秒空窗，事實 22），連續第二次才 `unavailable`
    var upcoming: DeckSnapshot.Upcoming {
        if currentIndex != nil { return .available }
        if snapshot == nil { return readFailed ? .unavailable : .pending }
        return consecutiveMisses >= 2 ? .unavailable : .pending
    }

    func applying(_ new: QueueSnapshot) -> QueueSession {
        var next = self
        next.readFailed = false
        guard new != snapshot else { return next }
        next.epochs = Self.epochs(self.epochs, updatedWith: new)
        next.currentIndex = carriedIndex(into: new)
        next.snapshot = new
        return next
    }

    /// 讀取或解析失敗：已有有效快照就沿用（R3-3），從未有過才標記
    func markingReadFailed() -> QueueSession {
        guard snapshot == nil else { return self }
        var next = self
        next.readFailed = true
        return next
    }

    func resolvingCurrent(persistentID: String, isRealChange: Bool) -> QueueSession {
        var next = self
        let matches = snapshot.map { snapshot in
            snapshot.entries.indices.filter { snapshot.entries[$0].persistentID == persistentID }
        } ?? []
        if !persistentID.isEmpty, let resolved = Self.pick(matches, previous: currentIndex, isRealChange: isRealChange) {
            next.currentIndex = resolved
            next.consecutiveMisses = 0
        } else {
            next.currentIndex = nil
            next.consecutiveMisses += 1
        }
        return next
    }

    /// D15：Music 未執行 → 整個 session 失效，下一次取得有效讀取時重建
    func invalidated() -> QueueSession { QueueSession() }

    /// 清單第 `index` 項的卡 ID（AC8 唯一規格）
    func cardID(at index: Int) -> String {
        guard let snapshot, snapshot.entries.indices.contains(index) else { return "q:?:\(index)" }
        let entry = snapshot.entries[index]
        if let itemID = entry.itemID {
            return "q:\(epochs[itemID]?.value ?? 0):\(itemID)"
        }
        let nth = snapshot.entries[..<index].filter { $0.persistentID == entry.persistentID }.count
        return "q:p:\(entry.persistentID)#\(nth)"
    }

    // MARK: - 內部

    private static func pick(_ matches: [Int], previous: Int?, isRealChange: Bool) -> Int? {
        guard !matches.isEmpty else { return nil }
        if let previous {
            if isRealChange, let after = matches.first(where: { $0 > previous }) { return after }
            if !isRealChange, matches.contains(previous) { return previous }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func epochs(_ current: [Int64: ItemEpoch], updatedWith snapshot: QueueSnapshot) -> [Int64: ItemEpoch] {
        snapshot.entries.reduce(into: current) { epochs, entry in
            guard let itemID = entry.itemID else { return }
            if let known = epochs[itemID] {
                if known.persistentID != entry.persistentID {
                    epochs[itemID] = ItemEpoch(persistentID: entry.persistentID, value: known.value + 1)
                }
            } else {
                epochs[itemID] = ItemEpoch(persistentID: entry.persistentID, value: 0)
            }
        }
    }

    /// 以 itID（同首）把上次位置帶到新快照；帶不過去 → nil，交由下一次解析依唯一性定位
    private func carriedIndex(into new: QueueSnapshot) -> Int? {
        guard let currentIndex, let old = snapshot, old.entries.indices.contains(currentIndex),
              let itemID = old.entries[currentIndex].itemID
        else { return nil }
        let persistentID = old.entries[currentIndex].persistentID
        return new.entries.firstIndex { $0.itemID == itemID && $0.persistentID == persistentID }
    }
}
