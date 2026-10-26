#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import RemoteProtocol
@testable import MusicRemoteBridge

// T5（sprint-3-detail.md §4.5）：縮圖、Mac 端 LRU（同鍵合併與並行上限的測試已隨 S4 T1 移到 RemoteProtocolTests/CoalescingQueueTests）

enum TestImage {
    /// 偽隨機雜訊圖（壓縮最差）編成 PNG
    static func noisePNG(width: Int, height: Int, seed: UInt64 = 1) -> Data {
        var state = seed
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in pixels.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            pixels[i] = i % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 33)
        }
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    static func pixelSize(_ data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}

struct ArtworkRendererTests {
    @Test func spineLongSideIs160() throws {
        let jpeg = try #require(ArtworkRenderer.spineJPEG(from: TestImage.noisePNG(width: 1000, height: 500)))
        let size = try #require(TestImage.pixelSize(jpeg))
        #expect(size.0 == CatalogLimits.spinePixels && size.1 == 80)
    }

    @Test func smallImageIsNotUpscaled() throws {
        let jpeg = try #require(ArtworkRenderer.spineJPEG(from: TestImage.noisePNG(width: 40, height: 40)))
        #expect(TestImage.pixelSize(jpeg).map { $0.0 <= 40 } == true)
    }

    @Test func worstCaseNoiseFitsSpineBudget() throws {
        let jpeg = try #require(ArtworkRenderer.spineJPEG(from: TestImage.noisePNG(width: 2000, height: 2000)))
        #expect(jpeg.count <= CatalogLimits.spineMaxJPEGBytes)
    }

    @Test func extremeAspectRatioWorks() throws {
        let jpeg = try #require(ArtworkRenderer.spineJPEG(from: TestImage.noisePNG(width: 1, height: 3000)))
        #expect(TestImage.pixelSize(jpeg).map { $0.1 == CatalogLimits.spinePixels } == true)
    }

    @Test func steppedQualityShrinksUntilBudget() throws {
        let png = TestImage.noisePNG(width: 400, height: 400)
        let atDefault = try #require(ArtworkRenderer.spineJPEG(from: png))
        let budget = atDefault.count - 1
        let stepped = try #require(ArtworkRenderer.spineJPEG(from: png, maxBytes: budget))
        #expect(stepped.count <= budget)
    }

    @Test func impossibleBudgetReturnsNil() {
        #expect(ArtworkRenderer.spineJPEG(from: TestImage.noisePNG(width: 400, height: 400), maxBytes: 100) == nil)
    }

    @Test func corruptDataReturnsNil() {
        #expect(ArtworkRenderer.spineJPEG(from: Data("not an image".utf8)) == nil)
        #expect(ArtworkRenderer.spineJPEG(from: Data()) == nil)
    }
}

struct LRUCacheTests {
    @Test func evictsLeastRecentlyUsedByCost() {
        var cache = LRUCache<String, Int>(costLimit: 10)
        cache.set("a", 1, cost: 4)
        cache.set("b", 2, cost: 4)
        _ = cache.value(for: "a")          // a 變成最近使用
        cache.set("c", 3, cost: 4)         // 超過 10 → 淘汰 b
        #expect(cache.value(for: "b") == nil)
        #expect(cache.value(for: "a") == 1 && cache.value(for: "c") == 3)
        #expect(cache.totalCost == 8)
    }

    @Test func replacingKeyUpdatesCost() {
        var cache = LRUCache<String, Int>(costLimit: 10)
        cache.set("a", 1, cost: 8)
        cache.set("a", 2, cost: 2)
        #expect(cache.totalCost == 2 && cache.value(for: "a") == 2)
    }

    @Test func itemLargerThanLimitIsNotStored() {
        var cache = LRUCache<String, Int>(costLimit: 10)
        cache.set("a", 1, cost: 3)
        cache.set("big", 2, cost: 11)
        #expect(cache.value(for: "big") == nil && cache.value(for: "a") == 1)
    }

    @Test func removeWhereDropsMatchingEntries() {
        var cache = LRUCache<String, Int>(costLimit: 100)
        cache.set("keep", 1, cost: 1)
        cache.set("drop", 2, cost: 1)
        cache.removeAll { $0 == "drop" }
        #expect(cache.value(for: "drop") == nil && cache.totalCost == 1)
    }
}

/// 輪詢直到條件成立（最多約 2 s）；CatalogServiceTests 等共用
func eventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}
#endif
