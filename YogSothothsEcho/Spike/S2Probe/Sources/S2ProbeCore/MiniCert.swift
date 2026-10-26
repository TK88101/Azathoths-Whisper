import CryptoKit
import Foundation
import Security

// S2-P2：單一封閉 profile 的最小自簽 X.509（CR-010 ④甲）。
// 只產這一種形狀：v3、16-byte serial、ecdsa-with-SHA256、固定 CN、
// notBefore＝UTCTime（現在）、notAfter＝GeneralizedTime 99991231235959Z（RFC 5280 §4.1.2.5 無到期）、
// P-256 SPKI、BasicConstraints CA:false（critical）、KeyUsage digitalSignature（critical）、EKU serverAuth＋clientAuth。
public enum MiniCert {
    public enum Failure: Error { case publicKeyExport, signing(String), parse }

    static let ecdsaWithSHA256: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
    static let ecPublicKey: [UInt8] = [0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    static let prime256v1: [UInt8] = [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
    static let commonName: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]

    /// DER TLV；長度用最短形式
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        var length: [UInt8]
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
    public static func serial(_ random: [UInt8]) -> [UInt8] {
        precondition(random.count == 16)
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

    /// CN 固定 ASCII（呼叫端保證長度固定，例如 "yse-" ＋ 32 位十六進位）
    static func name(_ cn: String) -> [UInt8] {
        sequence(tlv(0x31, sequence(commonName, tlv(0x0C, Array(cn.utf8)))))
    }

    static func extensions() -> [UInt8] {
        let basicConstraints = sequence([0x06, 0x03, 0x55, 0x1D, 0x13], [0x01, 0x01, 0xFF], tlv(0x04, sequence()))
        let keyUsage = sequence([0x06, 0x03, 0x55, 0x1D, 0x0F], [0x01, 0x01, 0xFF],
                                tlv(0x04, [0x03, 0x02, 0x07, 0x80]))
        let serverAuth: [UInt8] = [0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]
        let clientAuth: [UInt8] = [0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02]
        let eku = sequence([0x06, 0x03, 0x55, 0x1D, 0x25], tlv(0x04, sequence(serverAuth, clientAuth)))
        return tlv(0xA3, sequence(basicConstraints, keyUsage, eku))
    }

    /// X9.63 未壓縮公鑰（65 bytes）
    public static func tbs(publicKey x963: [UInt8], serial: [UInt8], commonName cn: String, notBefore: Date) -> [UInt8] {
        let spki = sequence(sequence(ecPublicKey, prime256v1), tlv(0x03, [0x00] + x963))
        let validity = sequence(utcTime(notBefore), tlv(0x18, Array("99991231235959Z".utf8)))
        return sequence(
            tlv(0xA0, tlv(0x02, [0x02])),
            tlv(0x02, serial),
            sequence(ecdsaWithSHA256),
            name(cn), validity, name(cn), spki, extensions())
    }

    public static func assemble(tbs: [UInt8], signatureDER: [UInt8]) -> [UInt8] {
        sequence(tbs, sequence(ecdsaWithSHA256), tlv(0x03, [0x00] + signatureDER))
    }

    /// 以 SecKey 私鑰簽出整張憑證 DER
    public static func make(privateKey: SecKey, commonName cn: String, notBefore: Date = Date()) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let x963 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw Failure.publicKeyExport }
        var random = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, 16, &random) == errSecSuccess else { throw Failure.signing("random") }
        let toBeSigned = tbs(publicKey: Array(x963), serial: serial(random), commonName: cn, notBefore: notBefore)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256,
                                                    Data(toBeSigned) as CFData, &error) as Data? else {
            throw Failure.signing(String(describing: error?.takeRetainedValue()))
        }
        return Data(assemble(tbs: toBeSigned, signatureDER: Array(signature)))
    }

    public static func fingerprint(_ der: Data) -> Data { Data(SHA256.hash(data: der)) }
}
