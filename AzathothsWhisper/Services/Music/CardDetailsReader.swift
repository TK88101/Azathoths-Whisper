import Foundation

/// Cover Flow 卡片詳情的批次讀取＋快取（計劃 D14、AC8d）。
///
/// - 只問沒快取的 ID，且一批只問一次（S6：批次 21 首約 5 AE；逐首要 1 秒）
/// - 讀取失敗不入快取，下次重試；呼叫端拿不到的卡顯示為 unknown
/// - 寫入成功後由呼叫端以 `updateLyrics` 更新該卡，不重讀
/// - 最新者勝：套用到畫面由呼叫端的世代號保證；快取本身也不收比現有更舊的讀取（`stamps`）
actor CardDetailsReader {
    private let music: any MusicControlling
    private var cache: [String: TrackDetails] = [:]
    /// 每筆快取的新舊（AC8d「舊任務不得覆蓋新版」）：讀取取「發出時」的序號、寫入更新取當下最新序號；
    /// actor 在 await 時可重入，較早發出的一批可能較晚回來，只收比現有快取新的
    private var stamps: [String: Int] = [:]
    private var sequence = 0

    init(music: any MusicControlling) {
        self.music = music
    }

    func details(for persistentIDs: [String]) async -> [String: TrackDetails] {
        let wanted = Array(Set(persistentIDs.filter { !$0.isEmpty }))
        let missing = wanted.filter { cache[$0] == nil }.sorted()
        if !missing.isEmpty {
            sequence += 1
            let issued = sequence
            if let fetched = try? await music.trackDetails(persistentIDs: missing) {
                for details in fetched where stamps[details.persistentID, default: 0] < issued {
                    cache[details.persistentID] = details
                    stamps[details.persistentID] = issued
                }
            }
        }
        return wanted.reduce(into: [:]) { result, id in
            result[id] = cache[id]
        }
    }

    /// 本 app 寫入成功後更新快取中的歌詞（狀態由呼叫端依此重算）
    /// 還沒進快取時也推進序號：寫入前就發出、還在路上的批次回來時不收（該首下次重讀）
    func updateLyrics(_ lyrics: String, for persistentID: String) {
        sequence += 1
        stamps[persistentID] = sequence
        guard let current = cache[persistentID] else { return }
        cache[persistentID] = TrackDetails(
            persistentID: current.persistentID, artist: current.artist, title: current.title, album: current.album,
            discNumber: current.discNumber, trackNumber: current.trackNumber, lyrics: lyrics
        )
    }
}
