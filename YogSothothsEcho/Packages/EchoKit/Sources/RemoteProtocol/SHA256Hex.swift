import CryptoKit
import Foundation

extension Data {
    /// SHA-256 的 64 字小寫十六進位：CR-018 detail digest（Mac 算、iPad 驗）與快取檔名鍵共用的唯一一處寫法
    public var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
