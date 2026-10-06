import CoreGraphics
import Foundation

/// mono（母計劃 §2.6 表）：左對齊、Space Grotesk、當前行大＋下一行小灰；當前行淡入上移、舊行淡出；無逐字。
/// 也是「減少動態效果」時所有風格的退化型。數值見 A2 計劃 §3.4
extension LyricsFXFrame.Mono {
    static let enter = 0.35
    /// 距下一行開始多久內先出預覽
    static let previewLead = 2.0
    static let maxCurrentRows = 4
    static let maxPreviewRows = 2
    static let lineHeight: CGFloat = 1.25
    /// 當前行區塊第一列行盒 top 的高度比例
    static let currentTop: CGFloat = 0.36
    /// 位移＝字級 × 它
    static let rise: CGFloat = 0.3
    static let previewScale: CGFloat = 0.5
    static let previewGap: CGFloat = 0.6
    static let bottomInset: CGFloat = 16

    static func plan(
        _ moment: LyricsFXFrame.Moment, time: Double, size: CGSize, motion: LyricsFXMotion, measurer: any TextMeasuring
    ) -> FramePlan {
        let margin = MonoLayout.margin(width: size.width)
        let contentWidth = size.width - 2 * margin
        let fontSize = MonoLayout.currentFontSize(width: size.width)
        let top = size.height * currentTop
        let rowsOf = { (line: TimedLine, size: CGFloat, weight: GlyphWeight, limit: Int) in
            MonoLayout.rows(of: line.text, fontSize: size, weight: weight, maxWidth: contentWidth, maxRows: limit, measurer: measurer)
        }
        var glyphs: [GlyphDraw] = []
        let block = Block(left: margin, bottomLimit: size.height - bottomInset, measurer: measurer)
        var currentRowCount = 1
        if let exiting = moment.exiting {
            let progress = eased((time - exiting.end) / exit)
            let rows = rowsOf(exiting, fontSize, .medium, maxCurrentRows)
            glyphs += block.glyphs(rows, top: top - progress * rise * fontSize, fontSize: fontSize, weight: .medium, opacity: 1 - progress, tone: .primary)
        }
        if let current = moment.current {
            let progress = motion == .full ? eased((time - current.start) / enter) : 1
            let rows = rowsOf(current, fontSize, .medium, maxCurrentRows)
            currentRowCount = max(rows.count, 1)
            glyphs += block.glyphs(rows, top: top + (1 - progress) * rise * fontSize, fontSize: fontSize, weight: .medium, opacity: progress, tone: .primary)
        }
        if let next = moment.next {
            let previewSize = fontSize * previewScale
            let previewTop = top + CGFloat(currentRowCount) * lineHeight * fontSize + previewGap * fontSize
            let rows = rowsOf(next, previewSize, .regular, maxPreviewRows)
            glyphs += block.glyphs(rows, top: previewTop, fontSize: previewSize, weight: .regular, opacity: previewOpacity, tone: .secondary)
        }
        return FramePlan(glyphs: glyphs)
    }

    /// ease-out cubic，輸入先夾在 [0, 1]
    static func eased(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// 把折好的列攤成逐字的繪製指令；超出畫布底部的列不畫
    private struct Block {
        let left: CGFloat
        let bottomLimit: CGFloat
        let measurer: any TextMeasuring

        func glyphs(_ rows: [String], top: CGFloat, fontSize: CGFloat, weight: GlyphWeight, opacity: Double, tone: GlyphDraw.Tone) -> [GlyphDraw] {
            let rowHeight = lineHeight * fontSize
            return rows.enumerated().flatMap { index, row -> [GlyphDraw] in
                let y = top + CGFloat(index) * rowHeight
                guard y >= 0, y + rowHeight <= bottomLimit else { return [] }
                let offsets = measurer.advances(of: row, fontSize: fontSize, weight: weight)
                return zip(row, offsets).compactMap { character, x in
                    guard !character.isWhitespace else { return nil }
                    return GlyphDraw(text: String(character), fontSize: fontSize, weight: weight, origin: CGPoint(x: left + x, y: y), opacity: opacity, tone: tone)
                }
            }
        }
    }
}

/// mono 的折行與尺寸（純函數）
enum MonoLayout {
    static func margin(width: CGFloat) -> CGFloat {
        max(32, width * 0.06)
    }

    static func currentFontSize(width: CGFloat) -> CGFloat {
        min(max(width * 0.052, 24), 54)
    }

    /// 貪婪折行：有空白的文字以詞為單位，否則（CJK）逐字；單詞超寬時逐字折；超過 `maxRows` 截掉（不縮字級）
    static func rows(
        of text: String, fontSize: CGFloat, weight: GlyphWeight, maxWidth: CGFloat, maxRows: Int, measurer: any TextMeasuring
    ) -> [String] {
        let hasSpaces = text.contains(where: \.isWhitespace)
        let tokens = hasSpaces ? text.split(whereSeparator: \.isWhitespace).map(String.init) : text.map(String.init)
        let separator = hasSpaces ? " " : ""
        let width = { (candidate: String) in measurer.advances(of: candidate, fontSize: fontSize, weight: weight).last ?? 0 }
        var rows: [String] = []
        var row = ""
        for token in tokens {
            let candidate = row.isEmpty ? token : row + separator + token
            if width(candidate) <= maxWidth {
                row = candidate
                continue
            }
            if !row.isEmpty { rows.append(row) }
            row = ""
            for character in token {
                let extended = row + String(character)
                if width(extended) > maxWidth, !row.isEmpty {
                    rows.append(row)
                    row = String(character)
                } else {
                    row = extended
                }
            }
        }
        if !row.isEmpty { rows.append(row) }
        return Array(rows.prefix(maxRows))
    }
}
