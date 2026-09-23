import Foundation

// Music.app 控制面的協議與資料型別（Plan §4.3）。
// 曲目身分一律以 persistentID 為主（M2 審查 H4）；(artist,title,album) 僅在無 ID 時 fallback。

struct TrackInfo: Equatable, Sendable, Identifiable {
    let persistentID: String
    let artist: String
    let title: String
    let album: String
    let discNumber: Int
    let trackNumber: Int

    var id: String { persistentID }

    /// 切歌偵測用簽名：有 ID 用 ID，否則退回三元組（原版只用 (artist,title)，會撞號）
    var signature: String {
        persistentID.isEmpty ? "\(artist)\u{1}\(title)\u{1}\(album)" : persistentID
    }

    /// 專輯變更偵測用鍵（原版只比對 album 字串）
    var albumKey: String { "\(artist)\u{1}\(album)" }
}

struct AlbumTrack: Equatable, Sendable, Identifiable {
    let persistentID: String
    let artist: String
    let title: String
    let album: String
    let discNumber: Int
    let trackNumber: Int
    let lyrics: String

    var id: String { persistentID }

    /// C-29（用戶 2026-08-14 拍板）：純空白＝缺詞。
    /// 原版三處篩選用未 strip 的 `lyrics.length > 0`，而算好的 `has_lyrics`（strip 判空，py:2253）
    /// 從未被前端使用——屬原版內部不一致。此處採 strip 語義並記為已批准偏差（判定見 `LyricsText`）。
    var hasLyrics: Bool { !LyricsText.isBlank(lyrics) }

    /// 抓詞命中／寫入成功後產生新值（不就地改動）
    func withLyrics(_ newLyrics: String) -> AlbumTrack {
        AlbumTrack(
            persistentID: persistentID, artist: artist, title: title, album: album,
            discNumber: discNumber, trackNumber: trackNumber, lyrics: newLyrics
        )
    }
}

/// 當前曲的一次讀取（計劃 D9）：曲目欄位與歌詞出自**同一次**對釘住 specifier 的讀取。
/// 舊做法先讀曲目、再另讀歌詞，兩次各自重新解析 `current track`，中間換歌就會得到 A 的曲目＋B 的歌詞
struct NowPlayingRead: Equatable, Sendable {
    let track: TrackInfo
    /// nil＝歌詞讀取失敗（→ unknown）。**不得折疊成空字串**：那會被當成缺詞而降下 Editor
    let lyrics: String?
}

/// Cover Flow 卡片需要的曲目詳情（計劃 D14），以 persistentID 批次讀取
struct TrackDetails: Equatable, Sendable {
    let persistentID: String
    let artist: String
    let title: String
    let album: String
    let discNumber: Int
    let trackNumber: Int
    /// nil＝讀不到（→ unknown）
    let lyrics: String?
}

enum PlayerState: Equatable, Sendable {
    case playing
    case paused
    case stopped
    case other(String)

    /// py:1108-1128：playing 與 paused 都視為「有當前曲目」，只有 stopped/無曲才算沒有
    var hasCurrentTrack: Bool {
        self == .playing || self == .paused
    }
}

enum MusicError: Error, Equatable {
    case permissionDenied      // AE -1743 errAEEventNotPermitted
    case notRunning
    case scriptingFailure(String)
}

/// Music.app 的控制面。**只有唯讀方法＋既有的 `setLyrics`**——無任何播控（計劃 AC9 ①；
/// ② 執行期選擇器白名單見 `MusicSelectorAllowListTests`，③ 腳本閘門見 `Scripts/no_playback_gate.sh`）
protocol MusicControlling: Sendable {
    func playerState() async throws -> PlayerState
    func currentTrack() async throws -> TrackInfo?
    /// 監控用：曲目＋歌詞一次讀完（D9）
    func nowPlaying() async throws -> NowPlayingRead?
    /// 卡片詳情：一批 persistentID 一次讀完（D14；找不到的不回傳）
    func trackDetails(persistentIDs: [String]) async throws -> [TrackDetails]
    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack]
    func setLyrics(persistentID: String, lyrics: String) async throws -> Bool
    func artworkData(persistentID: String) async throws -> Data?
}

// Cover Flow 的穩定排序（Plan §4.8，M2 審查 M12）：disc → track → AE 返回序
extension Array where Element == AlbumTrack {
    func sortedForDisplay() -> [AlbumTrack] {
        enumerated()
            .sorted { lhs, rhs in
                if lhs.element.discNumber != rhs.element.discNumber {
                    return lhs.element.discNumber < rhs.element.discNumber
                }
                if lhs.element.trackNumber != rhs.element.trackNumber {
                    return lhs.element.trackNumber < rhs.element.trackNumber
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
