import Foundation

@testable import AzathothsWhisper

/// 手動觸發的換歌訊號（計劃 2026-09-27-coverflow-f1-f2 §3.1）
@MainActor
final class SpyPlayerChangeSignal: PlayerChangeSignaling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onChange: (@MainActor () -> Void)?

    func start(onChange: @escaping @MainActor () -> Void) {
        guard self.onChange == nil else { return }
        startCount += 1
        self.onChange = onChange
    }

    func stop() {
        stopCount += 1
        onChange = nil
    }

    func fire() {
        onChange?()
    }
}
