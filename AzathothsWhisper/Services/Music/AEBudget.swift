import Foundation

/// 一批 Apple Event 的總時限（計劃 AC8d、D14；simcodex R1）。
///
/// `SBApplication.timeout` 只管單一 AE；一批卡片詳情要送約 7 個 AE，全都擦著上限回應時
/// 會佔住 AE 串行佇列十幾秒、餓到當前曲輪詢。每送一個 AE 前以剩餘時間當它的 timeout，
/// 不足 1 tick 就停——呼叫端把整批當讀取失敗（卡片退為 unknown）。
struct AEBudget {
    /// `SBApplication.timeout` 的單位（1 tick＝1/60 秒）
    static let ticksPerSecond = 60

    let total: Duration
    let start: ContinuousClock.Instant

    /// 剩餘時間換成 tick（無條件捨去）；不足 1 tick → nil
    func remainingTicks(at now: ContinuousClock.Instant) -> Int? {
        let remaining = (start + total) - now
        let ticks = Int(remaining / .seconds(1) * Double(Self.ticksPerSecond))
        return ticks >= 1 ? ticks : nil
    }

    /// 送任何一個 AE 前的唯一扣預算步驟：還有至少 1 tick → 以剩餘時間設 timeout、回 true；用完 → 不設、回 false（整批放棄）
    func spend(setTimeout: (Int) -> Void, now: ContinuousClock.Instant = .now) -> Bool {
        guard let ticks = remainingTicks(at: now) else { return false }
        setTimeout(ticks)
        return true
    }

    /// 依序讀各欄（每欄一個 AE）：每欄先 `spend`；用完就不再送、回 nil＝整批作廢
    func readColumns<Key>(
        _ keys: [Key],
        setTimeout: (Int) -> Void,
        read: (Key) -> [Any],
        now: () -> ContinuousClock.Instant = { .now }
    ) -> [[Any]]? {
        var columns: [[Any]] = []
        for key in keys {
            guard spend(setTimeout: setTimeout, now: now()) else { return nil }
            columns.append(read(key))
        }
        return columns
    }
}
