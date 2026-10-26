#if os(macOS)
import Foundation

/// 以成本計的 LRU（值型別，放在 actor 內用）。單筆成本超過上限者不存
struct LRUCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Slot: Sendable { var value: Value; var cost: Int; var tick: UInt64 }

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
        remove(key)
        guard cost <= costLimit else { return }
        clock += 1
        slots[key] = Slot(value: value, cost: cost, tick: clock)
        totalCost += cost
        while totalCost > costLimit, let oldest = slots.min(by: { $0.value.tick < $1.value.tick })?.key { remove(oldest) }
    }

    mutating func removeAll(where shouldRemove: (Key) -> Bool) {
        for key in slots.keys where shouldRemove(key) { remove(key) }
    }

    private mutating func remove(_ key: Key) {
        guard let slot = slots.removeValue(forKey: key) else { return }
        totalCost -= slot.cost
    }
}
#endif
