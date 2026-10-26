import CoreGraphics
import Testing

@testable import YogSothothsEcho

// S6 #6-1 g 版 T1：FaceTextureCache 以位元組計成本（MemoryLRU），超過預算淘汰最久未用
@MainActor
struct FaceTextureCacheTests {
    static func key(_ id: String) -> FaceTexture.Key { .front(albumID: id, length: 10) }
    static let bytes = 10 * 10 * 4

    @Test func evictsLeastRecentlyUsedByBytes() {
        let cache = FaceTextureCache(byteLimit: 3 * Self.bytes)
        cache.rendersSynchronously = true
        for id in ["a", "b", "c"] { _ = cache.cached(Self.key(id)) }
        _ = cache.cached(Self.key("a"))
        _ = cache.cached(Self.key("d"))
        #expect(cache.totalBytes == 3 * Self.bytes)
        let before = cache.renderCount
        _ = cache.cached(Self.key("a"))
        #expect(cache.renderCount == before)
        _ = cache.cached(Self.key("b"))
        #expect(cache.renderCount == before + 1)
    }

    @Test func defaultBudgetIsDocumented() {
        #expect(FaceTextureCache.byteLimit == 48 * 1_048_576)
    }
}
