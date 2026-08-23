import Foundation

/// 可注入的單調時鐘（M7 P2-2）。
///
/// 為何不用 `Date()`：退避的判定是「距上次失敗過了多久」，wall-clock 會因對時、
/// 時區、休眠而倒退——倒退時 `retryAfter` 永遠不到期，該封面就再也不重試。
protocol MonotonicClock: Sendable {
    /// 自某個固定原點起的秒數，保證單調遞增
    var now: TimeInterval { get }
}

struct SystemMonotonicClock: MonotonicClock {
    var now: TimeInterval {
        // `uptimeNanoseconds` 不隨系統時鐘調整而變（休眠期間不累加，正是退避想要的語義）
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
