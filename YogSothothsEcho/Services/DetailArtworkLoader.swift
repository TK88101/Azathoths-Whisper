import Foundation
import RemoteProtocol
import RemoteTransport
import UIKit

/// detail 原檔分塊請求（CR-018）；正式＝LiveEchoClient，測試＝替身。spine 仍走 EchoClient.artwork（不變）
protocol DetailArtworkRequesting: Sendable {
    func artworkDetail(albumID: String, token: String, part: Int, digest: String?, generation: UInt64)
        async throws(EchoRequestError) -> ArtworkResponse
}

/// 每次開始傳輸取一個只增不減的世代（Mac 以它擋遲到的舊 part 0）。App 重開後從頭算也不會被擋：Mac 在每次新連線時釋放
/// 該 peer 的世代紀錄（RelayHost → CatalogService.releasePeer）
final class DetailGenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> UInt64 { lock.withLock { value += 1; return value } }
}

/// 唱機的原圖來源（CR-018）：先查磁碟快取，沒有才向 Mac 分塊取，成功後存回；未連線＝nil（呼叫端留在 spine）
actor DetailArtworkLoader {
    private let store: DetailArtworkStore
    private let generations = DetailGenerationCounter()
    private var requester: (any DetailArtworkRequesting)?

    init(store: DetailArtworkStore = DetailArtworkStore()) {
        self.store = store
    }

    func attach(_ requester: any DetailArtworkRequesting) { self.requester = requester }
    func detach() { requester = nil }

    /// 磁碟快取：檔頭讀得出、尺寸在上限內才算（不是圖或超過上限＝丟掉，之後向 Mac 重取）。只讀檔頭不解像素：
    /// 命中很頻繁（瀏覽每次停下 ±2 張），整張試解再丟掉會讓每次命中解兩次。S6 起由 `DetailArtworkScheduler` 不經排隊直接呼叫
    func cachedData(albumID: String, token: String) async -> Data? {
        guard let cached = await store.data(albumID: albumID, token: token) else { return nil }
        if DetailArtworkDecoder.isAcceptable(cached) { return cached }
        await store.remove(albumID: albumID, token: token)
        return nil
    }

    /// 解不開的快取（檔頭完好、內容壞）由排程器回報後刪掉
    func evict(albumID: String, token: String) async { await store.remove(albumID: albumID, token: token) }

    /// 向 Mac 分塊取；整張試解一次、解不出來（含過大的炸彈圖）不進快取——寫進快取的都確定解得開，所以命中時只驗檔頭
    /// （命中後解不開的由排程器刪掉重取）。只由 `DetailArtworkScheduler` 單飛呼叫
    func fetchData(albumID: String, token: String) async -> Data? {
        guard let requester else { return nil }
        let fetcher = DetailArtworkFetcher(directory: await store.temporaryDirectory, nextGeneration: { [generations] in generations.next() })
        let outcome = await fetcher.fetch(albumID: albumID, token: token) { part, digest, generation throws(EchoRequestError) in
            try await requester.artworkDetail(albumID: albumID, token: token, part: part, digest: digest, generation: generation)
        }
        guard case .image(let data) = outcome else { return nil }
        guard DetailArtworkDecoder.displayImage(data) != nil else {
            DetailArtworkFetcher.trace(albumID, "decode failed bytes=\(data.count)")
            return nil
        }
        await store.put(data, albumID: albumID, token: token)
        return data
    }
}
