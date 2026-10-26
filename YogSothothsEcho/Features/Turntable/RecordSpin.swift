import Foundation

/// 唱片旋轉角（D11；spec：20 s 一圈、線性、暫停停在當前角度、恢復續轉）。時間單位是秒（本機單調時鐘）。
/// G7 加煞停：甩動切歌時 350 ms 內線性減速到 0，角度連續（sprint-5-detail.md §4.4 v1.3）
struct RecordSpin: Equatable {
    enum Motion: Equatable { case spinning, braking, still }

    static let degreesPerSecond = 360.0 / 20
    static let brakeSeconds = 0.35

    private var base = 0.0
    /// 轉動中的起點（spinning 或 braking 時有值）
    private var anchor: Double?
    private var braking = false

    func angle(at now: Double) -> Double {
        guard let anchor else { return base }
        let v = Self.degreesPerSecond
        let elapsed = max(0, now - anchor)
        guard braking else { return (base + v * elapsed).truncatingRemainder(dividingBy: 360) }
        let t = min(elapsed, Self.brakeSeconds)
        return (base + v * t - v * t * t / (2 * Self.brakeSeconds)).truncatingRemainder(dividingBy: 360)
    }

    /// 同一狀態重複通知不重設錨點；從靜止開始煞停＝維持靜止
    mutating func update(_ motion: Motion, at now: Double) {
        switch motion {
        case .spinning:
            guard anchor == nil || braking else { return }
            base = angle(at: now)
            anchor = now
            braking = false
        case .braking:
            guard anchor != nil, !braking else { return }
            base = angle(at: now)
            anchor = now
            braking = true
        case .still:
            guard anchor != nil else { return }
            base = angle(at: now)
            anchor = nil
            braking = false
        }
    }

    mutating func update(spinning: Bool, at now: Double) { update(spinning ? .spinning : .still, at: now) }
}
