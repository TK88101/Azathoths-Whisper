import Foundation
import OSLog

private let timingFlagLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "timing-flags")

/// ⑪「時間軸不準」標記的接線（計劃 §4.3）：只記證據，不改顯示、不重查、不同步
extension AppModel {
    /// 沒有標記存檔（單元測試預設）就不接：特效層不提供右鍵選單
    func installTimingFlags() {
        guard let timingFlags else { return }
        lyricsFX.timingFlagLookup = { key in await timingFlags.isFlagged(key) }
        lyricsFX.onToggleTimingFlag = { [weak self] request in await self?.toggleTimingFlag(request) ?? false }
    }

    /// 標記時把畫面快照與存檔比對（provenance）；日誌只記結果與錯誤類型，不記曲名歌詞
    func toggleTimingFlag(_ request: TimingFlagRequest) async -> Bool {
        guard let timingFlags else { return false }
        do {
            if request.wantsFlagged {
                let record = await timingStore?.load(persistentID: request.key.persistentID)
                let resolved = TimingFlagProvenance.resolve(applied: request.applied, lyricsHash: request.key.lyricsHash, record: record)
                try await timingFlags.flag(TimingFlag(
                    persistentID: request.key.persistentID, lyricsHash: request.key.lyricsHash, markedAt: Date(),
                    positions: request.position.map { [$0] } ?? [], applied: request.applied,
                    stored: resolved.stored, provenance: resolved.provenance
                ))
                timingFlagLog.info("timing flag set (\(resolved.provenance.rawValue, privacy: .public))")
            } else {
                try await timingFlags.clear(request.key)
                timingFlagLog.info("timing flag cleared")
            }
            return true
        } catch {
            timingFlagLog.error("timing flag failed: \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
    }
}
