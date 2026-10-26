import Foundation

/// 比對用正規化（設計 §5.3 許可閘門與 S3 搜尋共用；同一語義只留這一處）：
/// NFKC → 不分大小寫、全半形、重音 → 片假名併入平假名。
/// 日文濁點／半濁點保留（diacriticInsensitive 不去它們，2026-10-17 實測，TextFoldTests 鎖住）。
public enum TextFold {
    public static func fold(_ text: String) -> String {
        let compatible = text.precomposedStringWithCompatibilityMapping
        let folded = compatible.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.applyingTransform(.hiraganaToKatakana, reverse: true) ?? folded
    }
}

/// 回應文字截斷（sprint-3-detail.md §4.3）：先截 grapheme 數，再截 UTF-8 位元組；不切斷 grapheme
public enum TextClamp {
    public static func clamp(_ text: String) -> String {
        var result = String(text.prefix(CatalogLimits.maxTextCharacters))
        while result.utf8.count > CatalogLimits.maxTextUTF8Bytes { result.removeLast() }
        return result
    }
}
