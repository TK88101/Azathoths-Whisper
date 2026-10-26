import Foundation
import RemoteProtocol
import RemoteTransport
import UIKit

/// iPad 封面快取（sprint-3-detail.md §4.6）：記憶體 LRU（解碼後的圖，64 MB）＋磁碟 LRU（`Library/Caches/Artwork`，500 MB）。
/// 同一 (albumID, token) 只有一個底層請求；同時最多 4 個在途（＝Mac 每連線封面上限），後到者先送（可視區優先）。
/// cell 消失只撤回自己的等待；全部撤回且尚未送出才放棄，已送出者做完並寫入快取。檔名＝SHA-256，不含任何 ID
actor ArtworkCache {
    typealias Fetch = @Sendable (_ albumID: String, _ token: String) async throws(EchoRequestError) -> ArtworkResponse

    static let maxInFlight = TransportLimits.maxArtworkInFlightPerConnection
    static let memoryLimit = 64 * 1_048_576
    static let diskLimit = 500 * 1_048_576
    static let diskTarget = 450 * 1_048_576
    static let indexFileName = "index.json"
    static let indexFlushDelay: Duration = .seconds(2)

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Artwork", isDirectory: true)
    }

    private enum Cached: Sendable {
        case image(UIImage)
        case none
    }

    private enum Fetched: Sendable {
        case image(UIImage, Data)
        case none, stale
    }

    private let directory: URL
    private let fetch: Fetch
    private let onStale: @Sendable () -> Void
    private let retry: ShortTransientRetry.Options
    private var memory: MemoryLRU<String, Cached>
    private var index: DiskLRUIndex?
    private let diskLimit: Int
    private let diskTarget: Int
    private var flushScheduled = false
    /// 合併與在途上限（S4 T1：與 Mac 共用 RemoteProtocol.CoalescingQueue）。後到者先送＝可視區優先；
    /// 全員撤回時已送出者做完並寫入快取（寫快取在工作閉包內，見 `image`）
    private let queue = CoalescingQueue<String, UIImage>(maxConcurrent: ArtworkCache.maxInFlight, order: .lifo, whenAbandoned: .finishRunning)

    init(directory: URL = ArtworkCache.defaultDirectory, memoryLimit: Int = ArtworkCache.memoryLimit,
         diskLimit: Int = ArtworkCache.diskLimit, diskTarget: Int = ArtworkCache.diskTarget,
         fetch: @escaping Fetch, onStale: @escaping @Sendable () -> Void, retry: ShortTransientRetry.Options = .live) {
        self.directory = directory
        self.fetch = fetch
        self.onStale = onStale
        self.retry = retry
        self.diskLimit = diskLimit
        self.diskTarget = diskTarget
        memory = MemoryLRU(costLimit: memoryLimit)
    }

    /// `networkDelay`：記憶體與磁碟都沒有、要向 Mac 要之前先等這麼久；等的期間被取消（側封的盒子只是滑過）就不送。
    /// Mac 每個連線每秒只收 60 個讀取，快甩時每個經過的盒子都去要會把配額用完，連 detail 原檔一起被擋（#6-1）
    func image(albumID: String, token: String, networkDelay: Duration = .zero) async -> UIImage? {
        let key = Self.key(albumID: albumID, token: token)
        switch memory.value(for: key) {
        case .image(let image)?: return image
        case .none?: return nil
        case nil: break
        }
        if let image = await fromDisk(key) { return image }
        if networkDelay > .zero {
            guard (try? await Task.sleep(for: networkDelay)) != nil else { return nil }
        }
        let fetch = self.fetch, retry = self.retry
        return await queue.run(key) { [weak self] in
            let fetched = await Self.download(albumID: albumID, token: token, fetch: fetch, retry: retry)
            return await self?.apply(key, fetched)
        }
    }

    /// busy／rateLimited 依 ShortTransientRetry 重試；其他錯誤、睡眠拋錯＝nil（格子維持佔位）。
    /// 不承諾可取消：佇列工作是 `.finishRunning`，畫面不再等也會跑完並寫快取（Codex R2 高-2）
    private static func download(albumID: String, token: String, fetch: Fetch, retry: ShortTransientRetry.Options) async -> Fetched? {
        for attempt in 1...ShortTransientRetry.maxAttempts {
            let response: ArtworkResponse
            do {
                response = try await fetch(albumID, token)
            } catch {
                guard ShortTransientRetry.shouldRetry(error, afterAttempt: attempt),
                      (try? await retry.pause(beforeAttempt: attempt + 1)) != nil
                else { return nil }
                continue
            }
            return decode(response)
        }
        return nil
    }

    private static func decode(_ response: ArtworkResponse) -> Fetched {
        switch response.outcome {
        case .stale: return .stale
        // restart／tooLarge 只屬於 detail（CR-018）；spine 回覆不合法地帶來時當作沒有封面
        case .none, .restart, .tooLarge: return .none
        case .image:
            guard let data = response.jpeg, let image = UIImage(data: data)?.preparingForDisplay() else { return .none }
            return .image(image, data)
        }
    }

    /// 測試與背景化時：立即寫回索引
    func flushIndex() {
        guard let index, let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: directory.appendingPathComponent(Self.indexFileName), options: .atomic)
    }

    // MARK: 磁碟

    private static func key(albumID: String, token: String) -> String {
        Data("\(albumID)|spine|\(token)".utf8).sha256Hex
    }

    private func fileURL(_ key: String) -> URL { directory.appendingPathComponent(key + ".jpg") }

    private func loadedIndex() -> DiskLRUIndex {
        if let index { return index }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let decoded = (try? Data(contentsOf: directory.appendingPathComponent(Self.indexFileName)))
            .flatMap { try? JSONDecoder().decode(DiskLRUIndex.self, from: $0) }
        let loaded = decoded ?? rebuildIndex()
        index = loaded
        return loaded
    }

    private func rebuildIndex() -> DiskLRUIndex {
        DiskLRUIndex.scanning(directory, fileExtension: "jpg", limit: diskLimit, target: diskTarget)
    }

    /// 讀檔與解碼在 actor 外做，不擋住其他格子的記憶體命中（simplify 效率 #4）；回 actor 只更新索引
    private func fromDisk(_ key: String) async -> UIImage? {
        guard loadedIndex().contains(key) else { return nil }
        let url = fileURL(key)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }.value
        var current = loadedIndex()
        guard let image else {
            current.remove(key)
            index = current
            return nil
        }
        // 只更新存取時間、不排程寫回（只影響淘汰順序；寫入新圖或背景化時才寫，simplify 效率 #5）
        current.touch(key, at: Date())
        index = current
        memory.set(key, .image(image), cost: Self.cost(image))
        return image
    }

    private func store(_ key: String, image: UIImage, data: Data) {
        var current = loadedIndex()
        if (try? data.write(to: fileURL(key), options: .atomic)) != nil {
            current.record(key, bytes: data.count, at: Date())
            for victim in current.evict() { try? FileManager.default.removeItem(at: fileURL(victim)) }
        }
        index = current
        memory.set(key, .image(image), cost: Self.cost(image))
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.indexFlushDelay)
            await self?.flushNow()
        }
    }

    private func flushNow() {
        flushScheduled = false
        flushIndex()
    }

    private static func cost(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    // MARK: 結果落地（在合併佇列的工作內執行：沒有等待者也會做完）

    private func apply(_ key: String, _ fetched: Fetched?) -> UIImage? {
        switch fetched {
        case .image(let image, let data)?:
            store(key, image: image, data: data)
            return image
        case .none?:
            memory.set(key, Cached.none, cost: 64)
        case .stale?:
            onStale()
        case nil:
            break
        }
        return nil
    }
}
