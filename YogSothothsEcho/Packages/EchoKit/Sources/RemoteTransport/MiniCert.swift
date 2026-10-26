import Foundation
import Security

/// 單一封閉 profile 的最小自簽 X.509（CR-010 ④甲；S2-P2 驗證過）。只產這一種形狀，**不得擴成通用 ASN.1 encoder**：
/// v3、16-byte serial、ecdsa-with-SHA256、CN＝`yse-` ＋ 32 位小寫十六進位、notBefore＝UTCTime（現在）、
/// notAfter＝GeneralizedTime 99991231235959Z（RFC 5280 §4.1.2.5 無到期；釘選取代有效期檢查）、P-256 SPKI、
/// BasicConstraints CA:false（critical）、KeyUsage digitalSignature（critical）、EKU serverAuth＋clientAuth。
public enum MiniCert {
    public enum Failure: Error, Sendable { case commonName, publicKeyExport, random, signing }

    /// 此 profile 的 TBS 長度恆定（只有外層簽章長度可變）
    public static let tbsLength = 327

    static let ecdsaWithSHA256: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
    static let ecPublicKey: [UInt8] = [0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    static let prime256v1: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
    static let commonNameOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
    static let serverAuth: [UInt8] = [0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]
    static let clientAuth: [UInt8] = [0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02]

    public static func isValidCommonName(_ cn: String) -> Bool {
        let hex = cn.dropFirst(4)
        return cn.hasPrefix("yse-") && hex.count == 32 && hex.unicodeScalars.allSatisfy { "0123456789abcdef".unicodeScalars.contains($0) }
    }

    /// 隨機 CN（符合 profile）
    public static func randomCommonName() -> String {
        "yse-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: DER（只服務本 profile）

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let length: [UInt8]
        if content.count < 0x80 {
            length = [UInt8(content.count)]
        } else {
            var n = content.count
            var bytes: [UInt8] = []
            while n > 0 { bytes.insert(UInt8(n & 0xFF), at: 0); n >>= 8 }
            length = [0x80 | UInt8(bytes.count)] + bytes
        }
        return [tag] + length + content
    }

    static func sequence(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }

    /// 首位元組落在 0x01…0x7F：正數、非零開頭，DER 最短形式恆為 16 bytes
    static func serial(_ random: [UInt8]) -> [UInt8] {
        var bytes = random
        bytes[0] = (bytes[0] & 0x7F) | 0x01
        return bytes
    }

    static func utcTime(_ date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Array(formatter.string(from: date).utf8))
    }

    static func name(_ cn: String) -> [UInt8] {
        sequence(tlv(0x31, sequence(commonNameOID, tlv(0x0C, Array(cn.utf8)))))
    }

    static func extensions() -> [UInt8] {
        let basicConstraints = sequence([0x06, 0x03, 0x55, 0x1D, 0x13], [0x01, 0x01, 0xFF], tlv(0x04, sequence()))
        let keyUsage = sequence([0x06, 0x03, 0x55, 0x1D, 0x0F], [0x01, 0x01, 0xFF], tlv(0x04, [0x03, 0x02, 0x07, 0x80]))
        let eku = sequence([0x06, 0x03, 0x55, 0x1D, 0x25], tlv(0x04, sequence(serverAuth, clientAuth)))
        return tlv(0xA3, sequence(basicConstraints, keyUsage, eku))
    }

    static func tbs(publicKey x963: [UInt8], serial: [UInt8], commonName cn: String, notBefore: Date) -> [UInt8] {
        let spki = sequence(sequence(ecPublicKey, prime256v1), tlv(0x03, [0x00] + x963))
        let validity = sequence(utcTime(notBefore), tlv(0x18, Array("99991231235959Z".utf8)))
        return sequence(tlv(0xA0, tlv(0x02, [0x02])), tlv(0x02, serial), sequence(ecdsaWithSHA256),
                        name(cn), validity, name(cn), spki, extensions())
    }

    /// 以 SecKey 私鑰簽出整張憑證 DER
    public static func make(privateKey: SecKey, commonName cn: String, notBefore: Date = Date()) throws(Failure) -> Data {
        guard isValidCommonName(cn) else { throw .commonName }
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let x963 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?, x963.count == 65 else {
            throw .publicKeyExport
        }
        var random = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw .random }
        let toBeSigned = tbs(publicKey: Array(x963), serial: serial(random), commonName: cn, notBefore: notBefore)
        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256,
                                                    Data(toBeSigned) as CFData, nil) as Data? else { throw .signing }
        return Data(sequence(toBeSigned, sequence(ecdsaWithSHA256), tlv(0x03, [0x00] + Array(signature))))
    }

    /// 拆出本 profile 憑證的 TBS 與簽章（測試與自檢用；非本 profile 的輸入回 nil）
    public static func split(_ der: Data) -> (tbs: Data, signature: Data)? {
        let bytes = [UInt8](der)
        func header(_ at: Int) -> (start: Int, length: Int)? {
            guard at + 1 < bytes.count else { return nil }
            let first = bytes[at + 1]
            if first < 0x80 { return (at + 2, Int(first)) }
            let n = Int(first & 0x7F)
            guard n <= 2, at + 2 + n <= bytes.count else { return nil }
            let length = (0..<n).reduce(0) { $0 << 8 | Int(bytes[at + 2 + $1]) }
            return (at + 2 + n, length)
        }
        guard let outer = header(0), let tbsHeader = header(outer.start) else { return nil }
        let tbsEnd = tbsHeader.start + tbsHeader.length
        guard let alg = header(tbsEnd), let bits = header(alg.start + alg.length),
              bits.start + bits.length <= bytes.count, bits.length > 1 else { return nil }
        return (Data(bytes[outer.start..<tbsEnd]), Data(bytes[(bits.start + 1)..<(bits.start + bits.length)]))
    }
}
