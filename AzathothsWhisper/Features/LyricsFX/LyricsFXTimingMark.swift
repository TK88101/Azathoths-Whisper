import Foundation

/// 特效層角落的 `~`（母計劃 §2.4 層 3、C 段計劃 §3.10）：只有估算時間才標；外部時間軸或內嵌 LRC 不標
enum LyricsFXTimingMark {
    static let symbol = "~"

    static func isShown(timeline: LyricsTimeline?, status: LyricsStatus) -> Bool {
        status == .present && timeline?.source == .estimated
    }

    enum Kind: Equatable, Sendable { case none, estimated, flagged }

    /// ⑪：同一個角落兩種記號。`!` 只在畫面的時間軸就是被標記的那份時出現；
    /// 標過的歌重新播放、外部時間軸還沒回來的估算窗口只顯示 `~`（Codex R2-3）
    static func resolve(timeline: LyricsTimeline?, status: LyricsStatus, flag: TimingFlagState, hasAppliedTiming: Bool) -> Kind {
        if isShown(timeline: timeline, status: status) { return .estimated }
        return flag == .flagged && hasAppliedTiming ? .flagged : .none
    }

    static let flaggedSymbol = "!"
}

/// ⑪：當前這首（當前歌詞）的「不準」標記狀態
enum TimingFlagState: Equatable, Sendable {
    case unflagged, flagged, pending
}

/// ⑪ 右鍵選單文案：選單一律寫死英文（A-07）
enum TimingFlagMenu {
    static let mark = "Mark Timing as Off"
    static let unmark = "Unmark Timing"
}
