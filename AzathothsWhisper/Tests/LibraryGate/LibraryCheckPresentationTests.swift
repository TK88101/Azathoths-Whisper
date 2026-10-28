import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.2、§4.5：檢查畫面的顯示判斷（純函式）。字串鍵要在三語字串檔裡
@Suite("Library check presentation")
struct LibraryCheckPresentationTests {
    private func row(_ id: String, _ artist: String, name: String = "Song", genre: String = "Rock") -> LibraryGateReport.Row {
        let track = ScannedTrack(persistentID: id, name: name, artist: artist, album: "Paper Boats", genre: genre, hasLyrics: true, isJapanese: false)
        return LibraryGateReport(tracks: [track], artistStyles: ArtistStyleBook(), decisions: ArtistDecisionBook()).rows[0]
    }

    @Test(arguments: [
        (ProfileExplanation.Key.signed("Mayhem"), "library_check_source_signed", "Mayhem"),
        (.jpop, "library_check_source_jpop", ""),
        (.userStyle("gothic"), "library_check_source_user", "gothic"),
        (.rows(.mbGenre, ["black", "death"]), "library_check_source_mb", "black + death"),
        (.rows(.appleGenre, ["black"]), "library_check_source_apple", "black"),
        (.rows(.genericMB, ["industrial"]), "library_check_source_generic_mb", "industrial"),
        (.rows(.genericApple, ["pop"]), "library_check_source_generic_apple", "pop"),
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
        for key in LibraryCheckPresentation.allKeys {
            for language in ["en", "zh-Hant", "ja"] {
                let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj 不存在")
                let bundle = try #require(Bundle(path: path))
                #expect(bundle.localizedString(forKey: key, value: "\u{1}", table: nil) != "\u{1}", "\(language) 缺 \(key)")
            }
        }
    }
}
