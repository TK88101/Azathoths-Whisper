import AppKit
import Foundation
import OSLog

/// Cover Flow 的狀態機（ACCEPTANCE H 段）。**純展示——不含任何播控**（決策 6）。
///
/// 併發守衛只有兩個（草案原列三個）：
/// - `albumGeneration`：清單回寫前校驗，擋過期載入
/// - `centerTrackID`：自動居中的目標身分（用 persistentID 而非索引，重建後仍有效）
///
/// per-item artworkToken 移到 P2：P1 無預取，圖片由 View 的 `.task` 按需取、
/// SwiftUI 在 view 消失時自動取消，沒有 VM 層的回寫路徑可被污染。
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

    // MARK: - 導航

    /// H-01：資料為空才載入（對齊 Batch 的 C-01）
    func tabActivated() {
        isTabActive = true
        guard items.isEmpty else { return }
        // 有 pending key 就用它（不可見期間切過專輯）；否則讀當前曲
        startLoad(albumKey: pendingAlbumKey)
    }

    func tabDeactivated() {
        isTabActive = false
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
        centerID = id
        userHasOverriddenAutoCenter = true
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
        if let playingTrackID {
            centerIfAllowed(on: playingTrackID)
        }
    }

    /// `albumKey` 格式為 `artist\u{1}album`（`TrackInfo.albumKey`）
    private static func parse(albumKey: String) -> (artist: String, album: String)? {
        let parts = albumKey.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    // MARK: - 居中

    private func centerIfAllowed(on persistentID: String) {
        guard !userHasOverriddenAutoCenter else { return }
        guard items.contains(where: { $0.persistentID == persistentID }) else { return }
        isCenteringProgrammatically = true
        centerID = persistentID
        isCenteringProgrammatically = false
    }
}
