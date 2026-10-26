import Foundation
import Testing

@testable import YogSothothsEcho

// S6 #6-1 g 版 T1（s6-61-g-perf-wear.md §5.3）：MemoryLRU 改 O(1)，行為與舊版（O(n) 淘汰）完全一致

/// 舊版實作原樣搬來當參考模型（淘汰＝掃全表找最舊）
private struct ReferenceLRU<Key: Hashable, Value> {
    private struct Slot { var value: Value; var cost: Int; var tick: UInt64 }
    let costLimit: Int
    private var slots: [Key: Slot] = [:]
    private var clock: UInt64 = 0
    private(set) var totalCost = 0

    init(costLimit: Int) { self.costLimit = costLimit }

    mutating func value(for key: Key) -> Value? {
        guard var slot = slots[key] else { return nil }
        clock += 1
        slot.tick = clock
        slots[key] = slot
        return slot.value
    }

    mutating func set(_ key: Key, _ value: Value, cost: Int) {
        if let old = slots.removeValue(forKey: key) { totalCost -= old.cost }
        guard cost <= costLimit else { return }
        clock += 1
        slots[key] = Slot(value: value, cost: cost, tick: clock)
        totalCost += cost
        while totalCost > costLimit, let oldest = slots.min(by: { $0.value.tick < $1.value.tick })?.key {
            totalCost -= slots.removeValue(forKey: oldest)?.cost ?? 0
        }
    }
}

struct MemoryLRUTests {
    @Test func hitRefreshesRecency() {
        var lru = MemoryLRU<String, Int>(costLimit: 2)
        lru.set("a", 1, cost: 1)
        lru.set("b", 2, cost: 1)
        _ = lru.value(for: "a")
        lru.set("c", 3, cost: 1)
        #expect(lru.value(for: "a") == 1 && lru.value(for: "b") == nil && lru.value(for: "c") == 3)
    }

    @Test func overwriteReplacesCostAndValue() {
        var lru = MemoryLRU<String, Int>(costLimit: 10)
        lru.set("a", 1, cost: 4)
        lru.set("a", 2, cost: 7)
        #expect(lru.value(for: "a") == 2 && lru.totalCost == 7)
    }

    @Test func overLimitItemIsNotStoredAndDropsOldValue() {
        var lru = MemoryLRU<String, Int>(costLimit: 5)
        lru.set("a", 1, cost: 2)
        lru.set("a", 9, cost: 6)
        #expect(lru.value(for: "a") == nil && lru.totalCost == 0)
    }

    @Test func evictsSeveralOldestForOneLargeItem() {
        var lru = MemoryLRU<String, Int>(costLimit: 10)
        for (i, key) in ["a", "b", "c", "d"].enumerated() { lru.set(key, i, cost: 2) }
        lru.set("e", 4, cost: 7)
        #expect(lru.value(for: "a") == nil && lru.value(for: "b") == nil && lru.value(for: "c") == nil)
        #expect(lru.value(for: "d") == 3 && lru.value(for: "e") == 4 && lru.totalCost == 9)
    }

    /// 固定種子的隨機操作序列：每一步的讀值與總成本都與參考模型相同（含覆寫、超限、大量淘汰、槽位重用）
    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func matchesReferenceModel(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        var lru = MemoryLRU<Int, Int>(costLimit: 100)
        var reference = ReferenceLRU<Int, Int>(costLimit: 100)
        for step in 0..<5_000 {
            let key = Int(rng.next() % 60)
            if rng.next() % 3 == 0 {
                #expect(lru.value(for: key) == reference.value(for: key), "step \(step) key \(key)")
            } else {
                let cost = Int(rng.next() % 30) + (rng.next() % 50 == 0 ? 90 : 0)
                lru.set(key, step, cost: cost)
                reference.set(key, step, cost: cost)
            }
            #expect(lru.totalCost == reference.totalCost, "step \(step)")
        }
    }

    /// 基準（附錄 B 記錄）：1,000 筆滿載、每次寫入都淘汰——O(1) 版要明顯快於 O(n) 參考
    @Test func evictionHeavyWorkloadIsFasterThanReference() {
        let n = 1_000, rounds = 20_000
        var lru = MemoryLRU<Int, Int>(costLimit: n)
        var reference = ReferenceLRU<Int, Int>(costLimit: n)
        let clock = ContinuousClock()
        let fast = clock.measure { for i in 0..<rounds { lru.set(i, i, cost: 1) } }
        let slow = clock.measure { for i in 0..<rounds { reference.set(i, i, cost: 1) } }
        print("MemoryLRU benchmark: O(1) \(fast) vs reference \(slow) for \(rounds) evicting sets at \(n) entries")
        #expect(fast * 10 < slow)
    }
}
