import Foundation

/// token bucket（sprint-2-detail.md §4.8）；時間由呼叫端傳入，時鐘倒退不產生 token
public struct TokenBucket: Sendable {
    let capacity: Double
    let refillPerSecond: Double
    private var tokens: Double
    private var last: Date

    public init(capacity: Int, refillPerSecond: Double, now: Date) {
        self.capacity = Double(capacity)
        self.refillPerSecond = refillPerSecond
        tokens = Double(capacity)
        last = now
    }

    public mutating func take(now: Date) -> Bool {
        let elapsed = max(0, now.timeIntervalSince(last))
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        last = max(last, now)
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

/// 以鍵（全域／來源位址／連線）分開的 bucket
public struct KeyedRateLimiter<Key: Hashable & Sendable>: Sendable {
    let capacity: Int
    let refillPerSecond: Double
    private var buckets: [Key: TokenBucket] = [:]

    public init(capacity: Int, refillPerSecond: Double) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
    }

    public mutating func take(_ key: Key, now: Date) -> Bool {
        var bucket = buckets[key] ?? TokenBucket(capacity: capacity, refillPerSecond: refillPerSecond, now: now)
        let allowed = bucket.take(now: now)
        buckets[key] = bucket
        return allowed
    }

    public mutating func forget(_ key: Key) { buckets[key] = nil }
}
