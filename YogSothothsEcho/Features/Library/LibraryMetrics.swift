import Foundation
import Observation

/// 首頁計時（sprint-3-detail.md §4.11）：起點＝連線就緒後開始載入；終點＝首屏格子的封面都已解碼並設到畫面
/// 或確定沒有封面。只記數值，不記任何名稱。DEBUG 的量測畫面讀它；Release 也存在但不輸出
@MainActor
@Observable
final class LibraryMetrics {
    private(set) var loadStartedAt: Date?
    private(set) var firstScreenSeconds: Double?
    private(set) var firstScreenCells = 0
    @ObservationIgnored private var pendingFirstScreen: Set<String>?
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) { self.now = now }

    func loadStarted() {
        loadStartedAt = now()
        firstScreenSeconds = nil
        pendingFirstScreen = nil
    }

    /// 第一頁到達後第一次版面配置時，與可視區相交的格子
    func firstScreen(ids: [String]) {
        guard pendingFirstScreen == nil, firstScreenSeconds == nil, !ids.isEmpty else { return }
        pendingFirstScreen = Set(ids)
        firstScreenCells = ids.count
    }

    /// 某格的封面已顯示或確定沒有封面
    func artworkSettled(id: String) {
        guard var pending = pendingFirstScreen, let started = loadStartedAt else { return }
        pending.remove(id)
        pendingFirstScreen = pending
        if pending.isEmpty, firstScreenSeconds == nil { firstScreenSeconds = now().timeIntervalSince(started) }
    }
}
