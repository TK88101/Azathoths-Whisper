import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.2、§4.5：檢查畫面的顯示判斷（純函式）。字串鍵要在三語字串檔裡
@Suite("Library check presentation")
struct LibraryCheckPresentationTests {
    /// 畫面用到的全部鍵（含 View 裡直接寫的字面鍵）：三語都要齊
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
        "library_check_source_jpop_estimated", "library_check_source_apple_consensus", "library_check_source_generic_apple_consensus",
        "library_check_consensus_fallback", "library_check_column_apple_genre", "library_check_show_artist_songs",
        "library_check_artist_filter %@", "library_check_clear_filter", "library_check_consensus_mb_first",
    ]

    private func row(_ id: String, _ artist: String, name: String = "Song", genre: String = "Rock") -> LibraryGateReport.Row {
        let track = ScannedTrack(persistentID: id, name: name, artist: artist, album: "Paper Boats", genre: genre, hasLyrics: true, isJapanese: false)
        return LibraryGateReport(tracks: [track], artistStyles: ArtistStyleBook(), decisions: ArtistDecisionBook()).rows[0]
    }

    @Test(arguments: [
        (ProfileExplanation.Key.signed("Mayhem"), "library_check_source_signed", "Mayhem"),
        (.jpop, "library_check_source_jpop", ""),
        (.rows(.userStyle, ["gothic"]), "library_check_source_user", "gothic"),
        (.rows(.mbGenre, ["black", "death"]), "library_check_source_mb", "black + death"),
        (.rows(.appleGenre, ["black"]), "library_check_source_apple", "black"),
        (.rows(.genericMB, ["industrial"]), "library_check_source_generic_mb", "industrial"),
        (.rows(.genericApple, ["pop"]), "library_check_source_generic_apple", "pop"),
        (.rows(.appleConsensus, ["hardrock"]), "library_check_source_apple_consensus", "hardrock"),
        (.rows(.genericAppleConsensus, ["pop"]), "library_check_source_generic_apple_consensus", "pop"),
        (.none, "library_check_source_none", ""),
        (.pending, "library_check_source_pending", ""),
    ] as [(ProfileExplanation.Key, String, String)])
    func everySourceHasAKeyAndADetail(key: ProfileExplanation.Key, expected: String, detail: String) {
        let text = LibraryCheckPresentation.source(key)
        #expect(text.key == expected)
        #expect(text.detail == detail)
    }

    @Test(arguments: [
        (LibraryGateReport.MBStatus.notApplicable, "library_check_mb_not_applicable"),
        (.unknown, "library_check_mb_unknown"),
        (.unresolved(.notFound), "library_check_mb_not_found"),
        (.unresolved(.noAlbumMatch), "library_check_mb_no_album_match"),
        (.unresolved(.ambiguous), "library_check_mb_ambiguous"),
        (.unresolved(.collision), "library_check_mb_collision"),
        (.unresolved(.emptyName), "library_check_mb_empty_name"),
        (.verified(hasGenres: true), "library_check_mb_verified"),
        (.verified(hasGenres: false), "library_check_mb_verified_no_genres"),
    ] as [(LibraryGateReport.MBStatus, String)])
    func everyMBStatusHasAKey(status: LibraryGateReport.MBStatus, expected: String) {
        #expect(LibraryCheckPresentation.mbStatus(status) == expected)
    }

    @Test(arguments: [
        (LibraryCheckViewModel.Status.notScanned, "library_check_status_not_scanned"),
        (.scanning(done: 1, total: 2), "library_check_status_scanning"),
        (.incomplete(.tracksMissing), "library_check_status_incomplete"),
        (.needsRescan, "library_check_status_needs_rescan"),
        (.failing, "library_check_status_failing"),
        (.passed, "library_check_status_passed"),
    ] as [(LibraryCheckViewModel.Status, String)])
    func everyStatusHasAKey(status: LibraryCheckViewModel.Status, expected: String) {
        #expect(LibraryCheckPresentation.status(status) == expected)
    }

    // 增補計劃 §4.1、§4.2：推定與共識的來源要帶可核對的數字

    private func report(_ tracks: [ScannedTrack]) -> LibraryGateReport {
        LibraryGateReport(tracks: tracks, artistStyles: ArtistStyleBook(), decisions: ArtistDecisionBook())
    }

    private func track(_ id: String, _ artist: String, genre: String = "Rock", lyrics: Bool = true, japanese: Bool = false) -> ScannedTrack {
        ScannedTrack(persistentID: id, name: "Song \(id)", artist: artist, album: "Paper Boats", genre: genre, hasLyrics: lyrics, isJapanese: japanese)
    }

    @Test func anEstimatedSongShowsJapaneseOverWithLyrics() throws {
        let r = report([track("1", "Paper Harbour", japanese: true), track("2", "Paper Harbour", japanese: true), track("3", "Paper Harbour"), track("4", "Paper Harbour", lyrics: false)])
        let row = try #require(r.rows.last)
        #expect(LibraryCheckPresentation.source(for: row, consensus: nil) == .init(key: "library_check_source_jpop_estimated", detail: "2/3", note: nil))
    }

    @Test func aConsensusSongShowsTheRowsAndTheVotes() throws {
        let r = report([track("1", "Paper Harbour", genre: "Hard Rock"), track("2", "Paper Harbour", genre: "Hard Rock"), track("3", "Paper Harbour", genre: "Gothic"), track("4", "Paper Harbour")])
        let row = try #require(r.rows.last)
        #expect(LibraryCheckPresentation.source(for: row, consensus: r.consensus[row.familyKey])
            == .init(key: "library_check_source_apple_consensus", detail: "hardrock · 2/3", note: nil))
    }

    @Test func aFallbackFromTheConsensusIsShown() throws {
        let explanation = ProfileExplanation(
            resolution: .genreRow(SongProfileResolver.compose(genres: ["Gothic"])!), key: .rows(.appleGenre, ["gothic"]),
            trace: [.init(layer: .appleConsensus, rowIDs: ["retired"], outcome: .noHit), .init(layer: .appleGenre, rowIDs: ["gothic"], outcome: .adopted)]
        )
        let base = row("1", "Paper Harbour")
        let fallback = LibraryGateReport.Row(
            track: base.track, familyKey: base.familyKey, explanation: explanation, mbStatus: base.mbStatus, decision: nil, noStyleReason: nil,
            issues: [], japaneseEstimate: nil
        )
        #expect(LibraryCheckPresentation.source(for: fallback, consensus: nil)
            == .init(key: "library_check_source_apple", detail: "gothic", note: "library_check_consensus_fallback"))
        #expect(LibraryCheckPresentation.source(for: base, consensus: nil).note == nil)
        let mbFirst = LibraryGateReport.Row(
            track: base.track, familyKey: base.familyKey,
            explanation: ProfileExplanation(resolution: explanation.resolution, key: explanation.key, trace: [.init(layer: .appleConsensus, rowIDs: ["altindie"], outcome: .overriddenByMB)]),
            mbStatus: base.mbStatus, decision: nil, noStyleReason: nil, issues: [], japaneseEstimate: nil
        )
        #expect(LibraryCheckPresentation.source(for: mbFirst, consensus: nil).note == "library_check_consensus_mb_first")
    }

    @Test func theSongListCanShowOneArtistFamily() {
        let rows = report([track("1", "Paper Harbour"), track("2", "PAPER HARBOUR"), track("3", "Velvet Lanterns")]).rows
        let family = ArtistDecisionBook.key("Paper Harbour")
        #expect(LibraryCheckPresentation.filter(rows, failingOnly: false, search: "", family: family).map(\.track.persistentID) == ["1", "2"])
        #expect(LibraryCheckPresentation.filter(rows, failingOnly: false, search: "", family: nil).count == 3)
    }

    @Test func theSongListFiltersByIssueAndSearch() {
        let rows = [row("1", "Mayhem", name: "Night Ferry", genre: "Black Metal"), row("2", "Paper Harbour", name: "Lantern Song")]
        #expect(LibraryCheckPresentation.filter(rows, failingOnly: true, search: "").map(\.track.persistentID) == ["2"])
        #expect(LibraryCheckPresentation.filter(rows, failingOnly: false, search: "ferry").map(\.track.persistentID) == ["1"])
        #expect(LibraryCheckPresentation.filter(rows, failingOnly: false, search: "harbour").map(\.track.persistentID) == ["2"], "歌手名也搜")
        #expect(LibraryCheckPresentation.filter(rows, failingOnly: false, search: "boats").count == 2, "專輯名也搜")
        #expect(LibraryCheckPresentation.filter(rows, failingOnly: false, search: "  ").count == 2)
    }

    @Test func theStyleMenuListsGenreRowsThenGenericRows() {
        let menu = LibraryCheckPresentation.styleChoices
        #expect(menu.genre == SongProfileResolver.keywordRows.map(\.id))
        #expect(menu.generic == SongProfileResolver.genericRows.map(\.id))
    }

    /// 畫面用到的每個鍵都在字串檔，三語齊（CLAUDE.md i18n）
    @Test func everyKeyIsTranslatedIntoThreeLanguages() throws {
        for key in Self.allKeys {
            for language in ["en", "zh-Hant", "ja"] {
                let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj 不存在")
                let bundle = try #require(Bundle(path: path))
                #expect(bundle.localizedString(forKey: key, value: "\u{1}", table: nil) != "\u{1}", "\(language) 缺 \(key)")
            }
        }
    }
}
