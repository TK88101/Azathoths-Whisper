import Foundation

/// 以成本計的記憶體 LRU（值型別，放在 actor 內用）。單筆成本超過上限者不存。
/// 與 Mac 端 MusicRemoteBridge 的 LRUCache 同形：該模組只在 macOS，iPad 不能依賴，故各留一份。
/// 讀、寫、淘汰皆 O(1)：字典找槽位＋以陣列索引串成的雙向鏈結（頭＝最久未用），空槽回收重用
/// （s6-61-g-perf-wear.md T1；舊版淘汰掃全表，1,000 筆滿載每次寫入約 34 µs）
struct MemoryLRU<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Node: Sendable {
        var key: Key
        var value: Value
        var cost: Int
        var previous: Int?
        var next: Int?
    }

    let costLimit: Int
    private var index: [Key: Int] = [:]
    /// 已釋放的槽位為 nil
    private var nodes: [Node?] = []
    private var free: [Int] = []
    /// 最久未用
    private var head: Int?
    /// 最近使用
    private var tail: Int?
    private(set) var totalCost = 0

    init(costLimit: Int) { self.costLimit = costLimit }

    mutating func value(for key: Key) -> Value? {
        guard let slot = index[key], let node = nodes[slot] else { return nil }
        moveToTail(slot)
        return node.value
    }

    mutating func set(_ key: Key, _ value: Value, cost: Int) {
        if let slot = index[key] { remove(slot) }
        guard cost <= costLimit else { return }
        let node = Node(key: key, value: value, cost: cost, previous: tail, next: nil)
        let slot: Int
        if let reused = free.popLast() {
            slot = reused
            nodes[slot] = node
        } else {
            slot = nodes.count
            nodes.append(node)
        }
        if let tail { nodes[tail]?.next = slot } else { head = slot }
        tail = slot
        index[key] = slot
        totalCost += cost
        while totalCost > costLimit, let oldest = head { remove(oldest) }
    }

    private mutating func unlink(_ slot: Int) {
        guard let node = nodes[slot] else { return }
        if let previous = node.previous { nodes[previous]?.next = node.next } else { head = node.next }
        if let next = node.next { nodes[next]?.previous = node.previous } else { tail = node.previous }
        nodes[slot]?.previous = nil
        nodes[slot]?.next = nil
    }

    private mutating func moveToTail(_ slot: Int) {
        guard slot != tail else { return }
        unlink(slot)
        nodes[slot]?.previous = tail
        if let tail { nodes[tail]?.next = slot } else { head = slot }
        tail = slot
    }

    private mutating func remove(_ slot: Int) {
        guard let node = nodes[slot] else { return }
        unlink(slot)
        index[node.key] = nil
        totalCost -= node.cost
        nodes[slot] = nil
        free.append(slot)
    }
}
