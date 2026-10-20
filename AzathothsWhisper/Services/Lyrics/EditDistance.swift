import Foundation

/// 全專案唯一的編輯距離（歌詞行相似度、曲目名比對共用）
enum EditDistance {
    /// 呼叫端都只問「在不在門檻內」：只算對角線兩側 `limit` 寬的帶（Ukkonen），
    /// 整列都超過 `limit` 就提早結束。門檻內回精確值，超過回 `limit + 1`（外部輸入不得拖住對齊，R3 審查）
    static func between(_ a: [Character], _ b: [Character], limit: Int = .max) -> Int {
        let (n, m) = (a.count, b.count)
        guard n > 0, m > 0 else { return clamp(max(n, m), to: limit) }
        let bound = min(limit, max(n, m))          // 距離不會超過較長者長度：避免 .max 溢位
        guard abs(n - m) <= bound else { return limit + 1 }
        let outside = bound + 1
        var previous = (0...m).map { $0 <= bound ? $0 : outside }
        var current = [Int](repeating: outside, count: m + 1)
        for i in 1...n {
            let low = max(1, i - bound), high = min(m, i + bound)
            current[0] = i <= bound ? i : outside
            if low > 1 { current[low - 1] = outside }
            var rowMinimum = low == 1 ? current[0] : outside
            if low <= high {
                for j in low...high {
                    let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                    current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution, outside)
                    rowMinimum = min(rowMinimum, current[j])
                }
            }
            if high < m { current[high + 1] = outside }
            if rowMinimum > bound { return limit + 1 }
            swap(&previous, &current)
        }
        return clamp(previous[m], to: limit)
    }

    private static func clamp(_ distance: Int, to limit: Int) -> Int {
        distance > limit ? limit + 1 : distance
    }
}
