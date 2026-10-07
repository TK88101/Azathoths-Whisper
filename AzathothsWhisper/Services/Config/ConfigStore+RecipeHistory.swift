import Foundation

// 歌詞特效：同一首歌上一次各槽選中的元件（2026-10-06 使用者定案：下次播放每槽排除它，「每次都感覺變了」）。
// 只以 Music 的 16 位 hex persistentID 為鍵（與「沒有歌詞」標記、時間軸存檔同一種身分）；不存曲名、歌詞。
// 最多記 `recipeHistoryCapacity` 首，超過丟最久沒播的
extension ConfigStore {
    enum RecipeHistoryKey {
        static let lastPicks = "LyricsFXLastPicks"
    }

    static let recipeHistoryCapacity = 500

    func lastLyricsFXPicks(forTrack persistentID: String) -> RecipePicks? {
        guard let key = Self.recipeHistoryKey(persistentID) else { return nil }
        return recipeHistory().last { $0.track == key }?.picks
    }

    /// 非 persistentID（空、三元組簽名、格式不對）一律不寫
    func recordLyricsFXPicks(_ picks: RecipePicks, forTrack persistentID: String) {
        guard let key = Self.recipeHistoryKey(persistentID) else { return }
        var entries = recipeHistory().filter { $0.track != key }
        entries.append((key, picks))
        let kept = entries.suffix(Self.recipeHistoryCapacity)
        defaults.set(kept.map { [$0.track] + $0.picks.stored }, forKey: RecipeHistoryKey.lastPicks)
    }

    /// 由舊到新；逐項取、略過壞項（同 `noLyricsMarks` 的理由：一個壞項不得抹掉整份）
    private func recipeHistory() -> [(track: String, picks: RecipePicks)] {
        let raw = defaults.array(forKey: RecipeHistoryKey.lastPicks) ?? []
        return raw.compactMap { item in
            guard let row = item as? [String], let first = row.first, let picks = RecipePicks(stored: Array(row.dropFirst())) else { return nil }
            return (first, picks)
        }
    }

    /// 只收 16 位 ASCII hex，轉大寫
    static func recipeHistoryKey(_ persistentID: String) -> String? {
        guard persistentID.utf8.count == 16, persistentID.utf8.allSatisfy({ $0.isASCIIHexDigit }) else { return nil }
        return persistentID.uppercased()
    }
}

private extension UInt8 {
    var isASCIIHexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}
