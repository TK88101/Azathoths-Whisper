#if os(macOS)
import Foundation

// 曲庫來源的邊界（sprint-3-detail.md §4.5）：protocol＋替身。正式版 `LibraryReader` 是唯一碰 ITLibrary 的地方，
// 對外只交出這裡的值型別，不外洩 ITLib 物件。

public struct RawTrack: Sendable, Equatable {
    public let trackID: UInt64
    /// nil＝沒有專輯；0 也不併入任何專輯（只計入略過統計）
    public let albumID: UInt64?
    public let albumTitle: String?
    public let sortAlbumTitle: String?
    public let albumArtist: String?
    public let sortAlbumArtist: String?
    public let artist: String?
    public let title: String?
    public let discNumber: Int
    public let trackNumber: Int
    public let modifiedAt: Date?
    public let hasArtwork: Bool
    /// 秒（ITLibrary totalTime 毫秒換算）；S4 曲目選擇器與 seek 上限用
    public let duration: Double?

    public init(trackID: UInt64, albumID: UInt64?, albumTitle: String?, sortAlbumTitle: String?, albumArtist: String?,
                sortAlbumArtist: String?, artist: String?, title: String?, discNumber: Int, trackNumber: Int,
                modifiedAt: Date?, hasArtwork: Bool, duration: Double? = nil) {
        self.trackID = trackID
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.sortAlbumTitle = sortAlbumTitle
        self.albumArtist = albumArtist
        self.sortAlbumArtist = sortAlbumArtist
        self.artist = artist
        self.title = title
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.modifiedAt = modifiedAt
        self.hasArtwork = hasArtwork
        self.duration = duration
    }
}

public enum SkipReason: String, Sendable, Hashable, CaseIterable {
    case noAlbum, zeroAlbumID
}

/// 非歌曲項目（影片等）的專輯名：捷徑以名稱查找時也可能撈到，許可閘門的同名判定要涵蓋（S0 ShortcutGate 註解）
public struct OtherAlbumTitle: Sendable, Equatable {
    public let title: String
    public let albumID: UInt64

    public init(title: String, albumID: UInt64) {
        self.title = title
        self.albumID = albumID
    }
}

public struct CatalogLoad: Sendable, Equatable {
    public let songs: [RawTrack]
    public let skipped: [SkipReason: Int]
    public let otherAlbumTitles: [OtherAlbumTitle]

    public init(songs: [RawTrack], skipped: [SkipReason: Int], otherAlbumTitles: [OtherAlbumTitle] = []) {
        self.songs = songs
        self.skipped = skipped
        self.otherAlbumTitles = otherAlbumTitles
    }
}

public enum CatalogSourceError: Error, Equatable, Sendable {
    /// 未授權或讀取失敗（ITLibrary 兩者同為 NSCocoaErrorDomain 4097，無法區分；附錄 B P1-c）
    case unavailable(code: Int)

    /// `reloadData()` 回 false 時（ITLibrary 不給 NSError）
    public static let reloadFailedCode = -1
}

public protocol CatalogSource: Sendable {
    /// 只含 kindSong
    func load() async throws(CatalogSourceError) -> CatalogLoad
    /// 代表曲的原圖資料（未編碼前的位元組）；沒有或讀不到回 nil
    func artworkData(trackID: UInt64) async -> Data?
}
#endif
