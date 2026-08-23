import Foundation
import OSLog

/// 封面的磁碟快取（M7 P2-1）：完整 SHA-256 檔名 ＋ 原子寫入 ＋ 單調序 LRU。
///
/// **actor**：`data(for:)` 會更新存取序、`store` 會觸發淘汰，兩者交錯會讓 LRU 次序與配額計算失準。
/// 串行化是配額正確性的前提，不只是資料競爭的防護。
///
/// **對內容不可知**：進出都是 bytes。編解碼（縮圖、JPEG）留在 `ArtworkService`——
/// 快取層不該知道它存的是圖片。
///
/// **所有 I/O 失敗都靜默降級為 miss**：封面丟了只是重取一次，不值得把錯誤傳到 UI。
actor ArtworkDiskCache {
    struct Limits: Sendable {
        var countLimit: Int
        var byteLimit: Int

        init(countLimit: Int = 200, byteLimit: Int = 50 * 1024 * 1024) {
            self.countLimit = countLimit
            self.byteLimit = byteLimit
        }
    }

    /// 純讀取累積多少次才落盤。崩潰最多丟這麼多次存取順序——只影響未來的淘汰次序，不影響正確性。
    /// 每次讀都寫 metadata 會讓「命中快取」比「重取」還貴
    static let accessPersistThreshold = 16

    private static let metadataFileName = "metadata.json"
    private static let tempMarker = ".tmp-"
    private static let log = Logger(
        subsystem: "com.ibridgezhao.azathothswhisper", category: "artwork-disk"
    )

    private let directory: URL
    private let limits: Limits
    private let fileManager = FileManager.default

    private var metadata = ArtworkDiskCacheMetadata()
    private var didLoad = false
    /// 目錄不可用（無法建立／無法讀取 metadata）。整個 session 降級為「永遠 miss」，
    /// 且**不刪任何檔案**——一次性的 I/O 錯誤不該演變成資料清除
    private var isDegraded = false
    private var pendingAccessUpdates = 0

    init(directory: URL, limits: Limits = Limits()) {
        self.directory = directory
        self.limits = limits
    }

    // MARK: - 對外

    func data(for persistentID: String) -> Data? {
        guard !persistentID.isEmpty else { return nil }
        ensureLoaded()
        guard !isDegraded else { return nil }

        let key = Self.fileName(for: persistentID)
        guard let entry = metadata.entries[key] else { return nil }

        // 檔名是 hash，碰撞（或 metadata 被竄改）會讓我們回傳**另一首歌的封面**
        guard entry.persistentID == persistentID else {
            discard(key)
            return nil
        }

        switch readFile(key, expectedSize: entry.size) {
        case .bytes(let payload):
            touch(key)
            return payload
        case .invalid:
            discard(key)      // 檔案不在或大小不符＝這筆 entry 已失效
            return nil
        case .unreadable:
            return nil        // 檔案還在、只是這次讀不到：留著，下次再試
        }
    }

    func store(_ data: Data, for persistentID: String) {
        guard !persistentID.isEmpty else { return }
        // 單筆就超過總配額：存了必然立刻被淘汰，白做一次 I/O
        guard data.count <= limits.byteLimit else { return }
        ensureLoaded()
        guard !isDegraded else { return }

        let key = Self.fileName(for: persistentID)
        guard writeAtomically(data, to: key) else { return }

        // 序號先求值到區域變數：`entries[key] = .init(… nextSequence())` 會讓下標賦值的獨占存取
        // 與 `nextSequence()` 對 metadata 的存取重疊，觸發 Swift 排他性違規（執行期 trap）
        let sequence = nextSequence()
        metadata.entries[key] = .init(
            persistentID: persistentID, size: data.count, lastAccess: sequence
        )
        evictIfNeeded(keeping: key)
        persist()
    }

    func remove(for persistentID: String) {
        guard !persistentID.isEmpty else { return }
        ensureLoaded()
        guard !isDegraded else { return }

        discard(Self.fileName(for: persistentID))
        persist()
    }

    /// 把累積的存取更新落盤。生產環境靠 `accessPersistThreshold` 自動觸發，本方法供測試與明確收尾使用
    func flush() {
        ensureLoaded()
        guard !isDegraded, pendingAccessUpdates > 0 else { return }
        persist()
    }

    /// 降級時回 0：`metadata` 此時停在降級前的快照，回報它等於謊稱快取仍可用
    var entryCount: Int {
        ensureLoaded()
        return isDegraded ? 0 : metadata.entries.count
    }

    /// 即時由 `entries` 求和，**不維護衍生的運行計數**。
    ///
    /// 曾一度改成運行計數器以省下 O(entries) 的加總，但那個收益是假的：
    /// `store` 每次都會 `persist()`，而 `persist()` 的 `JSONEncoder().encode(metadata)`
    /// 本就是對全部 entries 的完整遍歷＋序列化，比整數加總貴幾個數量級。
    /// 既然 O(entries) 已是每次寫入的既定成本，再省一個更便宜的 O(entries) 等於零收益，
    /// 換來的卻是五個必須手動保持同步的增減點——漏一個就是配額永久偏移且無自我糾正
    var totalBytes: Int {
        ensureLoaded()
        return isDegraded ? 0 : metadata.entries.values.reduce(0) { $0 + $1.size }
    }

    /// 檔名契約全部住在 `ArtworkDiskCacheMetadata`（產生／驗證／temp 命名三面同處）；
    /// 這裡只轉發，方便呼叫端與測試不必知道那層細節
    static func fileName(for persistentID: String) -> String {
        ArtworkDiskCacheMetadata.fileName(for: persistentID)
    }

    // MARK: - 載入與重建

    private func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Self.log.error("cache directory unavailable: \(error.localizedDescription, privacy: .public)")
            isDegraded = true
            return
        }

        switch readMetadata() {
        case .absent:
            metadata = ArtworkDiskCacheMetadata()
        case .loaded(let value):
            metadata = value.sanitized()
        case .corrupt:
            // SHA-256 單向：metadata 內容一旦損毀，磁碟上任何檔案的 persistentID 都無法還原，
            // 也就無法通過身分驗證。快取是可再生資料，清掉重取比留著無法驗證的 blob 更誠實
            metadata = ArtworkDiskCacheMetadata()
            purgeAllCacheFiles()
        case .unreadable:
            // 檔案在但讀不到（權限、暫時性錯誤）——**不刪任何東西**，本 session 純降級
            isDegraded = true
            return
        }

        reconcileWithFileSystem()
    }

    /// 讀取快取檔的三種結果。
    ///
    /// **`.invalid` 與 `.unreadable` 必須分開**——這是本型別反覆出現的同一條原則：
    /// 暫時性的 I/O／權限錯誤不是「內容損毀」，把它當損毀處理會刪掉本來好好的快取。
    /// 同樣的區分也出現在 `readMetadata`（`.unreadable`）與 `reconcileWithFileSystem`（列目錄失敗）
    private enum FileReadResult {
        case bytes(Data)
        case invalid
        case unreadable
    }

    private func readFile(_ key: String, expectedSize: Int) -> FileReadResult {
        let url = fileURL(key)
        guard fileManager.fileExists(atPath: url.path) else { return .invalid }
        guard let payload = try? Data(contentsOf: url) else {
            Self.log.error("artwork unreadable; keeping entry for a later retry")
            return .unreadable
        }
        return payload.count == expectedSize ? .bytes(payload) : .invalid
    }

    private enum MetadataReadResult {
        case absent
        case loaded(ArtworkDiskCacheMetadata)
        case corrupt
        case unreadable
    }

    private func readMetadata() -> MetadataReadResult {
        let url = metadataURL
        guard fileManager.fileExists(atPath: url.path) else { return .absent }
        guard let raw = try? Data(contentsOf: url) else { return .unreadable }
        guard let decoded = try? JSONDecoder().decode(ArtworkDiskCacheMetadata.self, from: raw),
              decoded.version == ArtworkDiskCacheMetadata.currentVersion
        else { return .corrupt }
        return .loaded(decoded)
    }

    /// 對齊 metadata 與實際檔案：兩邊只要對不上就以「刪掉、下次重取」收斂。
    /// 殘留 temp（上次寫入中途崩潰）一律清除。
    ///
    /// **只碰快取自己的三類檔案**（64 hex、`metadata.json`、`*.tmp-*`）——
    /// `directory` 由呼叫端傳入，規格不保證它是專用目錄
    private func reconcileWithFileSystem() {
        // 列目錄失敗（暫時性 I/O／權限）**不得**當成「目錄是空的」：那會刪光所有 entry，
        // 再由下一次 persist 把截斷的索引寫回，磁碟上的快取檔就成了永久 orphan。
        // 與 `readMetadata` 的 `.unreadable` 同一條原則——讀不到就降級，不清資料
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            Self.log.error("cache directory unreadable; degrading without touching files")
            isDegraded = true
            return
        }
        var present = Set<String>()
        for name in names {
            if isOwnTempFile(name) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(name))
            } else if ArtworkDiskCacheMetadata.isValidFileName(name) {
                present.insert(name)
            }
        }

        for (key, entry) in metadata.entries {
            guard present.contains(key) else {
                discard(key)                          // 有 entry 無檔（removeItem 對不存在的路徑靜默失敗）
                continue
            }
            let actualSize = (try? fileManager.attributesOfItem(atPath: fileURL(key).path)[.size] as? Int) ?? nil
            if actualSize != entry.size {
                discard(key)                          // 截斷或大小不符
            }
        }

        // 有檔無 entry：身分無從驗證，留著只會佔配額外的空間
        for name in present where metadata.entries[name] == nil {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func purgeAllCacheFiles() {
        try? fileManager.removeItem(at: metadataURL)
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where ArtworkDiskCacheMetadata.isValidFileName(name) || isOwnTempFile(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: - 內部

    /// 只認快取自己產生的 temp 檔名，避免刪到目錄裡碰巧含 `.tmp-` 的外部檔案
    private func isOwnTempFile(_ name: String) -> Bool {
        ArtworkDiskCacheMetadata.isOwnTempFileName(name, metadataFileName: Self.metadataFileName)
    }

    private var metadataURL: URL {
        directory.appendingPathComponent(Self.metadataFileName)
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(key)
    }

    private func nextSequence() -> Int {
        let value = metadata.nextSequence
        metadata.nextSequence += 1
        return value
    }

    private func touch(_ key: String) {
        let sequence = nextSequence()          // 同上：不得在下標賦值中呼叫（重疊存取）
        metadata.entries[key]?.lastAccess = sequence
        pendingAccessUpdates += 1
        if pendingAccessUpdates >= Self.accessPersistThreshold {
            persist()
        }
    }

    /// 刪 entry 與檔案。**只對合法檔名組路徑**——metadata 是磁碟資料、可被竄改，
    /// 拿任意 key 拼路徑等於讓它決定要刪哪個檔
    private func discard(_ key: String) {
        metadata.entries[key] = nil
        guard ArtworkDiskCacheMetadata.isValidFileName(key) else { return }
        try? fileManager.removeItem(at: fileURL(key))
    }

    /// temp 建在**同一目錄**（跨檔案系統 rename 會失敗）；首次寫入用 move、覆寫用 `replaceItemAt`——
    /// 兩者對「目標已存在」的行為不同，不能只走一條
    private func writeAtomically(_ data: Data, to key: String) -> Bool {
        let target = fileURL(key)
        let temp = directory.appendingPathComponent("\(key)\(Self.tempMarker)\(UUID().uuidString)")
        do {
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: target.path) {
                _ = try fileManager.replaceItemAt(target, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: target)
            }
            return true
        } catch {
            Self.log.error("artwork write failed: \(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: temp)
            return false
        }
    }

    /// 剛寫入的 entry 不參與本輪淘汰——否則單筆接近上限時會出現「寫完立刻自我淘汰」
    private func evictIfNeeded(keeping key: String) {
        while metadata.entries.count > limits.countLimit || totalBytes > limits.byteLimit {
            let candidates = metadata.entries.filter { $0.key != key }
            guard let victim = candidates.min(by: { $0.value.lastAccess < $1.value.lastAccess })
            else { break }
            discard(victim.key)
        }
    }


    /// 寫入失敗時**保留** `pendingAccessUpdates`：把沒落盤的更新當成已落盤，
    /// 會讓下次啟動的 LRU 次序悄悄回退
    private func persist() {
        let temp = directory.appendingPathComponent("\(Self.metadataFileName)\(Self.tempMarker)\(UUID().uuidString)")
        do {
            let encoded = try JSONEncoder().encode(metadata)
            try encoded.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: metadataURL.path) {
                _ = try fileManager.replaceItemAt(metadataURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: metadataURL)
            }
            pendingAccessUpdates = 0
        } catch {
            Self.log.error("metadata write failed: \(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: temp)
        }
    }
}
