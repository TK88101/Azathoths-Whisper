import CoreGraphics
import Foundation

/// 中日韓行的字型用途：組合樣式、素面目前行、素面預覽行
enum CJKFaceRole: Sendable, CaseIterable {
    case composed, monoCurrent, monoPreview
}

/// 含中日韓字的行整行換字型（⑤ 中日韓字型計劃 §4.2；使用者 2026-10-22：中文蘋方、日文冬青黑體、韓文隨意、整行同一字型）。
/// 以 PostScript 名指定字重（family＋trait 不保證解析到指定的冬青黑體 W 系列）
extension FontFace {
    /// 中日韓字身本身已含字間，只留一點
    static let cjkSpacing: CGFloat = 0.02

    private static let postScriptNames: [CJKFaceRole: (japanese: String, chinese: String, korean: String)] = [
        .composed: ("HiraginoSans-W6", "PingFangTC-Semibold", "AppleSDGothicNeo-SemiBold"),
        .monoCurrent: ("HiraginoSans-W5", "PingFangTC-Medium", "AppleSDGothicNeo-Medium"),
        .monoPreview: ("HiraginoSans-W4", "PingFangTC-Regular", "AppleSDGothicNeo-Regular"),
    ]

    /// 這一行該換的字型；拉丁行回 nil（照用 `base`）。`uppercase` 跟著 `base`，只影響行內的拉丁字母
    static func lineFace(for script: LineScript, language: CJKLanguage, role: CJKFaceRole, base: FontFace) -> FontFace? {
        guard let names = postScriptNames[role] else { return nil }
        let name: String
        switch script {
        case .latin: return nil
        case .hangul: name = names.korean
        case .cjk: name = language == .japanese ? names.japanese : names.chinese
        }
        return FontFace(
            id: "cjk:\(name)\(base.uppercase ? ":upper" : "")", family: name, weight: nil, uppercase: base.uppercase,
            spacing: cjkSpacing, postScriptName: name
        )
    }
}
