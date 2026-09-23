import CryptoKit
import Foundation

/// 待播清單中的一項（計劃 §3 事實 20、23）
struct QueueEntry: Equatable, Sendable {
    /// AppleScript 的 `persistent ID`（16 位大寫 hex）
    let persistentID: String
    /// 佇列項身分：插入不改變既有項（事實 23）。**只在同一佇列 session 內有意義**（R4-4），
    /// 跨重寫是否會被重用沒有證據，故由 `QueueSession` 另以 epoch 區分
    let itemID: Int64?
}

/// Music 自存的待播清單 `Queue.dat` 的解析結果（計劃 D13）。只讀、純解析，不碰檔案系統。
///
/// 選序列的規則（R4-5）：`shuffleMode == off` 讀 `items.list`；其餘一律讀 `items.shuffledList`，
/// 缺失或壞型別就**整份不可用**——絕不退回 `list`（那是未打亂的原始順序，會顯示錯的「接下來」）。
/// `shuffleMode` 本身不明（型別錯、兩處不一致，或沒寫卻有打乱序列）同樣不可用（對抗覆核 P1①）。
struct QueueSnapshot: Equatable, Sendable {
    enum SequenceKind: String, Equatable, Sendable {
        case ordered
        case shuffled
    }

    let entries: [QueueEntry]
    let sequenceKind: SequenceKind
    /// 所選序列的內容雜湊：檔案 mtime 只是「要不要重讀」的提示，實質變更以此判定（R3-3）
    let contentHash: String

    static func parse(_ data: Data) -> QueueSnapshot? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let segments = root["sega"] as? [[String: Any]],
              // 實測（S8 六種情境）恆為 1 段；多段的語義未知，保守視為不可用
              segments.count == 1,
              let items = segments[0]["items"] as? [String: Any]
        else { return nil }

        guard let kind = sequenceKind(items: items, root: root) else { return nil }
        let listKey = kind == .ordered ? "list" : "shuffledList"
        guard let list = (items[listKey] as? [String: Any])?["items"] as? [String: Any],
              let raw = list["iar"] as? [[String: Any]]
        else { return nil }

        // 不在本機曲庫的項（例如串流）沒有 `tID`，無從對到曲目——略過，不影響其他項的身分
        let entries = raw.compactMap(entry)
        guard raw.isEmpty || !entries.isEmpty else { return nil }
        return QueueSnapshot(entries: entries, sequenceKind: kind, contentHash: hash(kind: kind, entries: entries))
    }

    /// `shuffleMode` 寫在 items 與頂層兩處（實檔兩處皆有、值相同）。
    /// 兩處都沒寫時：只有 `list` 一支 → 順序；另有 `shuffledList` → 無從判斷正在播哪一支，不可用。
    /// （順序模式的實檔是否寫 `shuffleMode` 尚未實測，計劃 U10）
    private static func sequenceKind(items: [String: Any], root: [String: Any]) -> SequenceKind? {
        let fields = [items["shuffleMode"], root["shuffleMode"]].compactMap { $0 }
        let modes = fields.compactMap { $0 as? String }
        guard modes.count == fields.count, Set(modes).count <= 1 else { return nil }
        guard let mode = modes.first else {
            return items["shuffledList"] == nil ? .ordered : nil
        }
        return mode == "off" ? .ordered : .shuffled
    }

    private static func entry(_ raw: [String: Any]) -> QueueEntry? {
        guard let spec = (raw["pm"] as? [String: Any])?["piObjSpec"] as? [String: Any],
              let trackID = (spec["tID"] as? NSNumber)?.int64Value
        else { return nil }
        return QueueEntry(
            persistentID: PersistentID.hex(trackID),
            itemID: (raw["itID"] as? NSNumber)?.int64Value
        )
    }

    private static func hash(kind: SequenceKind, entries: [QueueEntry]) -> String {
        let body = entries.map { "\($0.persistentID):\($0.itemID.map(String.init) ?? "-")" }.joined(separator: ",")
        return PersistentID.digest("\(kind.rawValue)|\(body)")
    }
}

/// persistentID 的文字形式與雜湊（Queue.dat 與 History.dat 共用，確保兩邊比對時同一字串）
enum PersistentID {
    /// `tID` 是有號 64 位元；AppleScript 的 `persistent ID` 是同一位元樣式的 16 位大寫 hex
    static func hex(_ value: Int64) -> String {
        String(format: "%016llX", UInt64(bitPattern: value))
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
