import Foundation

/// 取圖失敗的退避表（M7 P2-2）。
///
/// 為何需要：`CoverFlowItemContainer` 的 `.task(id:)` 在 `LazyHStack` 回收／重建時會反覆觸發。
/// 沒有退避，一首取不到封面的曲子每次滾進畫面都會打一次 AE——正是「每次 render 重打 AE」。
struct ArtworkFailureBackoff: Sendable {
    /// 失敗次數的飽和上限。不 clamp 的話 `2^(count-1)` 會在長期失敗下溢位
    static let maxFailureCount = 7
    static let baseDelay: TimeInterval = 5
    static let maxDelay: TimeInterval = 300

    private struct Record {
        var count: Int
        var retryAfter: TimeInterval
    }

    private var records: [String: Record] = [:]

    /// 是否可以再試。無紀錄＝從未失敗＝可以
    func isDue(_ persistentID: String, now: TimeInterval) -> Bool {
        guard let record = records[persistentID] else { return true }
        return now >= record.retryAfter
    }

    /// 記錄一次成功，並回報**這次是否為從失敗中恢復**。
    ///
    /// 檢查與清除收攏成單一操作：拆成 `hasRecord()` →（跑 AE）→ `clear()` 的話，
    /// 兩步之間的順序沒有任何型別層面的保證，日後若同 ID 允許並發取圖，
    /// 就會安靜地送出錯誤的恢復通知
    /// - Returns: true＝該 ID 先前失敗過（呼叫端已顯示佔位，需要被叫醒）
    @discardableResult
    mutating func recordSuccess(_ persistentID: String) -> Bool {
        records.removeValue(forKey: persistentID) != nil
    }

    mutating func record(_ persistentID: String, now: TimeInterval) {
        let count = min((records[persistentID]?.count ?? 0) + 1, Self.maxFailureCount)
        records[persistentID] = Record(count: count, retryAfter: now + Self.delay(forCount: count))
    }

    /// 5s、10s、20s… 到 300s 封頂。**先 clamp 再取冪**，避免大指數先溢位再被 min 截斷
    static func delay(forCount count: Int) -> TimeInterval {
        let clamped = min(max(count, 1), maxFailureCount)
        return min(baseDelay * pow(2, Double(clamped - 1)), maxDelay)
    }
}
