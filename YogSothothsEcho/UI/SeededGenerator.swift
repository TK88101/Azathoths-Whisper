/// 固定種子的亂數（SplitMix64）：同一種子＝同一序列（控制量測的抽樣、書脊磨損形狀共用）
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0…1
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// FNV-1a 64（UTF-8 位元組）：書脊磨損與唱片花紋（CR-037）的種子共用
enum FNV1a64 {
    static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}
