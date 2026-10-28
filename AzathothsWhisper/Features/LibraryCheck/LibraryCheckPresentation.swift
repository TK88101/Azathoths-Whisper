import Foundation

/// 曲庫檢查畫面的顯示判斷（⑧ 計劃 §4.2、§4.5）：純函式，回傳字串檔的鍵與要嵌入的細節
enum LibraryCheckPresentation {
    struct SourceText: Equatable {
        let key: String
        /// 嵌進文案的細節（團名、列 id）；沒有＝空字串
        let detail: String
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
        case .appleGenre: "library_check_source_apple"
        case .genericMB: "library_check_source_generic_mb"
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

    /// 逐首表：只看不合格／依曲名、歌手、專輯搜尋（不分大小寫）
    static func filter(_ rows: [LibraryGateReport.Row], failingOnly: Bool, search: String) -> [LibraryGateReport.Row] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            (!failingOnly || !row.issues.isEmpty)
                && (needle.isEmpty || [row.track.name, row.track.artist, row.track.album].contains { $0.localizedCaseInsensitiveContains(needle) })
        }
    }

    /// 指定樣式的選單：曲風列、通用列兩段
    static let styleChoices = ArtistDecisionBook.selectableRows
}
