import Foundation

/// 曲庫檢查畫面的顯示判斷（⑧ 計劃 §4.2、§4.5）：純函式，回傳字串檔的鍵與要嵌入的細節
enum LibraryCheckPresentation {
    struct SourceText: Equatable {
        let key: String
        /// 嵌進文案的細節（團名、列 id、票數）；沒有＝空字串
        let detail: String
        /// 附註的字串鍵（例：同歌手共識不可用、改依單曲）；沒有＝nil
        let note: String?

        init(key: String, detail: String, note: String? = nil) {
            self.key = key
            self.detail = detail
            self.note = note
        }
    }

    /// 逐首來源：推定日文帶「日文／有詞」，同歌手共識帶「列 · 票數／證據數」，共識退回單曲時加附註（增補計劃 §4.1、§4.2）
    static func source(for row: LibraryGateReport.Row) -> SourceText {
        if let estimate = row.japaneseEstimate {
            return SourceText(key: "library_check_source_jpop_estimated", detail: "\(estimate.japaneseSongs)/\(estimate.lyricsSongs)")
        }
        let base = source(row.explanation.key)
        let detail = row.consensusVote.map { "\(base.detail) · \($0.votes)/\($0.evidence)" } ?? base.detail
        let fellBack = row.explanation.trace.contains { [.appleConsensus, .genericAppleConsensus].contains($0.layer) && $0.outcome != .adopted }
        return SourceText(key: base.key, detail: detail, note: fellBack ? "library_check_consensus_fallback" : nil)
    }

    static func source(_ key: ProfileExplanation.Key) -> SourceText {
        switch key {
        case .signed(let name): SourceText(key: "library_check_source_signed", detail: name)
        case .jpop: SourceText(key: "library_check_source_jpop", detail: "")
        case .rows(let layer, let ids): SourceText(key: rowsKey(layer), detail: ids.joined(separator: " + "))
        case .none: SourceText(key: "library_check_source_none", detail: "")
        case .pending: SourceText(key: "library_check_source_pending", detail: "")
        }
    }

    private static func rowsKey(_ layer: ProfileExplanation.Layer) -> String {
        switch layer {
        case .userStyle: "library_check_source_user"
        case .mbGenre: "library_check_source_mb"
        case .appleConsensus: "library_check_source_apple_consensus"
        case .appleGenre: "library_check_source_apple"
        case .genericMB: "library_check_source_generic_mb"
        case .genericAppleConsensus: "library_check_source_generic_apple_consensus"
        case .genericApple: "library_check_source_generic_apple"
        }
    }

    static func mbStatus(_ status: LibraryGateReport.MBStatus) -> String {
        switch status {
        case .notApplicable: "library_check_mb_not_applicable"
        case .unknown: "library_check_mb_unknown"
        case .unresolved(.notFound): "library_check_mb_not_found"
        case .unresolved(.noAlbumMatch): "library_check_mb_no_album_match"
        case .unresolved(.ambiguous): "library_check_mb_ambiguous"
        case .unresolved(.collision): "library_check_mb_collision"
        case .unresolved(.emptyName): "library_check_mb_empty_name"
        case .verified(hasGenres: true): "library_check_mb_verified"
        case .verified(hasGenres: false): "library_check_mb_verified_no_genres"
        }
    }

    static func status(_ status: LibraryCheckViewModel.Status) -> String {
        switch status {
        case .notScanned: "library_check_status_not_scanned"
        case .scanning: "library_check_status_scanning"
        case .incomplete: "library_check_status_incomplete"
        case .needsRescan: "library_check_status_needs_rescan"
        case .failing: "library_check_status_failing"
        case .passed: "library_check_status_passed"
        }
    }

    static func issue(_ issue: LibraryGateReport.Issue) -> String {
        switch issue {
        case .identity: "library_check_identity"
        case .composed: "library_check_composed"
        case .readability: "library_check_readability"
        case .source: "library_check_source"
        }
    }

    static func noStyleReason(_ reason: LibraryGateReport.NoStyleReason) -> String {
        switch reason {
        case .signedBandMissingParts: "library_check_reason_signed_missing_parts"
        case .noRowMatched: "library_check_reason_no_row"
        }
    }

    /// 逐首表：只看不合格／只看一位歌手（寫法家族，增補計劃 R4）／依曲名、歌手、專輯搜尋（不分大小寫）
    static func filter(_ rows: [LibraryGateReport.Row], failingOnly: Bool, search: String, family: String? = nil) -> [LibraryGateReport.Row] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            (!failingOnly || !row.issues.isEmpty)
                && (family.map { $0 == row.familyKey } ?? true)
                && (needle.isEmpty || [row.track.name, row.track.artist, row.track.album].contains { $0.localizedCaseInsensitiveContains(needle) })
        }
    }

    /// 指定樣式的選單：曲風列、通用列兩段
    static let styleChoices = ArtistDecisionBook.selectableRows
}
