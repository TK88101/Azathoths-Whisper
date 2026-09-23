import Foundation

// 「這首沒有歌詞」標記（計劃 D4）：存 app 設定、**不寫進音樂檔**。
// 身分＝非空 persistentID；空 ID 的曲不可標記（不同的歌會共用同一個空鍵）。
extension ConfigStore {
    enum NoLyricsMarksKey {
        static let markedTrackIDs = "NoLyricsMarkedTrackIDs"
    }

    /// 逐項取字串、略過壞項：`stringArray(forKey:)` 遇到一個非字串就整組回 nil，
    /// 下一次標記便會以空集合覆寫、抹掉其他標記（對抗覆核 P2）
    var noLyricsMarks: Set<String> {
        let raw = defaults.array(forKey: NoLyricsMarksKey.markedTrackIDs) ?? []
        return Set(raw.compactMap { $0 as? String }.filter { !$0.isEmpty })
    }

    /// - Returns: 是否真的記下了（空 ID 拒絕）
    @discardableResult
    func markNoLyrics(_ persistentID: String) -> Bool {
        guard !persistentID.isEmpty else { return false }
        write(noLyricsMarks.union([persistentID]))
        return true
    }

    func clearNoLyricsMark(_ persistentID: String) {
        let current = noLyricsMarks
        guard current.contains(persistentID) else { return }
        write(current.subtracting([persistentID]))
    }

    /// 排序後存，讓設定檔內容穩定（同一集合每次寫出相同的陣列）
    private func write(_ marks: Set<String>) {
        defaults.set(marks.sorted(), forKey: NoLyricsMarksKey.markedTrackIDs)
    }
}
