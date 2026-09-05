import AppKit
import Foundation
import OSLog

/// Cover Flow 的狀態機（ACCEPTANCE H 段）。**純展示——不含任何播控**（決策 6）。
///
/// 併發守衛只有兩個（草案原列三個）：
/// - `albumGeneration`：清單回寫前校驗，擋過期載入
/// - `centerTrackID`：自動居中的目標身分（用 persistentID 而非索引，重建後仍有效）
///
/// per-item artworkToken **P2 判定不需要**：預取的回寫目標是 service 的快取，不是 VM 狀態。
/// VM 唯一的封面相關狀態是 `artworkRevisions`——它只記版本計數、不存圖片內容，
/// 且只接受目前 `items` 內的 ID，故沒有可被過期預取污染的回寫路徑。
@MainActor
@Observable
final class CoverFlowViewModel {
    private(set) var items: [AlbumTrack] = []
    /// 綁給 `CoverFlowStrip` 的 scrollPosition
    var centerID: String?
    private(set) var isTabActive = false

    private let music: any MusicControlling
    private let artworkProvider: any ArtworkProviding

    /// 每次清單重建遞增；載入回寫前校驗
    private var albumGeneration = 0
    /// 目前**播放**的曲目（≠ centerID，後者可能被使用者滑走）
    private var playingTrackID: String?
    /// H-05：使用者拖曳或鍵盤步進後為 true，抑制自動居中
    private var userHasOverriddenAutoCenter = false
    /// 程式化居中期間為 true——SwiftUI 會因程式化捲動回呼 scrollPosition binding，
    /// 若不區分就會把自己的動作誤判為使用者滑動
    private var isCenteringProgrammatically = false

    /// 每個 ID 的封面版本號。取圖失敗時 View 拿到 nil 並顯示佔位；
    /// 之後退避到期重取成功時，provider 會通知，靠它讓該項的 `.task(id:)` 重跑。
    ///
    /// 精確邊界：Observation 是**屬性粒度**，寫這個字典仍會讓所有讀過它的 View body
    /// 重新求值；被真正限縮的是「哪一項的 `.task` 會重跑」（key 只有該項會變）。
    /// 通知本身已由 provider 收窄成「僅從失敗中恢復時才發」，故頻率極低
    private(set) var artworkRevisions: [String: Int] = [:]

    /// 預取命令的世代。過時命令在送達 provider 前自行退出——
    /// 只取消前一個 Task 並不保證它的 closure 不執行，會送出一串過時集合
    private var prefetchGeneration = 0
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    /// 測試用：等預取命令實際送達 provider（與 `loadTask` 同一慣例）
    @ObservationIgnored var prefetchTaskForTesting: Task<Void, Never>? { prefetchTask }

    /// 不可見時收到的專輯變更：記住 key，等切回 tab 才載入。
    /// 若在此期間直接載入，既違反 H-01 懶載入，也會往共用的串行 AE 佇列塞查詢、
    /// 拖慢 monitor 與 Editor（對齊 Batch 的 C-17）
    private var pendingAlbumKey: String?

    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    private static let log = Logger(
        subsystem: "com.ibridgezhao.azathothswhisper", category: "coverflow"
    )

    init(music: any MusicControlling, artwork: any ArtworkProviding) {
        self.music = music
        self.artworkProvider = artwork
    }

    /// 由組裝根接上取圖完成通知。
    ///
    /// 吃**協議**而非具體型別：收窄成 `ArtworkService` 會讓測試替身無法傳入，
    /// 這條 actor→MainActor 的橋接就再也沒有測試能跑到
    func observeArtworkStores(from provider: any ArtworkProviding) {
        Task { [weak self] in
            await provider.setOnStored { [weak self] id in
                // `[weak self]` **不會**自動傳進巢狀 closure：內層若直接用外層解出的
                // optional，捕獲的是它的強副本，存進 provider 的 handler 就永久持有整個 VM
                Task { @MainActor in self?.artworkDidStore(id) }
            }
        }
    }

    /// provider 回報某項從失敗中恢復。**「是否為恢復」由 provider 判定**——
    /// 它的退避表本就記著誰失敗過，VM 再建一份「誰在顯示佔位」的鏡像狀態
    /// 只會多出需要人工同步的第二份真相
    func artworkDidStore(_ persistentID: String) {
        // 舊專輯的殘留通知不得寫進字典，否則長時間切歌會讓它無界增長
        guard items.contains(where: { $0.persistentID == persistentID }) else { return }
        artworkRevisions[persistentID, default: 0] += 1
    }

    /// View 的 `.task(id:)` key。版本變更即重讀（命中記憶體，成本是一次字典查找）
    func artworkRevision(for persistentID: String) -> Int {
        artworkRevisions[persistentID] ?? 0
    }

    // MARK: - 導航

    /// H-01：資料為空才載入（對齊 Batch 的 C-01）
    func tabActivated() {
        isTabActive = true
        guard items.isEmpty else {
            schedulePrefetch()          // 已有資料：回到此 tab 就重排中心兩側
            return
        }
        // 有 pending key 就用它（不可見期間切過專輯）；否則讀當前曲
        startLoad(albumKey: pendingAlbumKey)
    }

    func tabDeactivated() {
        isTabActive = false
        cancelPrefetch()                // 看不見的 tab 不該佔用 AE
    }

    // MARK: - 事件

    func handle(_ event: PlaybackEvent) async {
        switch event {
        case .albumChanged(let albumKey):
            // H-06：切專輯重建。**明確重置抑制**——新專輯應回到目前播放曲
            userHasOverriddenAutoCenter = false
            items = []
            centerID = nil
            playingTrackID = nil
            artworkRevisions = [:]
            cancelPrefetch()            // H-06：切專輯取消舊批次
            // C-17 同構：無條件清空，但**只有可見時才重載**
            guard isTabActive else {
                pendingAlbumKey = albumKey
                return
            }
            startLoad(albumKey: albumKey)

        case .trackChanged(let info, _):
            // H-05 的解除條件＝**真實切歌**（persistentID 變更）。
            // forceRefresh() 會對同一曲重發此事件，那不算。
            let isRealChange = info.persistentID != playingTrackID
            playingTrackID = info.persistentID
            if isRealChange {
                userHasOverriddenAutoCenter = false
            }
            centerIfAllowed(on: info.persistentID)

        case .notPlaying, .permissionDenied:
            break
        }
    }

    // MARK: - 使用者互動

    /// 使用者拖曳造成的中心變更（View 層在確認非程式化捲動後呼叫）
    func userDidScroll(to id: String) {
        let previous = centerID
        centerID = id
        userHasOverriddenAutoCenter = true
        schedulePrefetch(movingFrom: previous)
    }

    /// scrollPosition binding 的回呼。程式化居中期間不得被當成使用者滑動
    func scrollPositionDidChange(to id: String?) {
        guard !isCenteringProgrammatically, let id, id != centerID else { return }
        userDidScroll(to: id)
    }

    /// H-09：鍵盤步進。與拖曳同樣算「使用者接管」
    func stepCenter(by offset: Int) {
        guard let centerID,
              let index = items.firstIndex(where: { $0.persistentID == centerID })
        else { return }
        let target = min(max(index + offset, 0), items.count - 1)
        guard target != index else { return }
        userDidScroll(to: items[target].persistentID)
    }

    // MARK: - 封面

    func artwork(for persistentID: String) async -> NSImage? {
        await artworkProvider.artwork(for: persistentID)
    }

    // MARK: - 載入

    private func startLoad(albumKey: String?) {
        albumGeneration += 1
        let generation = albumGeneration
        loadTask = Task { [weak self] in
            await self?.load(albumKey: albumKey, generation: generation)
        }
    }

    /// `albumKey` 為 nil＝首次載入，此時才讀 currentTrack()。
    /// **切專輯路徑一律用事件攜帶的 key**：事件發布後再讀 currentTrack()，
    /// 使用者若已快速切歌，拿到的會是**下一張**專輯。
    private func load(albumKey: String?, generation: Int) async {
        let query: (artist: String, album: String)?
        if let albumKey {
            query = Self.parse(albumKey: albumKey)
        } else {
            let current = try? await music.currentTrack()
            query = current.map { ($0.artist, $0.album) }
        }
        guard let query else { return }

        let loaded: [AlbumTrack]
        do {
            loaded = try await music.albumTracks(artist: query.artist, album: query.album)
        } catch {
            Self.log.error("album load failed: \(String(describing: error), privacy: .public)")
            return
        }

        guard generation == albumGeneration else { return }   // 過期載入不回寫
        pendingAlbumKey = nil
        items = loaded.sortedForDisplay()                     // H-11
        // H-06：重建後預取中心兩側。`centerIfAllowed` 成功時自己就會排程，
        // 這裡只補它沒排到的情況（無播放曲、曲目不在本專輯、使用者已接管）
        if let playingTrackID, centerIfAllowed(on: playingTrackID) {
            return
        }
        schedulePrefetch()
    }

    /// `albumKey` 格式為 `artist\u{1}album`（`TrackInfo.albumKey`）
    private static func parse(albumKey: String) -> (artist: String, album: String)? {
        let parts = albumKey.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    // MARK: - 居中

    /// - Returns: 是否真的居中了（連帶已排好預取）
    @discardableResult
    private func centerIfAllowed(on persistentID: String) -> Bool {
        guard !userHasOverriddenAutoCenter else { return false }
        guard items.contains(where: { $0.persistentID == persistentID }) else { return false }
        let previous = centerID
        isCenteringProgrammatically = true
        centerID = persistentID
        isCenteringProgrammatically = false
        schedulePrefetch(movingFrom: previous)
        return true
    }

    // MARK: - 預取

    /// 以中心兩側的 window 取代目前的預取集合。`movingFrom` 決定哪一側先取
    private func schedulePrefetch(movingFrom previous: String? = nil) {
        guard isTabActive, let centerID,
              let centerIndex = items.firstIndex(where: { $0.persistentID == centerID })
        else { return }

        let previousIndex = previous.flatMap { id in
            items.firstIndex(where: { $0.persistentID == id })
        }
        let direction = previousIndex.map { centerIndex >= $0 ? 1 : -1 } ?? 1
        dispatchPrefetch(
            CoverFlowPrefetchWindow.ids(
                items: items, centerIndex: centerIndex, direction: direction
            )
        )
    }

    private func cancelPrefetch() {
        dispatchPrefetch([])
    }

    /// 串鏈 ＋ 世代門：串鏈保證送達順序，世代門讓過時命令在呼叫 provider 前退出。
    /// 只做前者會送出一長串過時集合，只做後者則無法保證先後
    private func dispatchPrefetch(_ ids: [String]) {
        prefetchGeneration += 1
        let generation = prefetchGeneration
        let previous = prefetchTask
        let provider = artworkProvider
        prefetchTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, generation == self.prefetchGeneration else { return }
            await provider.prefetch(ids)
        }
    }
}
