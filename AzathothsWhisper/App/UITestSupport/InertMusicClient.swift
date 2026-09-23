// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// 單元測試 host 用的 Music 替身（計劃 D11）：永遠「沒在播」、不送任何 Apple Event、不寫入。
/// 讓整輪單元測試期間不去讀使用者正在聽的歌，也不觸發 Editor 的自動抓詞。
struct InertMusicClient: MusicControlling {
    func playerState() async throws -> PlayerState { .stopped }
    func currentTrack() async throws -> TrackInfo? { nil }
    func currentLyrics() async throws -> String { "" }
    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack] { [] }
    func setLyrics(persistentID: String, lyrics: String) async throws -> Bool { false }
    func artworkData(persistentID: String) async throws -> Data? { nil }
}
#endif
