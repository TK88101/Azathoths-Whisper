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

    // 裝飾性靜態文案（py:183, 185, 200-201, 143, 145）
    static let txtMode = "TXT_MODE: UTF-8"
    static let lyricsPlaceholder = "// Waiting for input stream..."
    static let fakeMemory = "Mem: 64MB"
    static let fakeLatency = "Lat: 12ms"
    static let nowEditing = "Now Editing"
    static let separator = "//"
}
