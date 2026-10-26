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
        isVisible ? restartTimer() : cancelTimer()
    }

    /// 浮層內有操作（例如換樣式）：保持顯示並重新計時
    func poke() {
        guard isVisible else { return }
        restartTimer()
    }

    /// DEBUG 調整面板拖滑桿：編輯中停自動隱藏，放手重新計時（v2.1 T8）
    func setEditing(_ editing: Bool) {
        guard isVisible else { return }
        editing ? cancelTimer() : restartTimer()
    }

    private func restartTimer() {
        cancelTimer()
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
