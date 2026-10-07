import Foundation
import Observation

/// 歌詞特效的狀態層（母計劃 §2.7／§2.8；A1 計劃 §3.4）。**A1 不含任何 View**：畫面在 A2 接上。
///
/// 世代守衛：`identity`＝(persistentID, revision)。換曲或歌詞指紋變了 revision +1；未播放時 identity 清空，
/// 之後同一首回來也是新的 revision——C 段的非同步結果套用前以 `isCurrent` 比對，舊回應不得蓋掉新詞（Codex R1-4／R2）
@MainActor
@Observable
final class LyricsFXViewModel {
    struct TimelineIdentity: Equatable, Sendable {
        let persistentID: String
        let revision: Int
    }

    private(set) var identity: TimelineIdentity?
    /// 與 Cover Flow／Editor 同源判定（標記取自 `isMarkedNoLyrics`）。升起 ≠ 有詞（母計劃 §2.1 R1-7①）
    private(set) var status: LyricsStatus = .unknown
    private(set) var timeline: LyricsTimeline?
    private(set) var genreStyle: GenreStyle?
    /// 沒有曲目時顯示的既有英文狀態字（E-05）；有曲目時 nil
    private(set) var statusText: String?
    private(set) var isVisible = false

    let positionClock: PlaybackPositionClock
    /// 這次播放的組合配方（B1 計劃 §3.7）：換曲或停播後再播才重抽，一次播放內固定
    private(set) var recipe: SessionRecipe = .mono

    /// 預覽場景強制「減少動態效果」（XCUITest 改不了系統設定）；只有 UI 測試組裝會設成 true
    @ObservationIgnored var forcesReducedMotion = false

    /// 「已標記無詞」的唯讀判斷式，由 AppModel 接到 `lyricsFlow`（與 Editor 同一份標記，D8）
    @ObservationIgnored var isMarkedNoLyrics: (String) -> Bool = { _ in false }

    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var fingerprint: LyricsFingerprint?
    /// 當前曲的歌詞（只在記憶體，不記日誌）：標記改變時重判狀態用
    @ObservationIgnored private var lyrics: String?
    @ObservationIgnored private var metadata: TrackMetadata = .unknown

    /// 預覽場景可換成固定 nonce（`AppModel+LyricsFlowUITest`）
    @ObservationIgnored var nonceSource: any FXNonceSource
    #if DEBUG
    /// 預覽場景直接指定配方（效能量測用最重的組合）；只在得到 profile 時套用
    @ObservationIgnored var recipeOverride: ((SongProfile) -> ComposedRecipe?)?
    #endif
    /// session 身分＝`track.signature`（空 persistentID 時退回三元組，不會全體撞種子；Codex 辯論 J4″）
    @ObservationIgnored private var sessionSignature: String?
    @ObservationIgnored private var sessionArtist = ""
    @ObservationIgnored private var sessionNonce: UInt64 = 0
    /// recipe 已定格（得到 profile 或確定是 mono）：之後同一 session 內不再重組
    @ObservationIgnored private var isRecipeSettled = false

    /// 同一首歌上一次的配方：下次每槽排除它（生產＝`StoredRecipeHistory`，由 AppModel 注入）
    @ObservationIgnored private let recipeHistory: any LyricsFXRecipeHistory

    init(
        positionClock: PlaybackPositionClock, nonceSource: any FXNonceSource = SystemNonceSource(),
        recipeHistory: any LyricsFXRecipeHistory = InMemoryRecipeHistory()
    ) {
        self.positionClock = positionClock
        self.nonceSource = nonceSource
        self.recipeHistory = recipeHistory
    }

    func handle(_ event: PlaybackEvent) {
        switch event {
        case .trackChanged(let track, let lyrics, let metadata):
            nowPlaying(track, lyrics: lyrics, metadata: metadata)
        case .lyricsChanged(let persistentID, let lyrics):
            lyricsUpdated(persistentID: persistentID, text: lyrics)
        case .metadataChanged(let persistentID, let metadata):
            metadataUpdated(persistentID: persistentID, metadata: metadata)
        case .notPlaying:
            clear(statusText: StatusText.noTrackPlaying)
        case .permissionDenied:
            clear(statusText: StatusText.accessDenied)
        case .albumChanged:
            break
        }
    }

    /// 本 app 寫入成功（Editor／Batch）或 Music 端同曲改詞。只認當前曲；指紋相同＝同一份詞，不動
    func lyricsUpdated(persistentID: String, text: String) {
        guard identity?.persistentID == persistentID else { return }
        let new = LyricsFingerprint.of(text)
        guard new != fingerprint else { return }
        apply(persistentID: persistentID, lyrics: text)
    }

    /// 同一首的 genre／曲長後來才讀到或被改了（A2 計劃 §3.0）：時間軸與風格隨之重建，revision +1
    func metadataUpdated(persistentID: String, metadata: TrackMetadata) {
        guard let identity, identity.persistentID == persistentID, metadata != self.metadata else { return }
        self.metadata = metadata
        apply(persistentID: persistentID, lyrics: lyrics)
        settleRecipeIfNeeded()
    }

    /// 可見性由 A2 的切換接上；不可見或沒有詞時時鐘不讀 Music
    func setVisible(_ visible: Bool) {
        isVisible = visible
        updateClock()
    }

    /// 「已標記無詞」改了（使用者在 Cover Flow 標記）：不發播放事件，由 AppModel 在升降變更時叫這裡重判。
    /// 詞沒變，revision 不動
    func refreshStatus() {
        guard let identity else { return }
        let new = LyricsStatus.resolve(lyrics: lyrics, isMarked: isMarkedNoLyrics(identity.persistentID))
        guard new != status else { return }
        status = new
        timeline = timeline(for: lyrics)
        updateClock()
    }

    func isCurrent(_ identity: TimelineIdentity) -> Bool {
        self.identity == identity
    }

    // MARK: 內部

    private func nowPlaying(_ track: TrackInfo, lyrics: String?, metadata: TrackMetadata) {
        statusText = nil
        // 「同一首」只有一個定義＝signature 相同（空 persistentID 時退回三元組）：
        // 兩首都沒有 persistentID 時不得把前一首的 genre／曲長併進新曲（simcodex R1 層級評審）
        let isSameTrack = identity != nil && track.signature == sessionSignature
        // 同一首重發（強制重讀）而這次 genre／曲長讀失敗：沿用已知值，正在顯示的歌詞不得消失（codex R3）
        let metadata = isSameTrack ? self.metadata.mergingLatestKnown(with: metadata) : metadata
        let isSameSnapshot = isSameTrack && lyrics.map(LyricsFingerprint.of) == fingerprint && metadata == self.metadata
        self.metadata = metadata
        if !isSameTrack { startSession(track) }
        // trackChanged 帶的是整份快照：同一首（forceRefresh 重發）只有詞或 genre／曲長變了才重建
        guard !isSameSnapshot else { return }
        positionClock.setTrack(track.persistentID.isEmpty ? nil : track.persistentID)
        apply(persistentID: track.persistentID, lyrics: lyrics)
        settleRecipeIfNeeded()
    }

    private func apply(persistentID: String, lyrics: String?) {
        revision += 1
        identity = TimelineIdentity(persistentID: persistentID, revision: revision)
        fingerprint = lyrics.map(LyricsFingerprint.of)
        self.lyrics = lyrics
        status = LyricsStatus.resolve(lyrics: lyrics, isMarked: isMarkedNoLyrics(persistentID))
        timeline = timeline(for: lyrics)
        genreStyle = GenreStyleResolver.resolve(genre: metadata.genre, lyrics: lyrics)
        updateClock()
    }

    /// 只有確實有詞（`.present`）才建；`.present` 蘊含 lyrics 非 nil
    private func timeline(for lyrics: String?) -> LyricsTimeline? {
        guard status == .present, let lyrics else { return nil }
        return LyricsTimelineBuilder.build(lyrics: lyrics, duration: metadata.duration ?? 0)
    }

    private func clear(statusText text: String) {
        identity = nil
        fingerprint = nil
        lyrics = nil
        metadata = .unknown
        status = .unknown
        timeline = nil
        genreStyle = nil
        statusText = text
        sessionSignature = nil
        recipe = .mono
        positionClock.setTrack(nil)
        updateClock()
    }

    /// 新 session：抽 nonce、recipe 回 mono 等定格（B1 計劃 §3.7）
    private func startSession(_ track: TrackInfo) {
        sessionSignature = track.signature
        sessionArtist = track.artist
        sessionNonce = nonceSource.next()
        isRecipeSettled = false
        recipe = .mono
    }

    /// 第一次得到可用的目標值時組一次並定格；genre 還沒讀到（pending）就先維持 mono 等下次
    private func settleRecipeIfNeeded() {
        guard !isRecipeSettled, let signature = sessionSignature else { return }
        switch SongProfileResolver.resolve(artist: sessionArtist, genre: metadata.genre) {
        case .pending:
            return
        case .mono:
            recipe = .mono
        case .profile(let profile):
            #if DEBUG
            if let forced = recipeOverride?(profile) {
                recipe = .composed(forced)
                break
            }
            #endif
            recipe = Composer.compose(
                profile: profile, seed: FXHash.fnv1a64(signature) ^ sessionNonce ^ Self.recipeSchemaVersion,
                avoiding: recipeHistory.lastPicks(forTrack: signature)?.asPrevious
            )
        }
        if case .composed(let composed) = recipe { recipeHistory.record(RecipePicks(composed), forTrack: signature) }
        isRecipeSettled = true
    }

    /// 目錄或抽樣規則改版時加 1：同 nonce 也抽出不同配方
    static let recipeSchemaVersion: UInt64 = 3

    private func updateClock() {
        positionClock.setActive(isVisible && status == .present)
    }
}
