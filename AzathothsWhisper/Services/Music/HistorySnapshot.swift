import Foundation

/// Music 的「履歴」中的一次播完（計劃 §3 事實 25）
struct HistoryEntry: Equatable, Sendable {
    let persistentID: String
}

/// Music 自存的播放歷史 `History.dat` 的解析結果（計劃 D16）。只讀、純解析。
///
/// 只收播完的歌（Music 的語義，跳過的不進）；檔內由舊到新。
/// 每項的 persistentID 藏在 `pm.contentDesc.identifiers.libraryItemID` 的 `PID:0x…` 段。
struct HistorySnapshot: Equatable, Sendable {
    /// 最近 `keepLast` 筆，由舊到新
    let recent: [HistoryEntry]
    let contentHash: String

    static func parse(_ data: Data, keepLast: Int) -> HistorySnapshot? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = (root["items"] as? [String: Any])?["iar"] as? [[String: Any]]
        else { return nil }
        // 不在本機曲庫的項沒有 libraryItemID，無從對到曲目——略過
        let all = raw.compactMap { item -> HistoryEntry? in
            let identifiers = (((item["pm"] as? [String: Any])?["contentDesc"] as? [String: Any])?["identifiers"])
                as? [String: Any]
            return (identifiers?["libraryItemID"] as? String)
                .flatMap(persistentID(fromLibraryItemID:))
                .map(HistoryEntry.init)
        }
        let recent = Array(all.suffix(max(0, keepLast)))
        return HistorySnapshot(
            recent: recent,
            contentHash: PersistentID.digest(recent.map(\.persistentID).joined(separator: ","))
        )
    }

    /// `DBID:0x…-PID:0xf01b…-PPID:0x0-…` → `F01B…`（補足 16 位、大寫）。
    /// 以 `-` 切段、找**恰好**以 `PID:0x` 開頭的那段——子字串搜尋會誤中 `PPID:0x0`
    static func persistentID(fromLibraryItemID identifier: String) -> String? {
        let prefix = "PID:0x"
        guard let segment = identifier.split(separator: "-").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let hexDigits = segment.dropFirst(prefix.count)
        guard (1...16).contains(hexDigits.count), hexDigits.allSatisfy(\.isHexDigit),
              let value = UInt64(hexDigits, radix: 16), value != 0
        else { return nil }
        return String(format: "%016llX", value)
    }
}
