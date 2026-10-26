import Foundation

extension Duration {
    /// 秒數（Double）：單調時鐘換算的唯一一處（Mac 的 SystemControlClock 與 iPad 的 MonotonicNow 共用）
    public var secondsValue: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
