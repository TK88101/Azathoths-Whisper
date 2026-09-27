import Foundation

/// Import All 一整批的結局（計劃 2026-09-26-lyrics-notification §4.3a）。
/// 「失敗」＝ `setLyrics` 回 false 或 throw；`stale`＝中途被切專輯作廢（寫入過的仍是事實）
enum BatchImportOutcome: Equatable, Sendable {
    case allSucceeded
    case someFailed
    case allFailed
    case stale
}

/// Batch 一次匯入的事實事件。只有 `.batch(_, .allSucceeded)` 與 `.single(isStale: false)` 會觸發自動切回 Editor 分頁（§4.6）
enum BatchImportResult: Equatable, Sendable {
    /// Import Selected：只在寫入成功（didWrite）時送
    case single(artist: String, title: String, album: String, isStale: Bool)
    /// Import All：每一輪結束都送（含 stale），通知由 summary 產生
    case batch(BatchWriteSummary, BatchImportOutcome)

    /// 是否要排「自動切回 Editor 分頁」（§4.6 觸發條件，使用者 2026-09-26 拍板）
    var returnsToEditor: Bool {
        switch self {
        case .single(_, _, _, let isStale): return !isStale
        case .batch(_, let outcome): return outcome == .allSucceeded
        }
    }
}
