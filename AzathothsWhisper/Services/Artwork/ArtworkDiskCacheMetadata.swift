import CryptoKit
import Foundation

/// 磁碟快取的索引（M7 P2-1）。
///
/// 為何要它：檔名是 persistentID 的**完整 SHA-256**（單向），光看檔案無法還原它屬於哪首歌。
/// metadata 記 `hash → persistentID` 供讀取時驗證——沒有這層驗證，hash 碰撞會回傳**別首歌的封面**。
struct ArtworkDiskCacheMetadata: Codable, Equatable, Sendable {
    /// 格式版本。不符即視為損毀（欄位語義可能已變，猜測比重建更危險）
    static let currentVersion = 1

    struct Entry: Codable, Equatable, Sendable {
        var persistentID: String
        var size: Int
        /// 單調遞增的存取序號。**不用 wall-clock**：時鐘會倒退、同毫秒並列無法穩定排序
        var lastAccess: Int
    }

    var version: Int = ArtworkDiskCacheMetadata.currentVersion
    var nextSequence: Int = 1
    /// key＝64 hex 的 SHA-256
    var entries: [String: Entry] = [:]

    /// persistentID → 檔名。**完整 SHA-256（64 hex）**，不用前綴——
    /// 前綴長度未定義會碰撞，而碰撞的後果是回傳另一首歌的封面。
    ///
    /// 產生、驗證、temp 命名三者放在同一處：它們是同一份檔名契約的三面，
    /// 分居不同型別會讓「換 hash 演算法」這種改動很容易只改到一半
    static func fileName(for persistentID: String) -> String {
        SHA256.hash(data: Data(persistentID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// 檔名格式：64 個小寫 hex。**只有通過本檢查的 key 才允許組成檔案路徑**——
    /// metadata 是磁碟上的資料，可被竄改；直接拿 key 拼路徑等於讓它決定要刪哪個檔（路徑穿越）
    static func isValidFileName(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// 快取自己的 temp 檔：`<64hex>.tmp-<uuid>` 或 `metadata.json.tmp-<uuid>`。
    ///
    /// **不能只看 `.tmp-` 子字串**：`directory` 由呼叫端傳入、規格不保證專用，
    /// 寬鬆的謂詞會在啟動清理時刪掉使用者的 `important.tmp-notes`
    static func isOwnTempFileName(_ name: String, metadataFileName: String) -> Bool {
        guard let range = name.range(of: ".tmp-") else { return false }
        let prefix = String(name[name.startIndex..<range.lowerBound])
        let suffix = String(name[range.upperBound...])
        guard prefix == metadataFileName || isValidFileName(prefix) else { return false }
        return UUID(uuidString: suffix) != nil
    }

    /// 丟棄自相矛盾的 entry：異常值不是「保守使用」的對象，它們會污染 LRU 次序與配額計算
    func sanitized() -> ArtworkDiskCacheMetadata {
        var copy = self
        copy.nextSequence = max(1, nextSequence)
        copy.entries = entries.filter { key, entry in
            Self.isValidFileName(key)
                && !entry.persistentID.isEmpty
                && entry.size >= 0
                && entry.lastAccess >= 0
                && entry.lastAccess < copy.nextSequence
        }
        return copy
    }
}
