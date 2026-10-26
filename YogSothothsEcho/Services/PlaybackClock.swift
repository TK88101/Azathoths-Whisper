import Foundation
import RemoteProtocol

/// 進度補間（sprint-4-detail.md §4.8；D3）：以「收到事件時的本機單調時鐘」為錨。兩台裝置的時鐘不同步，
/// `sampledAt` 是 Mac 的單調鐘，只用來丟棄亂序事件（PlaybackOrdering），絕不跨裝置相減
struct PlaybackClock: Equatable {
    let event: PlaybackEvent
    let receivedAt: Double

    func position(at now: Double) -> Double {
        let elapsed = event.state == .playing ? max(0, now - receivedAt) : 0
        let raw = max(0, event.position + elapsed)
        guard let duration = event.duration else { return raw }
        return min(raw, max(0, duration))
    }
}

/// 同一連線世代內，`sampledAt` 不大於已採用者＝亂序，丟棄；新連線（重連或 Mac 重啟，單調鐘會變小）時重置
struct PlaybackOrdering {
    private var latest: Double?

    mutating func admits(_ event: PlaybackEvent) -> Bool {
        if let latest, event.sampledAt <= latest { return false }
        latest = event.sampledAt
        return true
    }

    mutating func reset() { latest = nil }
}

/// iPad 的本機單調時鐘（秒）：程式啟動起算
enum MonotonicNow {
    private static let origin = ContinuousClock.now

    static func seconds() -> Double { (ContinuousClock.now - origin).secondsValue }
}
