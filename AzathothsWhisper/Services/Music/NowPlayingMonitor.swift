import Foundation

// 3 秒輪詢當前曲目並發布事件（py:508-517 的 pollTrack 等價，Plan §4.4）。
// 差異（已批准的安全修正）：曲目身分用 persistentID，專輯鍵用 (artist, album)。

enum PlaybackEvent: Equatable, Sendable {
    /// `existingLyrics` 為 nil＝歌詞讀取失敗（unknown），與空字串（缺詞）不同（計劃 D9）
    case trackChanged(TrackInfo, existingLyrics: String?)
    case albumChanged(String)          // albumKey
    case notPlaying
    case permissionDenied
}

/// 忙碌來源。輪詢只在**全部**來源都空閒時才跑。
///
/// 顯式聲明 `Hashable` 是防禦性的：無 associated value 的 enum 本就自動合成它，
/// 但日後若有人給某個 case 加上 payload，合成會**靜默消失**、`Set<BusySource>` 才報錯。
/// 寫出來能讓那一刻的意圖清楚。
enum BusySource: Sendable, Hashable {
    case editor
    case batch
}

/// 可注入的時鐘，讓輪詢測試零真實延時
protocol PollClock: Sendable {
    func sleep(for interval: Duration) async throws
}

struct SystemPollClock: PollClock {
    func sleep(for interval: Duration) async throws {
        try await Task.sleep(for: interval)
    }
}

actor NowPlayingMonitor {
    static let interval: Duration = .seconds(3)   // py:769 setInterval(pollTrack, 3000)

    private let music: any MusicControlling
    private let clock: any PollClock
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    // AsyncStream 本身 Sendable，訂閱端不需進 actor
    nonisolated let events: AsyncStream<PlaybackEvent>

    private var lastSignature: String?
    private var lastAlbumKey: String?
    private var lastWasNotPlaying = false
    private var busySources: Set<BusySource> = []
    private var pollTask: Task<Void, Never>?

    init(music: any MusicControlling, clock: any PollClock = SystemPollClock()) {
        self.music = music
        self.clock = clock
        let (stream, continuation) = AsyncStream<PlaybackEvent>.makeStream()
        self.events = stream
        self.continuation = continuation
    }

    /// py:508-510：批處理/抓詞期間跳過輪詢，避免打斷使用者操作。
    ///
    /// **必須帶 source**（2026-08-23 修）：Editor 與 Batch 是兩個獨立的忙碌來源，
    /// 舊簽名讓兩者各自以裸布林覆寫同一個旗標——一方送 false 會清掉另一方仍需維持的 busy。
    /// 實測可達：Editor 抓詞中切到 Batch（原版 toggleBusy 不禁 tab 導航，py:407）→
    /// Batch 載入完成送 false → Editor 仍在抓詞但輪詢已恢復。
    /// 由本型別自己記錄「誰還忙著」，而非讓組裝根替它記帳；新增來源（如 M7 Cover Flow）
    /// 只需擴 `BusySource`，不必動 `AppModel`。
    func setBusy(_ busy: Bool, source: BusySource) {
        if busy {
            busySources.insert(source)
        } else {
            busySources.remove(source)
        }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                guard let self else { return }
                do {
                    try await self.clock.sleep(for: Self.interval)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        continuation.finish()
    }

    /// 單次輪詢；測試可直接驅動而不經過時鐘
    func tick() async {
        guard busySources.isEmpty else { return }

        do {
            // D9：曲目＋歌詞一次讀完（同一個釘住的 specifier），不再分兩次各自解析 current track
            guard let read = try await music.nowPlaying() else {
                if !lastWasNotPlaying {
                    lastWasNotPlaying = true
                    lastSignature = nil
                    continuation.yield(.notPlaying)
                }
                return
            }
            lastWasNotPlaying = false
            let track = read.track

            if track.albumKey != lastAlbumKey {
                lastAlbumKey = track.albumKey
                continuation.yield(.albumChanged(track.albumKey))
            }

            guard track.signature != lastSignature else { return }
            lastSignature = track.signature
            continuation.yield(.trackChanged(track, existingLyrics: read.lyrics))
        } catch MusicError.permissionDenied {
            continuation.yield(.permissionDenied)
        } catch {
            // 其餘失敗（Music 未啟動、AE 暫時性錯誤）安靜跳過本輪，下一輪重試——對齊原版行為
        }
    }

    /// 使用者手動點擊「Now Editing」卡片時強制重新讀取（py:745）
    func forceRefresh() async {
        lastSignature = nil
        lastWasNotPlaying = false
        await tick()
    }
}
