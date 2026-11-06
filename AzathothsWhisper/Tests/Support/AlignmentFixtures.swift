@testable import AzathothsWhisper

/// 對齊測試共用的輸入建構（⑩ simcodex R1：不要每個 suite 各寫一份）
enum AlignmentFixtures {
    static func lrc(_ pairs: [(Double, String)]) -> [LRCLine] { pairs.map { LRCLine(start: $0.0, text: $0.1) } }

    /// 最壞輸入的 LRC 側（salt 2）：起點每行間隔 `step` 秒
    static func worstCaseCues(step: Double) -> [LRCLine] {
        worstCaseLines(salt: 2).enumerated().map { LRCLine(start: Double($0.offset) * step, text: $0.element) }
    }

    /// 最壞輸入：`count` 行、每行 `ProviderOutcome.maximumLineLength` 個亂數小寫字母（固定種子；salt 讓 Music 與 LRC 兩邊全不相同）
    static func worstCaseLines(count: Int = ProviderOutcome.maximumTimedLines, salt: Int) -> [String] {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return (0..<count).map { index in
            var random = SplitMix64(seed: UInt64(index * 7919 + salt))
            return String((0..<ProviderOutcome.maximumLineLength).map { _ in letters[Int(random.next() % 26)] })
        }
    }
}
