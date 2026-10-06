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
    /// 與歌詞同一次讀取（母計劃 §2.8 (a)）
    let metadata: TrackMetadata

    init(track: TrackInfo, lyrics: String?, metadata: TrackMetadata = .unknown) {
        self.track = track
        self.lyrics = lyrics
        self.metadata = metadata
    }
}

/// 曲目的 genre 與曲長（歌詞特效用，母計劃 §2.2）。
/// `nil`＝讀不到（未知）；`""`／`0`＝Music 說沒有——兩者不折疊（A1 計劃 §2）
struct TrackMetadata: Equatable, Sendable {
    static let unknown = TrackMetadata(genre: nil, duration: nil)

    let genre: String?
    /// 秒
    let duration: Double?

    /// 非有限的曲長（NaN／∞）在這裡就當成讀不到：換歌事件與補讀事件帶的是同一種正規化後的值
    init(genre: String?, duration: Double?) {
        self.genre = genre
        self.duration = duration.flatMap { $0.isFinite ? $0 : nil }
    }

    /// 同一首的新讀值併入已知值：nil＝讀不到，不覆蓋；非 nil（含 `""`／`0`）一律取新值（A2 計劃 §3.0）
    func mergingLatestKnown(with newer: TrackMetadata) -> TrackMetadata {
        TrackMetadata(genre: newer.genre ?? genre, duration: newer.duration ?? duration)
    }
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
    /// 歌詞特效用（母計劃 §2.2）；nil＝讀不到
    let genre: String?
    let duration: Double?

    init(
        persistentID: String, artist: String, title: String, album: String,
        discNumber: Int, trackNumber: Int, lyrics: String?, genre: String? = nil, duration: Double? = nil
    ) {
        self.persistentID = persistentID
        self.artist = artist
        self.title = title
        self.album = album
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.lyrics = lyrics
        self.genre = genre
        self.duration = duration
    }
}

extension TrackDetails {
    /// 只換歌詞、其餘照舊（唯一定義：Cover Flow 卡片與詳情快取都走這裡，新增欄位不會在某處被默默清掉）
    func replacingLyrics(_ lyrics: String?) -> TrackDetails {
        TrackDetails(
            persistentID: persistentID, artist: artist, title: title, album: album,
            discNumber: discNumber, trackNumber: trackNumber, lyrics: lyrics, genre: genre, duration: duration
        )
    }

    /// 批次讀取的欄位順序（`MusicAppleEventsClient.trackDetails` 依此送 AE）
    enum Column: Int, CaseIterable {
        case persistentID, artist, title, album, discNumber, trackNumber, lyrics, genre, duration
    }

    /// 各欄（依 `Column` 順序）→ 卡片詳情。欄數不對或各欄長度不一致＝批次讀取不完整，整批不採用（卡片退為 unknown）；
    /// 沒有 persistentID 的列略過
    static func fromColumns(_ columns: [[Any]]) -> [TrackDetails] {
        guard columns.count == Column.allCases.count,
              let count = columns.first?.count,
              columns.allSatisfy({ $0.count == count })
        else { return [] }
        return (0..<count).compactMap { row in
            func value(_ column: Column) -> Any { columns[column.rawValue][row] }
            guard let id = value(.persistentID) as? String, !id.isEmpty else { return nil }
            return TrackDetails(
                persistentID: id,
                artist: value(.artist) as? String ?? "",
                title: value(.title) as? String ?? "",
                album: value(.album) as? String ?? "",
                discNumber: (value(.discNumber) as? NSNumber)?.intValue ?? 0,
                trackNumber: (value(.trackNumber) as? NSNumber)?.intValue ?? 0,
                lyrics: value(.lyrics) as? String,
                genre: value(.genre) as? String,
                duration: (value(.duration) as? NSNumber)?.doubleValue
            )
        }
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
    /// 歌詞特效的位置讀數（母計劃 §2.2）：沒在播或讀的途中換了歌＝nil
    func playbackPosition() async throws -> PlaybackPosition?
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
