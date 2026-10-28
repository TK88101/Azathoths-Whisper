import Foundation
import Observation

/// 曲庫檢查（⑧ 曲庫閘門計劃 §4.5）：掃描、四項計數、使用者決定。服務由 `AppModel` 以回呼接上，feature 不持有服務
@MainActor
@Observable
final class LibraryCheckViewModel {
    enum Status: Equatable {
        case notScanned
        case scanning(done: Int, total: Int)
        /// 這次掃描讀不完整：不能判定達標（畫面保留上一份報表）
        case incomplete(LibraryScanOutcome.Reason)
        /// 掃描後 MB 資料變了、或 MB 資料還沒載入：結果要重新掃描才能確認
        case needsRescan
        case failing
        case passed
    }

    private(set) var report: LibraryGateReport?
    private(set) var decisions: ArtistDecisionBook
    private(set) var decisionsAppliedAt: Date?
    private(set) var saveFailed = false
    private var scan: LibraryScan?
    /// 算出目前報表時用的 MB 存檔：現值與它不同（或還沒載入）＝結果要重新掃描確認（R1-12）
    private var artistStylesUsed: ArtistStyleBook?
    private var scanning: (done: Int, total: Int)?
    private var lastIncomplete: LibraryScanOutcome.Reason?

    var scannedAt: Date? { scan?.finishedAt }

    @ObservationIgnored var scanLibrary: @Sendable (_ progress: @escaping @Sendable (Int, Int) async -> Void) async throws -> LibraryScanOutcome = { _ in .incomplete(.emptyLibrary) }
    /// MB 存檔的目前值；nil＝背景同步還沒發布過（還不能判定達標）
    @ObservationIgnored var artistStyles: () -> ArtistStyleBook? = { nil }
    /// 存使用者決定；失敗＝這次決定不生效
    @ObservationIgnored var onDecisionsChanged: (ArtistDecisionBook) throws -> Void = { _ in }
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(decisions: ArtistDecisionBook, now: @escaping () -> Date = Date.init) {
        self.decisions = decisions
        self.now = now
    }

    var status: Status {
        if let scanning { return .scanning(done: scanning.done, total: scanning.total) }
        if let lastIncomplete { return .incomplete(lastIncomplete) }
        guard let report else { return .notScanned }
        guard let current = artistStyles(), current == artistStylesUsed else { return .needsRescan }
        return report.passed ? .passed : .failing
    }

    // MARK: 掃描

    /// 新掃描取代舊的（generation 守衛：舊的結果一律不發布）
    func rescan() {
        scanTask?.cancel()
        generation += 1
        let current = generation
        scanning = (0, 0)
        let scan = scanLibrary
        // VM 是 @MainActor（Sendable）且由 AppModel 長期持有：掃描期間強引用無妨
        scanTask = Task {
            let outcome = try? await scan { @MainActor done, total in
                self.progress(done, total, generation: current)
            }
            self.finish(outcome, generation: current)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        generation += 1
        scanning = nil
    }

    /// 測試用：等目前的掃描結束
    func waitForScan() async {
        await scanTask?.value
    }

    private func progress(_ done: Int, _ total: Int, generation current: Int) {
        guard current == generation, scanning != nil else { return }
        scanning = (done, total)
    }

    private func finish(_ outcome: LibraryScanOutcome?, generation current: Int) {
        guard current == generation else { return }
        scanning = nil
        switch outcome {
        case .complete(let scan):
            self.scan = scan
            lastIncomplete = nil
            recompute()
        case .incomplete(let reason):
            lastIncomplete = reason
        case nil:
            break   // 取消
        }
    }

    // MARK: 使用者決定

    func decide(_ choice: ArtistDecision.Choice, forArtists artists: [String]) {
        guard let updated = try? decisions.deciding(choice, forArtists: artists, at: now()) else { return }
        apply(updated)
    }

    func clear(forArtists artists: [String]) {
        apply(decisions.clearing(forArtists: artists))
    }

    /// 只對每首都已組出樣式的歌手（計劃 §4.3）
    func keepFallbackInBulk(keys: [String]) {
        let chosen = Set(keys)
        let spellings = (report?.artists ?? []).filter { chosen.contains($0.key) && $0.canKeepFallbackInBulk }.flatMap(\.spellings)
        guard !spellings.isEmpty else { return }
        decide(.keepFallback, forArtists: spellings)
    }

    private func apply(_ updated: ArtistDecisionBook) {
        do {
            try onDecisionsChanged(updated)
        } catch {
            saveFailed = true
            return
        }
        saveFailed = false
        decisions = updated
        decisionsAppliedAt = now()
        recompute()
    }

    private func recompute() {
        guard let scan else { return }
        let styles = artistStyles()
        artistStylesUsed = styles
        report = LibraryGateReport(tracks: scan.tracks, artistStyles: styles ?? ArtistStyleBook(), decisions: decisions)
    }
}
