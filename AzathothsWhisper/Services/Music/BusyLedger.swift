/// 「誰還忙著」的記帳（自 `NowPlayingMonitor` 抽出，A1 計劃 §3.3）。
///
/// monitor 與位置時鐘各持一份、由 `AppModel` 以同一個 `BusySource` 扇出（母計劃 §2.3 R2）。
/// 回傳的是**轉移**：已空閒時再送 false 是 `.unchanged`，不得當成「變成空閒」而錯觸補讀
struct BusyLedger: Sendable {
    enum Transition: Equatable, Sendable {
        case becameBusy
        case becameIdle
        case unchanged
    }

    private(set) var sources: Set<BusySource> = []

    var isIdle: Bool { sources.isEmpty }

    mutating func set(_ busy: Bool, source: BusySource) -> Transition {
        let wasIdle = isIdle
        if busy {
            sources.insert(source)
        } else {
            sources.remove(source)
        }
        switch (wasIdle, isIdle) {
        case (true, false): return .becameBusy
        case (false, true): return .becameIdle
        default: return .unchanged
        }
    }
}
