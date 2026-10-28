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
        case .userStyle(let id): SourceText(key: "library_check_source_user", detail: id)
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

    /// 指定樣式的選單：曲風列、通用列兩段（同 `ArtistDecisionBook.selectableRowIDs`）
    static let styleChoices = (genre: SongProfileResolver.keywordRows.map(\.id), generic: SongProfileResolver.genericRows.map(\.id))

    /// 畫面用到的全部鍵（`LibraryCheckPresentationTests` 驗三語齊）
    static let allKeys: [String] = [
        "library_check_identity", "library_check_composed", "library_check_readability", "library_check_source", "library_check_signed_pending",
        "library_check_all", "library_check_with_lyrics", "library_check_count %lld %lld", "library_check_rescan", "library_check_cancel",
        "library_check_scanned_at %@", "library_check_decided_at %@", "library_check_tab_artists", "library_check_tab_songs",
        "library_check_failing_only", "library_check_search", "library_check_choose_style", "library_check_style_genre", "library_check_style_generic",
        "library_check_keep_fallback", "library_check_clear", "library_check_bulk_keep %lld", "library_check_apply_too %@",
        "library_check_signed_note", "library_check_save_failed", "library_check_progress %lld %lld", "library_check_songs_albums %lld %lld",
        "library_check_column_title", "library_check_column_artist", "library_check_column_album", "library_check_column_source",
        "library_check_column_mb", "library_check_column_decision", "library_check_column_issues", "library_check_no_issues",
        "library_check_decision_style %@", "library_check_decision_keep",
        "library_check_source_signed", "library_check_source_jpop", "library_check_source_user", "library_check_source_mb",
        "library_check_source_apple", "library_check_source_generic_mb", "library_check_source_generic_apple", "library_check_source_none",
        "library_check_source_pending",
        "library_check_mb_not_applicable", "library_check_mb_unknown", "library_check_mb_not_found", "library_check_mb_no_album_match",
        "library_check_mb_ambiguous", "library_check_mb_collision", "library_check_mb_empty_name", "library_check_mb_verified", "library_check_mb_verified_no_genres",
        "library_check_status_not_scanned", "library_check_status_scanning", "library_check_status_incomplete", "library_check_status_needs_rescan",
        "library_check_status_failing", "library_check_status_passed",
        "library_check_reason_signed_missing_parts", "library_check_reason_no_row",
    ]
}
