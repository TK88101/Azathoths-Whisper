import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

/// 假烘焙器：記錄呼叫次數；可設定失敗；可讓烘焙卡住直到放行（測在途去重）
private actor FakeBaker: SwirlBaking {
    private(set) var calls: [Int] = []
    var failing = false
    private var gate: CheckedContinuation<Void, Never>?
    private var holding = false

    func hold() { holding = true }
    func release() { holding = false; gate?.resume(); gate = nil }
    func setFailing(_ value: Bool) { failing = value }

    func bake(_ recipe: SwirlRecipe, colors: SwirlColors, side: Int) async throws -> SwirlFace {
        calls.append(side)
        if holding { await withCheckedContinuation { gate = $0 } }
        if failing { throw SwirlBaker.Failure.encodingFailed }
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return SwirlFace(image: context.makeImage()!)
    }
}

// CR-037 T5（yse-swirl-style.md §4.4 資料流）：在途去重、位元組預算 LRU、使用中不淘汰、failed 不重試同鍵、
// 視圖用 use(_:) 的作用域登記／註銷使用中
@MainActor
struct SwirlArtworkStoreTests {
    private static func key(_ side: Int, seed: Double = 1) -> SwirlArtworkStore.Key {
        let recipe = SwirlRecipe(subtype: .pull, ink: nil, noiseSeed: seed, body: 0.4, opacity: 1)
        let colors = SwirlColors(base: .solid(.white), ink: .black, accent: nil, accentFallback: nil, opacity: 1)
        return SwirlArtworkStore.Key(recipe: recipe, colors: colors, side: side)
    }

    private static func settle(_ store: SwirlArtworkStore, until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func dedupesInFlightAndBecomesReady() async {
        let baker = FakeBaker()
        await baker.hold()
        let store = SwirlArtworkStore(baker: baker, budgetBytes: 1 << 20)
        let key = Self.key(16)
        store.request(key)
        store.request(key)
        #expect(store.state(for: key) == .baking)
        await Self.settle(store) { false }
        await baker.release()
        await Self.settle(store) { store.state(for: key)?.isReady == true }
        #expect(store.state(for: key)?.isReady == true)
        #expect(await baker.calls == [16])
    }

    @Test func failureIsNotRetriedForTheSameKey() async {
        let baker = FakeBaker()
        await baker.setFailing(true)
        let store = SwirlArtworkStore(baker: baker, budgetBytes: 1 << 20)
        let key = Self.key(16)
        store.request(key)
        await Self.settle(store) { store.state(for: key) == .failed }
        #expect(store.state(for: key) == .failed)
        store.request(key)
        await Self.settle(store) { false }
        #expect(await baker.calls.count == 1)
        store.request(Self.key(32))
        await Self.settle(store) { store.state(for: Self.key(32)) == .failed }
        #expect(await baker.calls.count == 2)
    }

    @Test func evictsLeastRecentlyUsedOverBudget() async {
        let baker = FakeBaker()
        let store = SwirlArtworkStore(baker: baker, budgetBytes: 2 * 16 * 16 * 4)
        let keys = (1...3).map { Self.key(16, seed: Double($0)) }
        for key in keys {
            store.request(key)
            await Self.settle(store) { store.state(for: key)?.isReady == true }
        }
        #expect(store.state(for: keys[0]) == nil)
        #expect(store.state(for: keys[1])?.isReady == true && store.state(for: keys[2])?.isReady == true)
        #expect(store.residentBytes <= 2 * 16 * 16 * 4)
    }

    @Test func inUseEntriesAreNeverEvicted() async {
        let baker = FakeBaker()
        let store = SwirlArtworkStore(baker: baker, budgetBytes: 16 * 16 * 4)
        let showing = Self.key(16, seed: 1)
        let task = Task { await store.use(showing) }
        await Self.settle(store) { store.state(for: showing)?.isReady == true }
        for seed in 2...3 {
            let key = Self.key(16, seed: Double(seed))
            store.request(key)
            await Self.settle(store) { store.state(for: key)?.isReady == true }
        }
        #expect(store.state(for: showing)?.isReady == true)
        task.cancel()
        await Self.settle(store) { store.inUseCount(showing) == 0 }
        #expect(store.inUseCount(showing) == 0)
    }

    @Test func missingBakerFailsImmediately() {
        let store = SwirlArtworkStore(baker: nil, budgetBytes: 1 << 20)
        store.request(Self.key(16))
        #expect(store.state(for: Self.key(16)) == .failed)
    }
}
