import Foundation
import Security

// S2-P2：產生金鑰 → 自簽憑證 → Keychain → 取回 SecIdentity。
// 只用專屬 label／tag（yse-s2-spike.*），teardown 必刪。
public struct SpikeIdentity: @unchecked Sendable {
    public let identity: SecIdentity
    public let certificateDER: Data
    public let tag: String
    /// macOS 舊式鑰匙圈加憑證時忽略 kSecAttrLabel、label 一律＝CN（2026-10-15 實測）；刪除與殘留檢查都以 CN 為準
    public let commonName: String
    public var fingerprint: Data { MiniCert.fingerprint(certificateDER) }

    public enum Failure: Error, CustomStringConvertible {
        case keyGeneration(String), certificateParse, addCertificate(OSStatus), identityNotFound(OSStatus)
        public var description: String {
            switch self {
            case .keyGeneration(let s): "keyGeneration \(s)"
            case .certificateParse: "certificateParse"
            case .addCertificate(let s): "addCertificate \(s)"
            case .identityNotFound(let s): "identityNotFound \(s)"
            }
        }
    }

    public static func create(name: String) throws -> SpikeIdentity {
        let tag = "yse-s2-spike.\(name).\(UUID().uuidString)"
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrLabel: tag,
                kSecAttrApplicationTag: Data(tag.utf8),
            ] as [CFString: Any],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw Failure.keyGeneration(String(describing: error?.takeRetainedValue()))
        }
        let cn = "yse-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let der = try MiniCert.make(privateKey: key, commonName: cn)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            delete(tag: tag, commonName: cn)
            throw Failure.certificateParse
        }
        let status = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: certificate,
                                 kSecAttrLabel: tag] as [CFString: Any] as CFDictionary, nil)
        guard status == errSecSuccess else { delete(tag: tag, commonName: cn); throw Failure.addCertificate(status) }
        do {
            let identity = try lookup(der: der)
            return SpikeIdentity(identity: identity, certificateDER: der, tag: tag, commonName: cn)
        } catch { delete(tag: tag, commonName: cn); throw error }
    }

    /// 以憑證 DER 比對取回 SecIdentity（不依賴 label 是否被帶到 identity 查詢）
    static func lookup(der: Data) throws -> SecIdentity {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassIdentity, kSecReturnRef: true,
                                          kSecMatchLimit: kSecMatchLimitAll] as [CFString: Any] as CFDictionary, &result)
        guard status == errSecSuccess, let all = result as? [SecIdentity] else { throw Failure.identityNotFound(status) }
        for identity in all {
            var certificate: SecCertificate?
            if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
               SecCertificateCopyData(certificate) as Data == der {
                return identity
            }
        }
        throw Failure.identityNotFound(errSecItemNotFound)
    }

    public func privateKey() -> SecKey? {
        var key: SecKey?
        return SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess ? key : nil
    }

    public func remove() { Self.delete(tag: tag, commonName: commonName) }

    static func delete(tag: String, commonName: String) {
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: commonName] as [CFString: Any] as CFDictionary)
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(tag.utf8)] as [CFString: Any] as CFDictionary)
    }

    /// 測後確認沒有殘留
    public static func residue(tag: String, commonName: String) -> Int {
        var count = 0
        for query: [CFString: Any] in [[kSecClass: kSecClassCertificate, kSecAttrLabel: commonName],
                                       [kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(tag.utf8)]] {
            var q = query
            q[kSecMatchLimit] = kSecMatchLimitAll
            q[kSecReturnRef] = true
            var r: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess { count += (r as? [Any])?.count ?? 1 }
        }
        return count
    }
}
