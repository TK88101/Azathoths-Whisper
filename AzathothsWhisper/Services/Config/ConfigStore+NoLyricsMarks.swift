import Foundation

// 「這首沒有歌詞」標記（計劃 D4）：存 app 設定、**不寫進音樂檔**。
// 身分＝非空 persistentID；空 ID 的曲不可標記（不同的歌會共用同一個空鍵）。
// ⑨ 計劃 §6.5：正本改為 ledger（每個 pid 一個 `SyncRegister<Bool>`，清除＝墓碑），跨機合併時已清除的標記不會復活。
// 舊鍵 `NoLyricsMarkedTrackIDs` 只在 ledger 還沒寫過時讀（單向遷移，revision 0、未蓋章）；之後凍結、不再讀寫——
// 不支援退回舊版後的標記改動回流（R3-2）
extension ConfigStore {
    enum NoLyricsMarksKey {
        static let markedTrackIDs = "NoLyricsMarkedTrackIDs"
        static let ledger = "NoLyricsMarkLedger"
    }

    typealias NoLyricsMarkLedger = [String: SyncRegister<Bool>]

    var noLyricsMarks: Set<String> {
        Set(noLyricsMarkLedger.compactMap { $0.value.value == true ? $0.key : nil })
    }

    /// ledger 還沒寫過＝由舊鍵推出（逐項取字串、略過壞項：一個非字串不得抹掉其他標記，對抗覆核 P2）
    var noLyricsMarkLedger: NoLyricsMarkLedger {
        if let data = defaults.data(forKey: NoLyricsMarksKey.ledger),
           let ledger = try? JSONDecoder().decode(NoLyricsMarkLedger.self, from: data) {
            // ⑨ 安全評審 HIGH-1：壞版本號的單筆不收（否則下一次清除就溢位崩潰）
            return ledger.filter { $0.value.version.isAcceptable(allowUnstamped: true) }
        }
        let legacy = (defaults.array(forKey: NoLyricsMarksKey.markedTrackIDs) ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        return Dictionary(legacy.map { ($0, SyncRegister(value: true, version: SyncVersion(revision: 0, origin: ""))) }) { first, _ in first }
    }

    /// - Returns: 是否真的記下了（空 ID 拒絕）
    @discardableResult
    func markNoLyrics(_ persistentID: String) -> Bool {
        guard !persistentID.isEmpty else { return false }
        let ledger = noLyricsMarkLedger
        guard ledger[persistentID]?.value != true else { return true }
        writeNoLyricsMarkLedger(ledger.merging([persistentID: ledger[persistentID]?.updated(to: true) ?? .fresh(true)]) { _, new in new })
        return true
    }

    func clearNoLyricsMark(_ persistentID: String) {
        let ledger = noLyricsMarkLedger
        guard let current = ledger[persistentID], current.value == true else { return }
        writeNoLyricsMarkLedger(ledger.merging([persistentID: current.updated(to: nil)]) { _, new in new })
    }

    /// 同步用：整份換掉（蓋章、匯入合併後）。排序鍵讓設定內容穩定
    func writeNoLyricsMarkLedger(_ ledger: NoLyricsMarkLedger) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ledger) else { return }
        defaults.set(data, forKey: NoLyricsMarksKey.ledger)
    }
}
