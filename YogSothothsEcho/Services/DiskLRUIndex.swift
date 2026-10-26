import Foundation

/// 封面磁碟快取的 LRU 索引（純值，sprint-3-detail.md §4.6）：記每檔大小與最後存取；
/// 總量超過上限時淘汰最久未用者到 target 以下（留餘裕，避免每次寫入都淘汰）
struct DiskLRUIndex: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var bytes: Int
        var lastAccess: Date
    }

    let limit: Int
    let target: Int
    private(set) var items: [String: Item] = [:]
    private(set) var totalBytes = 0

    init(limit: Int, target: Int) {
        self.limit = limit
        self.target = target
    }

    /// 索引遺失或損毀時，以目錄內的檔案（名稱、大小、修改時間）重建
    static func rebuilt(from files: [(key: String, bytes: Int, modified: Date)], limit: Int, target: Int) -> DiskLRUIndex {
        var index = DiskLRUIndex(limit: limit, target: target)
        for file in files { index.record(file.key, bytes: file.bytes, at: file.modified) }
        return index
    }

    /// 掃描快取目錄的檔案（檔名去副檔名＝鍵）重建；spine 與 detail 兩個磁碟快取共用
    static func scanning(_ directory: URL, fileExtension: String, limit: Int, target: Int) -> DiskLRUIndex {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        let files = urls.filter { $0.pathExtension == fileExtension }.compactMap { url -> (key: String, bytes: Int, modified: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize else { return nil }
            return (url.deletingPathExtension().lastPathComponent, size, values.contentModificationDate ?? .distantPast)
        }
        return rebuilt(from: files, limit: limit, target: target)
    }

    func contains(_ key: String) -> Bool { items[key] != nil }

    mutating func record(_ key: String, bytes: Int, at date: Date) {
        totalBytes += bytes - (items[key]?.bytes ?? 0)
        items[key] = Item(bytes: bytes, lastAccess: date)
    }

    mutating func touch(_ key: String, at date: Date) { items[key]?.lastAccess = date }

    mutating func remove(_ key: String) {
        guard let item = items.removeValue(forKey: key) else { return }
        totalBytes -= item.bytes
    }

    /// 超過 limit 時回傳被淘汰的鍵（最舊在前），並已從索引移除；呼叫端負責刪檔
    mutating func evict() -> [String] {
        guard totalBytes > limit else { return [] }
        var victims: [String] = []
        for (key, _) in items.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) where totalBytes > target {
            remove(key)
            victims.append(key)
        }
        return victims
    }
}
