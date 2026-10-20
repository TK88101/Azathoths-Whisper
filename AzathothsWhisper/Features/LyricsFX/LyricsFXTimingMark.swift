import Foundation

/// 特效層角落的 `~`（母計劃 §2.4 層 3、C 段計劃 §3.10）：只有估算時間才標；外部時間軸或內嵌 LRC 不標
enum LyricsFXTimingMark {
    static let symbol = "~"

    static func isShown(timeline: LyricsTimeline?, status: LyricsStatus) -> Bool {
        status == .present && timeline?.source == .estimated
    }
}
