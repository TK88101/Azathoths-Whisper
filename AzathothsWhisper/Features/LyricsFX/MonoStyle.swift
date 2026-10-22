import CoreGraphics
import Foundation

/// mono（母計劃 §2.6 表）：左對齊、Space Grotesk、當前行大＋下一行小灰；當前行淡入上移、舊行淡出；無逐字。
/// 也是「減少動態效果」時所有風格的退化型。數值見 A2 計劃 §3.4；常數全在本檔（B1 計劃 §1.2）
extension LyricsFXFrame { enum Mono {} }

extension LyricsFXFrame.Mono {
    static let previewOpacity = 0.55
    static let enter = 0.35
    static let exit = 0.35
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
    static let timing = LyricsFXFrame.MomentTiming(exit: exit, previewLead: previewLead)

    static func plan(
        _ moment: LyricsFXFrame.Moment, time: Double, size: CGSize, motion: LyricsFXMotion, language: CJKLanguage, measurer: any TextMeasuring
    ) -> FramePlan {
        let margin = MonoLayout.margin(width: size.width)
        let contentWidth = size.width - 2 * margin
        let fontSize = MonoLayout.currentFontSize(width: size.width)
        let top = size.height * currentTop
        // 含中日韓字的行整行換字型（⑤ 計劃 §4.2）
        let current = { (line: TimedLine) in FontFace.lineFace(for: line.script, language: language, role: .monoCurrent, base: .displayMedium) ?? .displayMedium }
        let preview = { (line: TimedLine) in FontFace.lineFace(for: line.script, language: language, role: .monoPreview, base: .displayRegular) ?? .displayRegular }
        let rowsOf = { (line: TimedLine, size: CGFloat, face: FontFace, limit: Int) in
            MonoLayout.rows(of: line.text, fontSize: size, face: face, maxWidth: contentWidth, maxRows: limit, measurer: measurer)
        }
        var glyphs: [GlyphDraw] = []
        let block = Block(left: margin, bottomLimit: size.height - bottomInset, measurer: measurer)
        var currentRowCount = 1
        if let exiting = moment.exiting {
            let progress = eased((time - exiting.end) / exit)
            let face = current(exiting)
            let rows = rowsOf(exiting, fontSize, face, maxCurrentRows)
            glyphs += block.glyphs(rows, top: top - progress * rise * fontSize, fontSize: fontSize, face: face, opacity: 1 - progress, color: .fg)
        }
        if let line = moment.current {
            let progress = motion == .full ? eased((time - line.start) / enter) : 1
            let face = current(line)
            let rows = rowsOf(line, fontSize, face, maxCurrentRows)
            currentRowCount = max(rows.count, 1)
            glyphs += block.glyphs(rows, top: top + (1 - progress) * rise * fontSize, fontSize: fontSize, face: face, opacity: progress, color: .fg)
        }
        if let next = moment.next {
            let previewSize = fontSize * previewScale
            let previewTop = top + CGFloat(currentRowCount) * lineHeight * fontSize + previewGap * fontSize
            let face = preview(next)
            let rows = rowsOf(next, previewSize, face, maxPreviewRows)
            glyphs += block.glyphs(rows, top: previewTop, fontSize: previewSize, face: face, opacity: previewOpacity, color: .dim)
        }
        return FramePlan(palette: .mono, glyphs: glyphs)
    }

    /// ease-out cubic，輸入先夾在 [0, 1]
    static func eased(_ progress: Double) -> Double {
        FXEasing.outCubic(FXEasing.clamp01(progress))
    }

    /// 把折好的列攤成逐字的繪製指令；超出畫布底部的列不畫
    private struct Block {
        let left: CGFloat
        let bottomLimit: CGFloat
        let measurer: any TextMeasuring

        func glyphs(_ rows: [String], top: CGFloat, fontSize: CGFloat, face: FontFace, opacity: Double, color: ColorSlot) -> [GlyphDraw] {
            let rowHeight = lineHeight * fontSize
            return rows.enumerated().flatMap { index, row -> [GlyphDraw] in
                let y = top + CGFloat(index) * rowHeight
                guard y >= 0, y + rowHeight <= bottomLimit else { return [] }
                let offsets = measurer.advances(of: row, face: face, fontSize: fontSize)
                return zip(row, offsets).compactMap { character, x in
                    guard !character.isWhitespace else { return nil }
                    return GlyphDraw(text: String(character), face: face, fontSize: fontSize, origin: CGPoint(x: left + x, y: y), opacity: opacity, color: color)
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

    /// 貪婪折行：原文空白處與中日文字之間可斷、守最小禁則（⑤ 計劃 §4.4，`CJKLineBreak`）；單詞超寬時逐字折；超過 `maxRows` 截掉（不縮字級）
    static func rows(
        of text: String, fontSize: CGFloat, face: FontFace, maxWidth: CGFloat, maxRows: Int, measurer: any TextMeasuring
    ) -> [String] {
        let width = { (candidate: String) in measurer.advances(of: candidate, face: face, fontSize: fontSize).last ?? 0 }
        let space = width(" ")
        var pieces: [(text: String, spaceBefore: Bool, token: CJKLineBreak.Token)] = []
        for piece in CJKLineBreak.tokens(of: text) {
            let gap = piece.spaceBefore ? space : 0
            let pieceWidth = width(piece.text)
            guard pieceWidth > maxWidth, piece.text.count > 1 else {
                pieces.append((piece.text, piece.spaceBefore, CJKLineBreak.Token(width: pieceWidth, gapBefore: gap, leading: piece.text, trailing: piece.text)))
                continue
            }
            // 超寬的詞逐字斷（所在列已有字就先換列）
            for (offset, character) in piece.text.enumerated() {
                let single = String(character)
                let split = CJKLineBreak.Token(
                    width: width(single), gapBefore: offset == 0 ? gap : 0, leading: single, trailing: single, forcesNewRow: offset == 0
                )
                pieces.append((single, offset == 0 && piece.spaceBefore, split))
            }
        }
        let rowOf = CJKLineBreak.assignRows(pieces.map(\.token), maxWidth: maxWidth)
        var rows: [String] = []
        for (index, piece) in pieces.enumerated() {
            if rowOf[index] == rows.count {
                rows.append(piece.text)
            } else {
                rows[rows.count - 1] += (piece.spaceBefore ? " " : "") + piece.text
            }
        }
        return Array(rows.prefix(maxRows))
    }
}
