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
    /// 從未被前端使用——屬原版內部不一致。此處採 trim 語義並記為已批准偏差。
    var hasLyrics: Bool { !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 抓詞命中／寫入成功後產生新值（不就地改動）
    func withLyrics(_ newLyrics: String) -> AlbumTrack {
        AlbumTrack(
            persistentID: persistentID, artist: artist, title: title, album: album,
            discNumber: discNumber, trackNumber: trackNumber, lyrics: newLyrics
        )
    }
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

protocol MusicControlling: Sendable {
    func playerState() async throws -> PlayerState
    func currentTrack() async throws -> TrackInfo?
    func currentLyrics() async throws -> String
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
