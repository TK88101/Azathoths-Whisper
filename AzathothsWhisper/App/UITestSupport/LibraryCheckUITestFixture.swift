// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// ⑧ 曲庫檢查的 UI 測試假曲庫（計劃 §5 T8）：不讀使用者的 Music、不碰決定存檔（組裝時 `artistDecisions` 為 nil）。歌手與曲名自編
enum LibraryCheckUITestFixture {
    static let variable = "AZW_LIBRARY_CHECK_FIXTURE"
    /// 素面＋身分未查：要使用者指定樣式
    static let plainArtist = "Paper Harbour"
    /// 有樣式（Apple 曲風命中黑金屬列）、身分未查：可批次照目前樣式
    static let styledArtist = "Velvet Lanterns"

    static let tracks: [ScannedTrack] = [
        ScannedTrack(persistentID: "LC01", name: "Lantern Song", artist: plainArtist, album: "Night Ferry", genre: "Rock", hasLyrics: true, isJapanese: false),
        ScannedTrack(persistentID: "LC02", name: "Ash Tide", artist: styledArtist, album: "Grey Harbour", genre: "Black Metal", hasLyrics: true, isJapanese: false),
    ]

    @MainActor
    static func installIfRequested(on model: AppModel, environment: [String: String]) {
        guard environment[variable] == "1" else { return }
        let scan = LibraryScan(tracks: tracks, startedAt: Date(), finishedAt: Date())
        model.libraryCheck.scanLibrary = { progress in
            await progress(1, 1)
            return .complete(scan)
        }
        model.libraryCheck.isArtistDataReady = { true }
    }
}
#endif
