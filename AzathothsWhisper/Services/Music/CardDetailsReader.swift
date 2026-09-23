import Foundation

/// Cover Flow 卡片詳情的批次讀取＋快取（計劃 D14、AC8d）。
///
/// - 只問沒快取的 ID，且一批只問一次（S6：批次 21 首約 5 AE；逐首要 1 秒）
/// - 讀取失敗不入快取，下次重試；呼叫端拿不到的卡顯示為 unknown
/// - 寫入成功後由呼叫端以 `updateLyrics` 更新該卡，不重讀
/// - 最新者勝由呼叫端的版本 token 保證（本型別只負責讀與快取）
actor CardDetailsReader {
    private let music: any MusicControlling
    private var cache: [String: TrackDetails] = [:]

    init(music: any MusicControlling) {
        self.music = music
    }

    func details(for persistentIDs: [String]) async -> [String: TrackDetails] {
        let wanted = Array(Set(persistentIDs.filter { !$0.isEmpty }))
        let missing = wanted.filter { cache[$0] == nil }.sorted()
        if !missing.isEmpty, let fetched = try? await music.trackDetails(persistentIDs: missing) {
            for details in fetched {
                cache[details.persistentID] = details
            }
        }
        return wanted.reduce(into: [:]) { result, id in
            result[id] = cache[id]
        }
    }

    /// 本 app 寫入成功後更新快取中的歌詞（狀態由呼叫端依此重算）
    func updateLyrics(_ lyrics: String, for persistentID: String) {
        guard let current = cache[persistentID] else { return }
        cache[persistentID] = TrackDetails(
            persistentID: current.persistentID, artist: current.artist, title: current.title, album: current.album,
            discNumber: current.discNumber, trackNumber: current.trackNumber, lyrics: lyrics
        )
    }
}
