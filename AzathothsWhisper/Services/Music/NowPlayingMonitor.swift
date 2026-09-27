import Foundation
import OSLog

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

/// 讀取的理由（計劃 2026-09-27-coverflow-f1-f2 §3.2）。busy 邊界上的去留各不相同，所以分開記
enum ReadReason: String, Sendable, Hashable {
    /// 3 秒輪詢：busy 期間丟棄、不補（B-02）
    case poll
    /// Music 的換歌通知：busy 期間記下，全部來源空閒時補一次
    case playerSignal
    /// 使用者點卡／寫入後補讀：busy 期間記下；該次讀取重發當前曲
    case forceRefresh
}

/// 日誌只記序號、理由、布林與耗時，不記曲名與 ID（CLAUDE.md 日誌脫敏）
private let monitorLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "monitor")

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
    /// 單飛：至多一個讀取進行中（輪詢與通知共用；actor 重入下兩個讀取交錯會讓後完成者覆寫 lastSignature）
    private var isReading = false
    /// 讀取進行中又來的理由：完成後再讀一次（多次合併成一次）
    private var followUp: Set<ReadReason> = []
    /// busy 期間記下的理由（不含 `.poll`）：不得吞掉，全部來源空閒時補讀一次
    private var deferred: Set<ReadReason> = []
    private var isStopped = false
    private var readSerial = 0
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
    func setBusy(_ busy: Bool, source: BusySource) async {
        if busy {
            busySources.insert(source)
        } else {
            busySources.remove(source)
            // Editor 寫入成功後要求的補讀發生在它解除 busy 之前（計劃 §6 `writeSucceeded`）；
            // busy 期間的換歌通知同樣在此補（F1）。多個理由只讀一次
            if busySources.isEmpty, !deferred.isEmpty {
                let reasons = deferred
                deferred = []
                await beginRead(reasons: reasons)
            }
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
        isStopped = true
        pollTask?.cancel()
        pollTask = nil
        continuation.finish()
    }

    /// 單次輪詢；測試可直接驅動而不經過時鐘。讀取進行中時合併成一次補讀、立即返回
    func tick() async {
        await request(.poll)
    }

    /// Music 廣播了換歌／播放狀態變化（F1）：立刻讀，不等下一次輪詢
    func playerDidChange() async {
        await request(.playerSignal)
    }

    /// 使用者手動點擊「Now Editing」卡片時強制重新讀取（py:745）；寫入成功後的補讀也走這裡。
    /// busy 期間不讀 Music（B-02），記下來待全部來源空閒時補做
    func forceRefresh() async {
        await request(.forceRefresh)
    }

    private func request(_ reason: ReadReason) async {
        guard !isStopped else { return }
        guard busySources.isEmpty else {
            if reason != .poll { deferred.insert(reason) }
            return
        }
        guard !isReading else {
            followUp.insert(reason)
            return
        }
        await beginRead(reasons: [reason])
    }

    /// 讀取的唯一入口：讀完若期間又來了理由就再讀一次；變 busy 就停，未完成的理由（輪詢除外）延到空閒時
    private func beginRead(reasons initial: Set<ReadReason>) async {
        guard !isStopped, !isReading else {
            followUp.formUnion(initial)
            return
        }
        isReading = true
        var reasons = initial
        while true {
            await readOnce(reasons: reasons)
            guard !followUp.isEmpty else { break }
            reasons = followUp
            followUp = []
            guard busySources.isEmpty, !isStopped else {
                deferred.formUnion(reasons.subtracting([.poll]))
                break
            }
        }
        isReading = false
    }

    private func readOnce(reasons: Set<ReadReason>) async {
        if reasons.contains(.forceRefresh) {
            // 在這次讀取開始時才清：進行中的那次讀完會寫回同一首，提早清會被它蓋掉
            lastSignature = nil
            lastWasNotPlaying = false
        }
        readSerial += 1
        let serial = readSerial
        let before = lastSignature
        let started = ContinuousClock.now
        await read()
        let elapsed = ContinuousClock.now - started
        let milliseconds = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let reasonText = reasons.map(\.rawValue).sorted().joined(separator: "+")
        monitorLog.debug(
            "read \(serial, privacy: .public) \(reasonText, privacy: .public) changed=\(before != self.lastSignature, privacy: .public) \(milliseconds, privacy: .public)ms"
        )
    }

    private func read() async {
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
}

extension PollClock {
    /// 「等一段時間、沒被取消才執行」的唯一實作：LyricsFlow 的升回與 Batch 成功後切回 Editor 分頁共用。
    /// 呼叫端持有回傳的 task，以 `cancel()` 放棄；sleep 被取消而丟錯、或醒來時已取消，都不執行 `action`
    @MainActor
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                try await sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
