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

    /// 預覽場景強制「減少動態效果」（XCUITest 改不了系統設定）；只有 UI 測試組裝會設成 true
    @ObservationIgnored var forcesReducedMotion = false

    /// 「已標記無詞」的唯讀判斷式，由 AppModel 接到 `lyricsFlow`（與 Editor 同一份標記，D8）
    @ObservationIgnored var isMarkedNoLyrics: (String) -> Bool = { _ in false }

    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var fingerprint: LyricsFingerprint?
    /// 當前曲的歌詞（只在記憶體，不記日誌）：標記改變時重判狀態用
    @ObservationIgnored private var lyrics: String?
    @ObservationIgnored private var metadata: TrackMetadata = .unknown

    init(positionClock: PlaybackPositionClock) {
        self.positionClock = positionClock
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
        let isSameTrack = identity?.persistentID == track.persistentID
        // 同一首重發（強制重讀）而這次 genre／曲長讀失敗：沿用已知值，正在顯示的歌詞不得消失（codex R3）
        let metadata = isSameTrack ? self.metadata.mergingLatestKnown(with: metadata) : metadata
        let isSameSnapshot = isSameTrack && lyrics.map(LyricsFingerprint.of) == fingerprint && metadata == self.metadata
        self.metadata = metadata
        // trackChanged 帶的是整份快照：同一首（forceRefresh 重發）只有詞或 genre／曲長變了才重建
        guard !isSameSnapshot else { return }
        positionClock.setTrack(track.persistentID.isEmpty ? nil : track.persistentID)
        apply(persistentID: track.persistentID, lyrics: lyrics)
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
        positionClock.setTrack(nil)
        updateClock()
    }

    private func updateClock() {
        positionClock.setActive(isVisible && status == .present)
    }
}
