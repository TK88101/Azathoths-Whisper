import Foundation
import Observation

/// 播放提示（兩個播放 ViewModel 共用）：會淡出的提示 10 s 後自動消失，換新提示或清除時取消計時
@MainActor
@Observable
final class FadingNotice {
    static let lifetime: Duration = .seconds(10)

    private(set) var current: PlaybackPresentation.Notice?
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    init(sleep: @escaping @Sendable (Duration) async -> Void) {
        self.sleep = sleep
    }

    func show(_ notice: PlaybackPresentation.Notice?) {
        task?.cancel()
        current = notice
        guard let notice, PlaybackPresentation.fades(notice) else { return }
        let sleep = self.sleep
        task = Task { [weak self] in
            await sleep(Self.lifetime)
            guard !Task.isCancelled, let self, self.current == notice else { return }
            self.current = nil
        }
    }
}
