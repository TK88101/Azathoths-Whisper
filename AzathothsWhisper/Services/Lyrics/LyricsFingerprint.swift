import CryptoKit
import Foundation

/// 歌詞文字的指紋：換行統一後 SHA-256 的前 16 bytes（hex）。
///
/// **全專案唯一定義**（A1 計劃 §2）：monitor 判同曲改詞、時間軸存檔的 `lyricsHash`、
/// 歌詞特效判「詞變了」都用它——三處各算各的，換行或截斷規則一漂移就會互相誤判。
/// 只存指紋、不存文字：日誌與磁碟上都不留歌詞
struct LyricsFingerprint: Hashable, Sendable {
    static let hexLength = 32

    let hex: String

    static func of(_ text: String) -> LyricsFingerprint {
        let digest = SHA256.hash(data: Data(LineEndings.normalized(text).utf8))
        return LyricsFingerprint(validated: digest.prefix(hexLength / 2).map { String(format: "%02x", $0) }.joined())
    }

    private init(validated hex: String) {
        self.hex = hex
    }

    /// 從存檔還原：必須是 32 位小寫 hex，否則視為壞資料
    init?(hex candidate: String) {
        guard candidate.count == Self.hexLength,
              candidate.allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase })
        else { return nil }
        self.init(validated: candidate)
    }
}

extension LyricsFingerprint: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let value = LyricsFingerprint(hex: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a lyrics fingerprint")
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
