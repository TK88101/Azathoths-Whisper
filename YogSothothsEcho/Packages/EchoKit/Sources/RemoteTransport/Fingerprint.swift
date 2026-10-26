import CryptoKit
import Foundation

/// 憑證指紋＝leaf DER 的 SHA-256（CR-010 ③）。釘選與信任紀錄一律用它
public struct Fingerprint: Hashable, Codable, Sendable {
    public static let byteCount = 32
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    public init(der: Data) {
        bytes = Data(SHA256.hash(data: der))
    }

    /// 末 2 bytes 的大寫十六進位；Mac 確認窗與 iPad 等待畫面同顯（CR-010 ②(f)）
    public var suffix: String {
        bytes.suffix(2).map { String(format: "%02X", $0) }.joined()
    }

    public init(from decoder: any Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        guard let value = Fingerprint(bytes: data) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "fingerprint length"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytes)
    }
}
