import Foundation
import RemoteProtocol

/// 對端自報的裝置名稱只當顯示用（CR-010 ②(f)：名稱不是身分）；顯示前一律淨化
public enum DeviceName {
    /// 去控制字元與格式字元（含 bidi 覆寫、零寬字元）、NFC、去首尾空白、截到顯示上限；清完是空字串就用 fallback
    public static func sanitize(_ raw: String, fallback: String) -> String {
        let kept = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: false
            default: true
            }
        }
        let cleaned = String(String.UnicodeScalarView(kept)).precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(cleaned.prefix(TransportLimits.displayNameMaxCharacters))
        return truncated.isEmpty ? fallback : truncated
    }
}
