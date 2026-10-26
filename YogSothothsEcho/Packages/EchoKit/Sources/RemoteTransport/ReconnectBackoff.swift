import Foundation
import RemoteProtocol

/// iPad 重連退避（sprint-2-detail.md §4.8）：1, 2, 4 … 秒，上限 30 秒，乘上 0.8…1.2 的抖動（由呼叫端注入）
public enum ReconnectBackoff {
    public static func delay(attempt: Int, jitter: Double) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let base = min(TransportLimits.reconnectCap, pow(2, Double(exponent)))   // 大指數時 pow＝inf，min 仍取上限
        return base * clamped(jitter)
    }

    private static func clamped(_ jitter: Double) -> Double { min(1.2, max(0.8, jitter)) }
}
