import Foundation
import OSLog

/// 未選中曲目時的預覽 meta 佔位（py:234）
private let emptyPreviewMeta = "--"

// Batch 的全部狀態機（py:554-740 的 JS 邏輯 + py:2218-2255 的 js_api）。
//
// 併發紀律（2026-08-14 複核修正，見 ACCEPTANCE C-18 與 M6 分解 §1.1）：
//   原 Plan §4.10 稱「批處理期間 isBusy 按鈕全禁＋輪詢停」為主防線——**該前提不成立**。
//   原版只有 runAlbumBatch 調 toggleBusy（py:621/639）；Fetch Missing／Import All 只禁自己的
//   按鈕，Import Selected 完全不禁，三者期間輪詢照跑。因此「抓詞中切專輯 → 輪詢觸發重載 →
//   舊循環往已被替換的陣列寫入」是真實競態，sessionID 守衛是唯一防線，不是縱深。
//   本類的作法：可觀察行為（按鈕禁用範圍、輪詢是否停）1:1 照搬，競態全部由 sessionID 擋。
@MainActor
@Observable
final class BatchViewModel {
    /// 列表區的四態（py:624 佔位／py:629,636 紅字／正常渲染）
    ///
    /// **`.failed` 是有意保留的不可達分支，勿當死碼清理**（2026-08-23 裁定，Codex 複審勝方＝保留）：
    /// ACCEPTANCE C-26 明文要求「保留於 UI 但無生產觸發點」——py:1180-1182 的 except 吞掉全部
    /// 異常回 []，故原版兩個紅字分支實際到不了，Swift 照搬此語義。這是**規格要求**的不可達碼，
    /// 不是漏清理。要刪必須先修訂並重新簽署 C-26（同步 `StatusText.failedToLoadTracks`／`batchFailed`）。
    enum ListState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // MARK: 顯示狀態

    private(set) var tracks: [AlbumTrack] = []
    private(set) var listState: ListState = .idle
    private(set) var selectedID: String?
    /// 預覽框內容：UI 唯讀（C-07），但抓詞命中與選中切換會改寫它
    var previewText = ""
    private(set) var previewMeta = emptyPreviewMeta
    private(set) var albumName = StatusText.albumLoadingPlaceholder
    /// Batch 自己的狀態欄；初始 "Ready" 為硬編碼英文，不隨語言變（C-25，py:241）
    private(set) var statusText = StatusText.batchReady
    private(set) var confettiTrigger = 0
    /// 對應原版的 alert()（C-08／C-13／C-22）
    var alertMessage: String?
    /// 對應原版的 confirm()（C-15）
    var isConfirmingImportAll = false

    // MARK: C-18 逐操作禁用範圍（三個旗標刻意分開，勿合併成單一 isBusy）

    /// 載入專輯：全部按鈕禁用＋輪詢停（唯一調 toggleBusy 的路徑）
    private(set) var isLoadingAlbum = false
    /// Fetch Missing：只禁自己的按鈕，輪詢照跑
    private(set) var isFetchingMissing = false
    /// Import All：只禁自己的按鈕，輪詢照跑
    private(set) var isImportingAll = false
    // Import Selected 無對應旗標——原版不禁任何按鈕，可重複點擊（寫入本身冪等）

    private(set) var isTabActive = false

    /// → NowPlayingMonitor.setBusy；只有載入專輯會外溢（C-18）
    var onBusyChange: ((Bool) async -> Void)?
    /// 載入三態文案設在 **Editor** 狀態欄，非 Batch 自己的（C-23，py:623/633/637）
    var onEditorStatus: ((String) -> Void)?
    /// 每筆寫入成功（`setLyrics` 回 true）：（寫入目標, 寫入的文字）→ Cover Flow 徽章（2026-09-25 回報）。
    /// 這是「檔案已寫入」的事實事件，**不受 sessionID 約束**：寫入後專輯切走，檔案裡的詞照樣變了
    var onLyricsWritten: ((String, String) -> Void)?

    private let music: any MusicControlling
    /// D-08：Token 保存後即時生效——AppModel 會重建此服務
    var lyricsService: LyricsService
    /// 每次專輯載入／切換遞增；串行循環每步回寫前校驗（C-19）
    private var sessionID = 0

    /// 本輪作業是否已被專輯切換／新一輪載入作廢（C-19）。
    /// 刻意回傳 Bool 而非直接 return——六個呼叫點的 early-return 語義各自不同
    /// （有的 return、有的 continue），把控制流藏進 helper 會讓循環行為變得不透明。
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    private static let log = Logger(
        subsystem: "com.ibridgezhao.azathothswhisper", category: "batch"
    )

    init(lyricsService: LyricsService, music: any MusicControlling) {
        self.lyricsService = lyricsService
        self.music = music
    }

    // MARK: - 派生

    /// C-29：純空白視為缺詞（判定收攏在 AlbumTrack.hasLyrics）
    var missingTracks: [AlbumTrack] { tracks.filter { !$0.hasLyrics } }

    /// C-04：序號＝**列表索引**+1 補零，與 trackNumber 無關（py:573）
    func rowNumber(at index: Int) -> String {
        String(format: "%02d", index + 1)
    }

    private func isStale(_ session: Int) -> Bool { session != sessionID }

    // MARK: - 導航與事件

    /// C-01：切入 Batch 時，**資料為空**才載入（py:396 判的是 batchData.length，不是「首次」）
    func tabActivated() {
        isTabActive = true
        guard tracks.isEmpty else { return }
        startLoad()
    }

    func tabDeactivated() {
        isTabActive = false
    }

    func handle(_ event: PlaybackEvent) {
        guard case .albumChanged = event else { return }
        // py:489-497：無條件清空列表；只有 Batch 可見才重載。
        // selectedID 與 previewText 刻意不清——原版只動 batchData（py:492），
        // 故切專輯後預覽框仍留著上一張專輯的內容。照搬。
        tracks = []
        sessionID += 1
        albumName = StatusText.albumLoadingPlaceholder
        listState = .idle
        guard isTabActive else { return }
        startLoad()
    }

    private func startLoad() {
        loadTask = Task { [weak self] in
            await self?.loadAlbum()
        }
    }

    // MARK: - 載入專輯（py:620-641）

    func loadAlbum() async {
        await withLoadingAlbum {
            onEditorStatus?(StatusText.processingAlbumBatch)
            listState = .loading

            // C-19：載入本身同樣要守，擋兩種重疊。
            // (a) 切專輯：handle() 已先遞增 sessionID，先發的舊載入回來後不得把已切走的
            //     專輯重新填回列表與 header。
            // (b) 同代重入：tabActivated() 不碰 sessionID，連點分頁會讓兩個載入捕獲同一個
            //     session 值；靠下面成功路徑的遞增，先完成者作廢後完成者，只提交一次。
            let session = sessionID
            let loaded = await fetchAlbumTracks()
            guard !isStale(session) else { return }

            sessionID += 1
            tracks = loaded
            // py:559-561：有資料取首曲 album，無資料為 "No Data / Album"
            albumName = loaded.first.map(\.album) ?? StatusText.noDataAlbum
            listState = .loaded
            onEditorStatus?(StatusText.albumLoaded)
        }
    }

    /// py:1154-1182：原版 get_album_tracks 的 except 吞掉全部異常並回 []，
    /// 使 JS 的 catch 分支（"Failed to load tracks."）實際不可達。照搬此可觀察行為，
    /// 但錯誤不靜默丟棄——落 os_log 供排查。
    private func fetchAlbumTracks() async -> [AlbumTrack] {
        do {
            guard let current = try await music.currentTrack() else { return [] }
            return try await music.albumTracks(artist: current.artist, album: current.album)
        } catch {
            Self.log.error("album load failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// 在飛的 `loadAlbum()` 呼叫數。不變量：`loadsInFlight == 活躍 loadAlbum 呼叫數`。
    ///
    /// 為何不是裸布林（C-18 偏差，2026-08-23 修）：舊實作在每個 `loadAlbum()` 的
    /// `defer` 裡無條件落下 busy，重疊載入時先完成者會提前解除——按鈕提前啟用、輪詢提前恢復。
    /// 切專輯路徑在原版**不可能**發生（輪詢在 isBusy 時跳過 py:508-510，載入期間偵測不到
    /// 專輯變更），故該空窗違反已簽署的 C-18，不是 1:1 保真。
    ///
    /// 不改為「取消舊載入」：tab 連點的重疊載入是原版可觀察行為
    /// （py:396 只判 batchData.length，而該值在 py:626 解析後才賦值），
    /// 取消會讓第二次載入不發 AE 請求，偏離原版（上游 §8.2 駁回項 1 已裁定）。
    private var loadsInFlight = 0

    private func setLoadingAlbum(_ loading: Bool) async {
        loadsInFlight += loading ? 1 : -1
        assert(loadsInFlight >= 0, "setLoadingAlbum 的 true/false 未配對")
        let busy = loadsInFlight > 0
        guard busy != isLoadingAlbum else { return }
        isLoadingAlbum = busy
        // await 而非 Task{} 跳板：讓「isLoadingAlbum 變更」與「monitor 記帳」嚴格有序
        await onBusyChange?(busy)
    }

    /// 載入 busy 區間的作用域封裝：取代 `defer { setLoadingAlbum(false) }`。
    ///
    /// defer 裡不能 await，而 setLoadingAlbum 已改 async。scope 保留了 defer 的
    /// **全路徑保證**——closure 內任何 return 只離開 closure，cleanup 仍統一執行。
    /// 這對 `loadsInFlight` 的不變量（== 活躍 loadAlbum 呼叫數）是必要的：
    /// 手工散落釋放會讓未來新增的 early return 漏掉減一，busy 永久卡住、輪詢不恢復。
    private func withLoadingAlbum<T>(_ operation: () async throws -> T) async rethrows -> T {
        await setLoadingAlbum(true)
        do {
            let result = try await operation()
            await setLoadingAlbum(false)
            return result
        } catch {
            await setLoadingAlbum(false)
            throw error
        }
    }

    // MARK: - 選中（py:604-613）

    func select(_ id: String) {
        selectedID = id      // py:605：即使隨後找不到該曲也已設值
        guard let track = tracks.first(where: { $0.persistentID == id }) else { return }
        previewText = track.lyrics
        previewMeta = "\(track.artist) - \(track.title)"
    }

    // MARK: - Fetch Missing（py:648-679）

    func fetchMissing() async {
        let missing = missingTracks
        guard !missing.isEmpty else {
            alertMessage = StatusText.noMissingLyrics
            return
        }

        let session = sessionID
        isFetchingMissing = true
        defer { isFetchingMissing = false }

        // py:658：緊接著就被逐條進度覆蓋，原版同樣觀察不到——保留賦值以維持語義完整
        statusText = StatusText.fetchingTracks(missing.count)

        for (index, track) in missing.enumerated() {
            guard !isStale(session) else { return }
            statusText = StatusText.fetchingProgress(
                index + 1, of: missing.count, title: track.title
            )

            // C-20 的可觀測性：隱藏視窗期間 UI 讀不到，靠此日誌證明串行循環仍在推進。
            // 只記序號，不記曲名／歌詞（全局 CLAUDE.md §7：日誌脫敏）
            Self.log.info("fetch progress \(index + 1, privacy: .public)/\(missing.count, privacy: .public)")

            // 決策 5：傳 album，讓 DarkLyrics 直連專輯頁快路徑可用（原版 py:2229 不傳）
            let result = await lyricsService.fetchForBatch(
                artist: track.artist, title: track.title, album: track.album
            )

            guard !isStale(session) else { return }   // C-19：回寫前再校驗
            // C-30：只有 .found 算命中。原版把 "Genius Error: …" 當歌詞填進列表，
            // 再由 Import All 寫進音樂檔——列舉三態天然阻斷該路徑。
            guard case .found(let lyrics) = result else { continue }
            apply(lyrics: lyrics, to: track.persistentID)
        }

        guard !isStale(session) else { return }
        statusText = StatusText.fetchComplete
    }

    /// py:666-670：寫回列表；若命中的正是選中項，同步更新預覽
    private func apply(lyrics: String, to persistentID: String) {
        guard let index = tracks.firstIndex(where: { $0.persistentID == persistentID }) else { return }
        tracks[index] = tracks[index].withLyrics(lyrics)
        if selectedID == persistentID {
            previewText = lyrics
        }
    }

    // MARK: - Import Selected（py:682-709）

    func importSelected() async {
        guard let selectedID else {
            alertMessage = StatusText.selectTrackFirst
            return
        }
        guard let track = tracks.first(where: { $0.persistentID == selectedID }) else { return }

        let session = sessionID
        statusText = StatusText.savingTrack(track.title)
        let content = previewText      // py:695：寫入的是預覽框當前文本

        do {
            let didWrite = try await music.setLyrics(persistentID: selectedID, lyrics: content)
            if didWrite {
                onLyricsWritten?(selectedID, content)      // 先於 stale 守衛（見 onLyricsWritten）
            }
            guard !isStale(session) else { return }
            if didWrite {
                apply(lyrics: content, to: selectedID)
                statusText = StatusText.batchSaved       // C-28：帶句點，與 Editor 不同
                confettiTrigger += 1
            } else {
                statusText = StatusText.batchSaveFailed
            }
        } catch {
            guard !isStale(session) else { return }
            Self.log.error("import selected failed: \(String(describing: error), privacy: .public)")
            statusText = StatusText.batchErrorSaving
        }
    }

    // MARK: - Import All（py:712-739）

    func requestImportAll() {
        isConfirmingImportAll = true
    }

    func cancelImportAll() {
        isConfirmingImportAll = false
    }

    /// 注意順序：原版 confirm 在 filter 之前，故「全部缺詞」也要先確認才看到提示（C-22）
    func confirmImportAll() async {
        isConfirmingImportAll = false

        let toSave = tracks.filter(\.hasLyrics)
        guard !toSave.isEmpty else {
            alertMessage = StatusText.noTracksHaveLyrics
            return
        }

        let session = sessionID
        isImportingAll = true
        defer { isImportingAll = false }

        statusText = StatusText.savingTracks(toSave.count)   // py:724，同樣即被覆蓋

        for (index, track) in toSave.enumerated() {
            guard !isStale(session) else { return }
            statusText = StatusText.savingProgress(
                index + 1, of: toSave.count, title: track.title
            )
            do {
                let didWrite = try await music.setLyrics(
                    persistentID: track.persistentID, lyrics: track.lyrics
                )
                // 先於下一輪的 stale 守衛（見 onLyricsWritten）；false 照原版不中斷、不改文案（計劃 N4）
                if didWrite {
                    onLyricsWritten?(track.persistentID, track.lyrics)
                }
            } catch {
                // py:729-734：單曲失敗只記錄，不中斷整批
                Self.log.error("import all: \(track.persistentID, privacy: .public) failed")
            }
        }

        guard !isStale(session) else { return }
        statusText = StatusText.allSaved
        confettiTrigger += 1
    }
}
