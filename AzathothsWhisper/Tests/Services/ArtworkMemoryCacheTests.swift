import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// 記憶體封面快取（M7 P1-1）。
//
// **不測驅逐時機**：`NSCache` 的 countLimit／totalCostLimit 是 soft limit，
// 實際驅逐由系統依記憶體壓力決定，斷言「超過 N 張就少於 N 張」會 flaky。
// 故測「存取契約」與「配額確實設置」；真正的容量行為屬 M8 效能觀察。
@Suite("ArtworkMemoryCache")
struct ArtworkMemoryCacheTests {
    private func image(side: CGFloat = 10) -> NSImage {
        NSImage(size: NSSize(width: side, height: side))
    }

    @Test func storesAndRetrievesByPersistentID() {
        let cache = ArtworkMemoryCache()
        let img = image()
        cache.store(img, for: "PID1")
        #expect(cache.image(for: "PID1") === img)
    }

    @Test func missReturnsNil() {
        let cache = ArtworkMemoryCache()
        #expect(cache.image(for: "absent") == nil)
    }

    /// persistentID 來自 AE，可能含特殊字元；不得因此存取失敗
    @Test func handlesPersistentIDsWithSpecialCharacters() {
        let cache = ArtworkMemoryCache()
        let weird = "../../etc/passwd\u{1}\u{0}名前"
        let img = image()
        cache.store(img, for: weird)
        #expect(cache.image(for: weird) === img)
    }

    @Test func removeAllClearsEverything() {
        let cache = ArtworkMemoryCache()
        cache.store(image(), for: "PID1")
        cache.store(image(), for: "PID2")
        cache.removeAll()
        #expect(cache.image(for: "PID1") == nil)
        #expect(cache.image(for: "PID2") == nil)
    }

    /// 配額與磁碟層（P2：200 張／50MB）是**兩套獨立上限**，不得混談
    @Test func quotasMatchSpec() {
        let cache = ArtworkMemoryCache()
        #expect(cache.countLimit == 60)
        #expect(cache.totalCostLimit == 40 * 1024 * 1024)
    }

    /// cost 以解碼後位元組估算（寬×高×4），而非原始檔大小——
    /// 記憶體壓力來自點陣圖，不是壓縮後的 JPEG
    @Test func costIsEstimatedFromDecodedBytes() {
        #expect(ArtworkMemoryCache.cost(of: image(side: 100)) == 100 * 100 * 4)
        #expect(ArtworkMemoryCache.cost(of: image(side: 512)) == 512 * 512 * 4)
    }

    /// 零尺寸圖不得產生 0 cost 而被視為「免費」無限堆積
    @Test func zeroSizedImageStillCostsAtLeastOne() {
        #expect(ArtworkMemoryCache.cost(of: NSImage(size: .zero)) >= 1)
    }
}
