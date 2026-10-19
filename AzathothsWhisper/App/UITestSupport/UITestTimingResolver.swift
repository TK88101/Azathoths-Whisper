// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// 歌詞特效 E2E 的假退路鏈（C 段計劃 §5）：不連網、立即回答。
/// 「找到」時間＝預覽 LRC 的時間點（熱替換後 `~` 消失）；「沒有」則一直是估算（`~` 留著）
struct UITestTimingResolver: TimingResolving {
    let finds: Bool

    init?(environment value: String?) {
        switch value {
        case "found": finds = true
        case "notFound": finds = false
        default: return nil
        }
    }

    func resolve(_ request: TimingRequest, priority: TimingPriority) async -> TimingResolution {
        let lines = LyricsFXPreviewFixture.timedLines.enumerated().map { TimingRecord.LineStart(index: $0.offset, start: $0.element.start) }
        return TimingResolution(persistentID: request.persistentID, lyricsHash: .of(request.lyrics), outcome: finds ? .found(.lrclib, lines) : .notFound)
    }

    func storedNotFound(persistentID: String, lyricsHash: LyricsFingerprint) async -> Bool { false }

    func shutdown() async {}
}
#endif
