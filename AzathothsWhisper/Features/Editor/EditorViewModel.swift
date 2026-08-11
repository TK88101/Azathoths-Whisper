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
    var onBusyChange: ((Bool) -> Void)?
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

    private func apply(track: TrackInfo, existingLyrics: String) {
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

    // MARK: - 動作

    func fetch() async {
        fetchSeq += 1
        let mySeq = fetchSeq
        let myGeneration = generation
        let myTrackID = boundTrackID

        setBusy(true)
        statusText = StatusText.fetchingFromGenius

        let outcome = await resolveAndFetch()

        // 已被更新一輪的抓詞取代：狀態交給對方，本輪靜默退出
        guard mySeq == fetchSeq else { return }
        setBusy(false)

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
        setBusy(true)
        statusText = StatusText.savingToMusic
        defer { setBusy(false) }

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

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        onBusyChange?(busy)
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
