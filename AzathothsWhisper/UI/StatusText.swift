import Foundation

// 運行時狀態文案：原版全部硬編碼在 JS 裡，不隨語言變（ACCEPTANCE E-05）。
// 這裡集中為常量並明示「勿本地化」——加入 String Catalog 會改變原有觀察行為。
enum StatusText {
    // Editor（py:519-552）
    static let fetchingFromGenius = "Fetching from Genius..."
    static let lyricsFetched = "Lyrics fetched"
    static let lyricsNotFound = "Lyrics not found"
    static let fetchFailed = "Fetch failed"
    static let savingToMusic = "Saving to Music..."
    static let saved = "Saved"
    static let failedToSave = "Failed to save"
    static let noTrackPlaying = "No track playing"
    static let writeFailed = "Write failed"
    static let lyricsLoadedFromMusicApp = "Lyrics loaded from music app"

    // 曲目卡片（py:441-453）
    static let noArtist = "No Artist"
    static let noTrack = "No Track"
    static let accessDenied = "Access Denied"
    static let checkMacOSPermissions = "Check macOS Permissions"

    // Settings modal（py:788-858）
    static let tokenSettingsTitle = "Token Settings"
    static let languageSettingsTitle = "Language Settings"
    static let tokenCannotBeEmpty = "Token cannot be empty."
    static let validating = "Validating..."
    static let tokenValidAndSaved = "Success! Token is valid and saved."
    static let languageSaved = "Language saved. Restart app to apply."
    static let languageSaveFailed = "Error saving language."

    static func invalidToken(_ message: String) -> String { "Invalid Token: \(message)" }

    // Batch（py:554-740）——與 Editor 刻意不同之處已標註，勿統一
    static let batchReady = "Ready"                                    // C-25：Batch footer 初始值，硬編碼不隨語言變
    static let batchTitle = "Batch Processing"                         // py:210，無 data-i18n
    static let previewPlaceholder = "Select a track..."                // py:236
    static let albumLoadingPlaceholder = "Loading..."                  // py:212 header 初始
    static let noDataAlbum = "No Data / Album"                         // py:561
    static let loadingTracksFromMusic = "Loading tracks from Music..." // py:624 列表區佔位
    static let failedToLoadTracks = "Failed to load tracks."           // py:636
    static let processingAlbumBatch = "Processing album batch..."      // py:623（設在 Editor 狀態欄）
    static let albumLoaded = "Album loaded"                            // py:633
    static let batchFailed = "Batch failed"                            // py:637
    static let noMissingLyrics = "No missing lyrics to fetch!"         // py:653
    static let fetchComplete = "Fetch complete."                       // py:677
    static let selectTrackFirst = "Please select a track first to import its lyrics (from preview)."  // py:685
    static let importAllConfirm = "Writes lyrics for ALL tracks in list where lyrics are present. Continue?"  // py:715
    static let noTracksHaveLyrics = "No tracks have lyrics to save."   // py:719
    static let allSaved = "All saved."                                 // py:736
    // C-28：Batch 的存檔文案帶句點，Editor 的不帶——原版即如此，勿統一
    static let batchSaved = "Saved."                                   // py:700
    static let batchSaveFailed = "Save failed."                        // py:703
    static let batchErrorSaving = "Error saving."                      // py:707

    // C-27 進度文案
    static func fetchingTracks(_ count: Int) -> String { "Fetching \(count) tracks..." }   // py:658
    static func fetchingProgress(_ index: Int, of total: Int, title: String) -> String {   // py:662
        "Fetching (\(index)/\(total)): \(title)"
    }
    static func savingTracks(_ count: Int) -> String { "Saving \(count) tracks..." }       // py:724
    static func savingProgress(_ index: Int, of total: Int, title: String) -> String {     // py:728
        "Saving (\(index)/\(total)): \(title)"
    }
    static func savingTrack(_ title: String) -> String { "Saving \(title)..." }            // py:692

    // 裝飾性靜態文案（py:183, 185, 200-201, 143, 145）
    static let txtMode = "TXT_MODE: UTF-8"
    static let lyricsPlaceholder = "// Waiting for input stream..."
    static let fakeMemory = "Mem: 64MB"
    static let fakeLatency = "Lat: 12ms"
    static let nowEditing = "Now Editing"
    static let separator = "//"
}
