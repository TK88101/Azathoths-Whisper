import Foundation

/// 一行歌詞的文字種類（⑤ 中日韓字型計劃 §4.1）：韓文優先，其次中日文
enum LineScript: Sendable, Equatable {
    case latin
    /// 含假名、漢字、全形標點或全形英數
    case cjk
    /// 含任一諺文（即使同時有漢字或假名）
    case hangul
}

/// 整首歌的中日文之分：決定 `.cjk` 行用冬青黑體還是蘋方
enum CJKLanguage: Sendable, Equatable {
    case japanese, chinese
}

/// 中日韓字元的唯一定義（`JapaneseText` 也由這裡推出）
enum LyricsScript {
    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF: return true   // 平假名、片假名、片假名擴充
        default: return false
        }
    }

    /// CJK 基本漢字與擴充 A
    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF: return true
        default: return false
        }
    }

    static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return true   // 字母、相容字母、音節
        default: return false
        }
    }

    /// 要用中日文字型排的字：假名、漢字、相容漢字、中日韓標點、全形英數與標點
    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        if isKana(scalar) || isHan(scalar) { return true }
        switch scalar.value {
        case 0x3000...0x303F, 0xF900...0xFAFF, 0xFF00...0xFFEF: return true
        default: return false
        }
    }

    static func line(_ text: String) -> LineScript {
        let scalars = text.unicodeScalars
        if scalars.contains(where: isHangul) { return .hangul }
        if scalars.contains(where: isCJK) { return .cjk }
        return .latin
    }

    /// 只看歌詞：有任一假名＝日文，否則中文（全漢字日文歌判成中文是已知限制，計劃 §4.1）
    static func language(of texts: [String]) -> CJKLanguage {
        texts.contains { $0.unicodeScalars.contains(where: isKana) } ? .japanese : .chinese
    }
}
