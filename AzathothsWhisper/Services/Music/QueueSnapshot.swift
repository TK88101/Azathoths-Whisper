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

        let shuffleMode = (items["shuffleMode"] as? String) ?? (root["shuffleMode"] as? String) ?? "off"
        let kind: SequenceKind = shuffleMode == "off" ? .ordered : .shuffled
        let listKey = kind == .ordered ? "list" : "shuffledList"
        guard let list = (items[listKey] as? [String: Any])?["items"] as? [String: Any],
              let raw = list["iar"] as? [[String: Any]]
        else { return nil }

        // 不在本機曲庫的項（例如串流）沒有 `tID`，無從對到曲目——略過，不影響其他項的身分
        let entries = raw.compactMap(entry)
        guard raw.isEmpty || !entries.isEmpty else { return nil }
        return QueueSnapshot(entries: entries, sequenceKind: kind, contentHash: hash(kind: kind, entries: entries))
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
