import Foundation

/// 決定論雜湊（B1 計劃 §3.4）：FNV-1a 64 位元，以 UTF-8 位元組計。**不用 `Hasher`**——它每次啟動換種子（母計劃 §2.7，Codex R1-5）
enum FXHash {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    static func fnv1a64(_ string: String) -> UInt64 {
        string.utf8.reduce(offsetBasis) { ($0 ^ UInt64($1)) &* prime }
    }
}

/// SplitMix64：可重現的亂數序列（同種子同序列）
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// [0, 1)：取高 53 位元
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func uniform(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
}
