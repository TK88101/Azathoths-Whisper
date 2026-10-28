import Foundation
import Observation

/// 唱機浮層（關閉鈕＋唱片樣式；sprint-5-detail.md §4.5）：顯示後 5 s 自動隱藏，每次觸發重新計時
@MainActor
@Observable
final class TurntableOverlayState {
    static let autoHide: Duration = .seconds(5)

    private(set) var isVisible = false
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func toggle() {
        isVisible.toggle()
        if isVisible {
            restartTimer()
        } else {
            endAllHolds()   // 浮層收起＝沒有東西要停（hold 永遠只在可見時存在）
            cancelTimer()
        }
    }

    /// 浮層內有操作（例如換樣式）：保持顯示並重新計時（有 hold 時不計時，見 restartTimer）
    func poke() {
        guard isVisible else { return }
        restartTimer()
    }

    /// 停自動隱藏的原因（可疊加；CR-034 增補 A r1-4）
    enum HoldReason: Hashable {
        /// DEBUG 調整面板拖滑桿（v2.1 T8）
        case tuningSlider
        /// 唱機外觀選擇器開著（浮層隱藏會讓 popover 的錨點消失）
        case skinPicker
    }

    private(set) var holds: Set<HoldReason> = []

    /// 有任何原因就停計時；浮層沒顯示時不記（沒有東西要停）
    func beginHold(_ reason: HoldReason) {
        guard isVisible else { return }
        holds.insert(reason)
        restartTimer()
    }

    /// 最後一個原因結束才重新計時；沒 begin 過的原因不動作
    func endHold(_ reason: HoldReason) {
        guard holds.remove(reason) != nil, isVisible else { return }
        restartTimer()
    }

    /// 唱機離開（關閉、斷線）：清空所有原因，不依賴視圖卸載時的回呼（r2-1）；可見性不變，仍可見就重新計時
    func endAllHolds() {
        guard !holds.isEmpty else { return }
        holds = []
        if isVisible { restartTimer() }
    }

    /// 唯一排程隱藏的地方：有任何 hold 就只取消、不重排
    private func restartTimer() {
        cancelTimer()
        guard holds.isEmpty else { return }
        let token = generation, sleep = self.sleep
        timer = Task { [weak self] in
            await sleep(Self.autoHide)
            guard let self, token == self.generation else { return }
            self.isVisible = false
        }
    }

    private func cancelTimer() {
        generation += 1
        timer?.cancel()
        timer = nil
    }
}
