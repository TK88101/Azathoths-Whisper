import Foundation

// 曲名清洗與 URL 正規化（lyrics_fetcher.py:1201-1219 / 1305-1306 的等價實現）
enum TitleSanitizer {
    // py:1209-1213 三條 IGNORECASE 正則，依序套用後 strip
    private static let patterns: [NSRegularExpression] = {
        // 關鍵字中的 i 補上土耳其文變體：re.IGNORECASE 會把 ı(U+0131)/İ(U+0130) 折疊成 i，
        // ICU 的 .caseInsensitive 不折疊，故顯式列出（M2 審查第 3 條）。
        let sources = [
            #"\s*[\(\[]\s*(?:Remastered|L[iıİ]ve|Rem[iıİ]x|Demo|Vers[iıİ]on|feat\.|ft\.).*?[\)\]]"#,
            #"\s*-\s*.*Remastered.*"#,
            #"\s*-\s*.*Rem[iıİ]x.*"#,
        ]
        return sources.map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    static func sanitize(_ title: String) -> String {
        let cleaned = patterns.reduce(title) { partial, regex in
            let range = NSRange(partial.startIndex..., in: partial)
            return regex.stringByReplacingMatches(in: partial, range: range, withTemplate: "")
        }
        return cleaned.pythonStripped()
    }

    // py:1305-1306 `re.sub(r'[^a-z0-9]', '', x.lower())`
    // 在 Unicode scalar 層過濾（非 Character），以對齊 Python 的 code point 語義：
    // 例如 lowercased() 產生的組合附加符號應被單獨刪除，而非連帶刪掉整個字素簇。
    static func normalizeForURL(_ value: String) -> String {
        let scalars = value.pythonLowercased().unicodeScalars.filter { scalar in
            (scalar.value >= 0x61 && scalar.value <= 0x7A) || (scalar.value >= 0x30 && scalar.value <= 0x39)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
