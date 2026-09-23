import Foundation

// Editor 的全部狀態機（py:419-552 的 JS 邏輯 + py:2082-2128 的 js_api）。
// 兩處已批准的安全修正（Plan §4.10）：
//   B-13 Save 寫入畫面綁定的 persistentID，而非「當前播放曲」；
//   B-14 Fetch 期間切歌 → 結果不套用（世代守衛）。
@MainActor
@Observable
final class EditorViewModel {
    // 顯示狀態
    private(set) var artistLine = StatusText.noArtist
    private(set) var titleLine = StatusText.noTrack
    private(set) var isAccessDenied = false
    var lyricsText = ""
    /// nil＝顯示本地化的 status_ready；其餘為硬編碼英文運行時文案（E-05）
    private(set) var statusText: String?
    private(set) var isBusy = false
    private(set) var confettiTrigger = 0
    /// 純裝飾（B-19）：切換不影響任何抓詞路徑
    var dataSource: DataSourceOption = .genius

    /// 目前編輯內容所綁定的曲目（Save 寫入目標）
    private(set) var boundTrackID: String?
    private(set) var boundTrack: TrackInfo?

    /// Editor tab 是否在前景——只有前景時才自動抓詞（B-05）
    var isEditorTabActive = true
    /// 忙碌狀態外溢（→ NowPlayingMonitor.setBusy，B-02）
    var onBusyChange: ((Bool) async -> Void)?
    /// 卡片點擊＝強制重讀（B-06）
    var onRequestHydrate: (() -> Void)?

    var lyricsService: LyricsService
    private let music: any MusicControlling
    private let clock: any PollClock

    private var lastSignature: String?
    private var generation = 0      // 切歌世代：決定 fetch 結果能否套用
    private var fetchSeq = 0        // 抓詞序號：決定誰擁有 isBusy
    /// 100ms 延後的自動抓詞；測試以 `await autoFetchTask?.value` 等待其收斂
    @ObservationIgnored private(set) var autoFetchTask: Task<Void, Never>?

    init(lyricsService: LyricsService, music: any MusicControlling, clock: any PollClock = SystemPollClock()) {
        self.lyricsService = lyricsService
        self.music = music
        self.clock = clock
    }

    /// py:419-424：空字串＝0 行，其餘＝以 \n 切分的段數
    var lineCount: Int {
        lyricsText.isEmpty ? 0 : lyricsText.components(separatedBy: "\n").count
    }

    // MARK: - 事件

    func handle(_ event: PlaybackEvent) {
        switch event {
        case .trackChanged(let track, let existingLyrics):
            apply(track: track, existingLyrics: existingLyrics)
        case .notPlaying:
            applyNotPlaying()
        case .permissionDenied:
            applyPermissionDenied()
        case .albumChanged:
            break   // Batch / Cover Flow 消費
        }
    }

    private func apply(track: TrackInfo, existingLyrics: String?) {
        isAccessDenied = false
        let lines = TrackLabel.lines(artist: track.artist, title: track.title)
        artistLine = lines.artist
        titleLine = lines.title

        guard track.signature != lastSignature else { return }   // py:459 trackChanged 判定
        lastSignature = track.signature
        boundTrack = track
        boundTrackID = track.persistentID
        generation += 1
        autoFetchTask?.cancel()

        // D8：讀不到歌詞 ≠ 沒有歌詞。不自動抓詞、不宣稱缺詞——否則使用者一按 Write 就覆蓋掉原本的詞
        guard let existingLyrics else {
            lyricsText = ""
            statusText = StatusText.lyricsUnreadable
            return
        }

        if existingLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lyricsText = ""
            guard isEditorTabActive else { return }   // py:481 batch view 可見時不自動抓
            autoFetchTask = Task { [weak self] in
                guard let self else { return }
                try? await self.clock.sleep(for: .milliseconds(100))   // py:483
                guard !Task.isCancelled else { return }
                await self.fetch()
            }
        } else {
            lyricsText = LineEndings.normalized(existingLyrics)
            statusText = StatusText.lyricsLoadedFromMusicApp
        }
    }

    private func applyNotPlaying() {
        artistLine = StatusText.noArtist
        titleLine = StatusText.noTrack
        isAccessDenied = false
        lastSignature = nil
    }

    private func applyPermissionDenied() {
        artistLine = StatusText.accessDenied
        titleLine = StatusText.checkMacOSPermissions
        isAccessDenied = true
        lastSignature = "Error"     // py:452
    }

    func requestHydrate() {
        onRequestHydrate?()
    }

    /// C-23：Batch 載入專輯的三態文案設在 **Editor** 的狀態欄（py:623/633/637 走同一個 setStatus）
    /// 由外部特性注入狀態文案（目前只有 Batch 載入三態，C-23：py:623/633/637）。
    /// 命名刻意與來源無關——狀態欄是 Editor 的展示資源，誰寫入不該編進方法名。
    func setExternalStatus(_ text: String) {
        statusText = text
    }

    // MARK: - 動作

    func fetch() async {
        fetchSeq += 1
        let mySeq = fetchSeq
        let myGeneration = generation
        let myTrackID = boundTrackID

        await setBusy(true)
        statusText = StatusText.fetchingFromGenius

        let outcome = await resolveAndFetch()

        // 已被更新一輪的抓詞取代：狀態交給對方，本輪靜默退出。
        // **刻意不套 withBusy scope**：釋放是有條件的——被取代的舊 fetch 不送 false，
        // 由最後擁有序號的 fetch 釋放，否則兩輪抓詞會提前解除 busy。
        guard mySeq == fetchSeq else { return }
        await setBusy(false)

        // 世代守衛（B-14）：抓詞期間切歌 → 結果不套用到新曲
        guard myGeneration == generation, myTrackID == boundTrackID else { return }

        switch outcome {
        case .found(let lyrics):
            lyricsText = LineEndings.normalized(lyrics)
            statusText = StatusText.lyricsFetched
        case .notFound, .error:
            statusText = StatusText.lyricsNotFound
        case .musicUnavailable:
            statusText = StatusText.fetchFailed
        }
    }

    private enum FetchOutcome {
        case found(String)
        case notFound
        case error
        case musicUnavailable
    }

    private func resolveAndFetch() async -> FetchOutcome {
        let track: TrackInfo?
        if let bound = boundTrack {
            track = bound
        } else {
            do {
                track = try await music.currentTrack()
            } catch {
                return .musicUnavailable
            }
        }
        // py:2090-2091：完全沒有曲目 → "No track playing" → 前端呈現 "Lyrics not found"
        guard let track else { return .notFound }

        switch await lyricsService.fetchForEditor(artist: track.artist, title: track.title, album: track.album) {
        case .found(let lyrics): return .found(lyrics)
        case .notFound: return .notFound
        case .error: return .error
        }
    }

    func save() async {
        await withBusy {
            statusText = StatusText.savingToMusic

            // B-13：寫入畫面綁定的曲目，而非當前播放曲
            guard let persistentID = boundTrackID, !persistentID.isEmpty else {
                statusText = StatusText.noTrackPlaying     // py:2101
                return
            }

            do {
                let didWrite = try await music.setLyrics(persistentID: persistentID, lyrics: lyricsText)
                statusText = didWrite ? StatusText.saved : StatusText.failedToSave
                if didWrite { confettiTrigger += 1 }
            } catch {
                statusText = StatusText.writeFailed        // py:548
            }
        }
    }

    private func setBusy(_ busy: Bool) async {
        isBusy = busy
        // await 而非 Task{} 跳板：讓「isBusy 變更」與「monitor 記帳」嚴格有序。
        // 舊寫法是 fire-and-forget，測試只能靠 settle() 讓步 N 輪賭它送達，
        // 實際存在 polling window（2026-08-23 Round 2 altitude 審查）。
        await onBusyChange?(busy)
    }

    /// busy 區間的作用域封裝：取代 `defer { setBusy(false) }`。
    ///
    /// 為何不用 defer：defer 裡不能 await，而 setBusy 已改為 async。
    /// scope 保留了 defer 的**全路徑保證**——closure 內的任何 return 只離開 closure，
    /// cleanup 仍由此處統一執行；throw 亦然。手工在各退出點散落 setBusy(false) 會讓
    /// 未來新增的 early return 漏掉釋放，後果是 busy 永久卡住、輪詢再也不恢復。
    private func withBusy<T>(_ operation: () async throws -> T) async rethrows -> T {
        await setBusy(true)
        do {
            let result = try await operation()
            await setBusy(false)
            return result
        } catch {
            await setBusy(false)
            throw error
        }
    }
}

// py:154-158 的裝飾性下拉；無任何消費者（附錄 A #1，決策 4 照留）
enum DataSourceOption: String, CaseIterable, Identifiable {
    case genius
    case darklyrics
    case metalarchives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .genius: return "Genius.com"
        case .darklyrics: return "DarkLyrics"
        case .metalarchives: return "MetalArchives"
        }
    }
}
