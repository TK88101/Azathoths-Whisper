#if os(macOS)
import Foundation
import iTunesLibrary

/// 唯一碰 ITLibrary 的地方（sprint-3-detail.md §4.5；echo_gate E7：只許本檔 import、只用白名單成員）。
/// 所有 ITLibrary 呼叫都在自己的序列執行器上，不佔協作執行緒池；對外只交出值型別。
/// 每次載入包 autoreleasepool：背景序列不會自動排空，實測每次重讀 +45 MB（附錄 B P1-d）。
public actor LibraryReader: CatalogSource {
    private let queue = DispatchSerialQueue(label: "com.ibridgezhao.yse.library-reader")
    private var library: ITLibrary?
    /// 上次載入的曲目，供封面讀取（只在本 actor 內使用）
    private var items: [UInt64: ITLibMediaItem] = [:]

    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    public init() {}

    public func load() throws(CatalogSourceError) -> CatalogLoad {
        let opened = try open()
        var songs: [RawTrack] = []
        var skipped: [SkipReason: Int] = [:]
        var byID: [UInt64: ITLibMediaItem] = [:]
        var others: [OtherAlbumTitle] = []
        autoreleasepool {
            for item in opened.allMediaItems {
                let albumID = item.album.persistentID.uint64Value
                // 非歌曲項目只取專輯名：許可閘門的同名判定要涵蓋（S4 T3）
                guard item.mediaKind == .kindSong else {
                    if albumID != 0 { others.append(OtherAlbumTitle(title: item.album.title ?? "", albumID: albumID)) }
                    continue
                }
                guard albumID != 0 else {
                    skipped[.zeroAlbumID, default: 0] += 1
                    continue
                }
                let trackID = item.persistentID.uint64Value
                byID[trackID] = item
                songs.append(RawTrack(
                    trackID: trackID, albumID: albumID, albumTitle: item.album.title, sortAlbumTitle: item.album.sortTitle,
                    albumArtist: item.album.albumArtist, sortAlbumArtist: item.album.sortAlbumArtist, artist: item.artist?.name,
                    title: item.title, discNumber: Int(item.album.discNumber), trackNumber: Int(item.trackNumber),
                    modifiedAt: item.modifiedDate, hasArtwork: item.hasArtworkAvailable,
                    duration: item.totalTime > 0 ? Double(item.totalTime) / 1000 : nil))
            }
        }
        items = byID
        return CatalogLoad(songs: songs, skipped: skipped, otherAlbumTitles: others)
    }

    public func artworkData(trackID: UInt64) -> Data? {
        autoreleasepool { items[trackID]?.artwork?.imageData }
    }

    /// 第一次建立 ITLibrary，之後重讀。失敗（未授權與讀取失敗同為 NSCocoaErrorDomain 4097，附錄 B P1-c）＝unavailable
    private func open() throws(CatalogSourceError) -> ITLibrary {
        if let library {
            guard library.reloadData() else { throw .unavailable(code: CatalogSourceError.reloadFailedCode) }
            return library
        }
        do {
            let opened = try ITLibrary(apiVersion: "1.0")
            library = opened
            return opened
        } catch {
            throw .unavailable(code: (error as NSError).code)
        }
    }
}
#endif
