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
