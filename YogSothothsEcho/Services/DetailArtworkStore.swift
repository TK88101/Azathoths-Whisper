import Foundation
import RemoteProtocol

/// detail 原檔的磁碟快取（CR-018；sprint-5-detail.md §11）：獨立目錄與 300 MiB 配額（不擠 spine 的 500 MiB），LRU 淘汰。
/// 鍵＝SHA-256(albumID|detail|token)，檔名不含任何 ID；啟動時清掉 `tmp/` 內上次殘留的接收暫存；索引遺失或損毀＝以目錄重建。
/// 讀取命中只更新記憶體內的存取時間，索引在寫入時存檔（與 spine 快取一樣不在讀取時寫回）
actor DetailArtworkStore {
    static let diskLimit = 300 * 1_048_576
    static let diskTarget = 270 * 1_048_576
    static let indexFileName = "index.json"

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ArtworkDetail", isDirectory: true)
    }

    /// 接收暫存（DetailArtworkFetcher 的 directory）
    static func temporaryDirectory(in directory: URL) -> URL { directory.appendingPathComponent("tmp", isDirectory: true) }

    private let directory: URL
    private var index: DiskLRUIndex

    init(directory: URL = DetailArtworkStore.defaultDirectory, diskLimit: Int = DetailArtworkStore.diskLimit,
         diskTarget: Int = DetailArtworkStore.diskTarget) {
        self.directory = directory
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: Self.temporaryDirectory(in: directory))
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = (try? Data(contentsOf: directory.appendingPathComponent(Self.indexFileName)))
            .flatMap { try? JSONDecoder().decode(DiskLRUIndex.self, from: $0) }
        index = stored.map { DiskLRUIndex.rebuilt(from: $0.items.map { ($0.key, $0.value.bytes, $0.value.lastAccess) },
                                                   limit: diskLimit, target: diskTarget) }
            ?? DiskLRUIndex.scanning(directory, fileExtension: Self.fileExtension, limit: diskLimit, target: diskTarget)
    }

    var temporaryDirectory: URL { Self.temporaryDirectory(in: directory) }

    func data(albumID: String, token: String) -> Data? {
        let key = Self.key(albumID: albumID, token: token)
        guard index.contains(key) else { return nil }
        guard let data = try? Data(contentsOf: fileURL(key)) else {
            index.remove(key)   // 檔案已不在：不再佔配額
            return nil
        }
        index.touch(key, at: Date())
        return data
    }

    func put(_ data: Data, albumID: String, token: String) {
        let key = Self.key(albumID: albumID, token: token)
        guard (try? data.write(to: fileURL(key), options: .atomic)) != nil else { return }
        index.record(key, bytes: data.count, at: Date())
        for victim in index.evict() { try? FileManager.default.removeItem(at: fileURL(victim)) }
        saveIndex()
    }

    func remove(albumID: String, token: String) {
        let key = Self.key(albumID: albumID, token: token)
        index.remove(key)
        try? FileManager.default.removeItem(at: fileURL(key))
        saveIndex()
    }

    private func saveIndex() {
        guard let encoded = try? JSONEncoder().encode(index) else { return }
        try? encoded.write(to: directory.appendingPathComponent(Self.indexFileName), options: .atomic)
    }

    private static let fileExtension = "bin"

    private func fileURL(_ key: String) -> URL { directory.appendingPathComponent(key).appendingPathExtension(Self.fileExtension) }

    private static func key(albumID: String, token: String) -> String { Data("\(albumID)|detail|\(token)".utf8).sha256Hex }
}
