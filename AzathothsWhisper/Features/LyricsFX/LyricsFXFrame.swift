import CoreGraphics
import Foundation

/// 動態程度：`reduced`＝系統「減少動態效果」，無淡入淡出、無位移（母計劃 §2.6 mono 列；A2 計劃 §3.5）
enum LyricsFXMotion: Sendable {
    case full, reduced
}

enum GlyphWeight: Sendable, Hashable {
    case regular, medium
}

/// 一個字（grapheme）的繪製指令。`origin`＝該字行盒的 **top-leading**，Canvas 以 `anchor: .topLeading` 畫
/// （同字級同行盒高，基線自然一致；A2 計劃 §2，Codex R1 #11）。只有 mono 用得到的欄位，B 段再加旋轉、縮放、模糊
struct GlyphDraw: Equatable, Sendable {
    /// 主色＝當前行；次色＝下一行預覽
    enum Tone: Sendable, Hashable {
        case primary, secondary
    }

    let text: String
    let fontSize: CGFloat
    let weight: GlyphWeight
    let origin: CGPoint
    let opacity: Double
    let tone: Tone
}

/// 某一刻要畫的東西（母計劃 §2.7）。純資料；背景由畫面自己畫（mono 只有 `Theme.background`）
struct FramePlan: Equatable, Sendable {
    static let empty = FramePlan(glyphs: [])

    let glyphs: [GlyphDraw]
}

/// 字寬量測：回傳 `text` 每個 grapheme 起點的 x 位移，末項＝總寬（共 `text.count + 1` 項）。
/// 依整列排版後取位移；連字、RTL、複雜文字不保證與整列 shaping 完全一致（A2 計劃 §3.4，Codex R2）
protocol TextMeasuring {
    func advances(of text: String, fontSize: CGFloat, weight: GlyphWeight) -> [CGFloat]
}

/// 繪製引擎的純函數 plan（母計劃 §2.7；A2 計劃 §3.4）：同輸入同輸出、不按尺寸快取
enum LyricsFXFrame {
    /// 任一邊小於它就不畫字
    static let minimumSide: CGFloat = 120

    /// 跨檔共用的 mono 常數（版面數值在 `MonoStyle.swift`）
    enum Mono {
        static let previewOpacity = 0.55
        static let exit = 0.35
    }

    static func plan(
        timeline: LyricsTimeline?, time: Double?, size: CGSize, motion: LyricsFXMotion, measurer: any TextMeasuring
    ) -> FramePlan {
        guard let timeline, let time, size.width >= minimumSide, size.height >= minimumSide else { return .empty }
        let moment = Moment(lines: timeline.lines, time: time, motion: motion)
        return Mono.plan(moment, time: time, size: size, motion: motion, measurer: measurer)
    }

    /// 無障礙用：此刻正在唱的那一行（A2 計劃 §3.4）
    static func currentLineText(timeline: LyricsTimeline?, time: Double?) -> String? {
        guard let timeline, let time else { return nil }
        return Moment(lines: timeline.lines, time: time, motion: .reduced).current?.text
    }

    /// 此刻要畫哪幾行。`current` 一律尊重既有 `TimedLine.end`，不重推（間奏空檔由 builder 決定，Codex R1 #10）
    struct Moment {
        let current: TimedLine?
        /// 剛結束、還在淡出的行（只在 full）
        let exiting: TimedLine?
        /// 下一行預覽：有當前行時、或距它開始 ≤ `previewLead` 時才有
        let next: TimedLine?

        init(lines: [TimedLine], time: Double, motion: LyricsFXMotion) {
            let current = lines.first { $0.start <= time && time < $0.end && !Self.isBlank($0) }
            self.current = current
            exiting = motion == .full
                ? lines.last { $0.end <= time && time < $0.end + Mono.exit && !Self.isBlank($0) && $0 != current }
                : nil
            let upcoming = lines.first { $0.start > time && !Self.isBlank($0) }
            let isNear = upcoming.map { $0.start - time <= Mono.previewLead } ?? false
            next = (current != nil || isNear) ? upcoming : nil
        }

        private static func isBlank(_ line: TimedLine) -> Bool {
            line.text.allSatisfy(\.isWhitespace)
        }
    }
}

/// `TimelineView` 的排程（A2 計劃 §3.4 排程表，Codex R1 #1／R2）：
/// 不可見或沒在播 → 不建定時器（暫停時以當下位置畫一次靜態畫面）
enum LyricsFXSchedule: Sendable, Equatable {
    case none, animation, periodic

    static func resolve(isVisible: Bool, isRunning: Bool, reduceMotion: Bool) -> LyricsFXSchedule {
        guard isVisible, isRunning else { return .none }
        return reduceMotion ? .periodic : .animation
    }
}
