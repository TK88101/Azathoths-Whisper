import Foundation
import S2ProbeCore
import Security

// S2-P3：ad-hoc 簽名的程式重新建置（CDHash 改變）後，讀 legacy 鑰匙圈私鑰是否跳授權框。
// 用法：s2-keyprobe create|use|delete。只碰 label＝yse-s2-spike.p3 的條目。
let tag = "yse-s2-spike.p3"
// macOS 舊式鑰匙圈加憑證時忽略 kSecAttrLabel，label 一律＝CN（2026-10-15 實測）；以 CN 查找
let commonName = "yse-" + String(repeating: "0", count: 32)
#if VARIANT_B
let variant = "B"
#else
let variant = "A"
#endif

func certificate() -> SecCertificate? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching([kSecClass: kSecClassCertificate, kSecAttrLabel: commonName,
                                      kSecReturnRef: true] as [CFString: Any] as CFDictionary, &result)
    return status == errSecSuccess ? (result as! SecCertificate) : nil
}

switch CommandLine.arguments.dropFirst().first {
case "create":
    guard certificate() == nil else { print("exists"); exit(1) }
    let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits: 256,
        kSecPrivateKeyAttrs: [kSecAttrIsPermanent: true, kSecAttrLabel: tag,
                              kSecAttrApplicationTag: Data(tag.utf8)] as [CFString: Any],
    ]
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
          let der = try? MiniCert.make(privateKey: key, commonName: commonName),
          let cert = SecCertificateCreateWithData(nil, der as CFData) else { print("create failed"); exit(1) }
    let status = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: cert, kSecAttrLabel: tag]
                            as [CFString: Any] as CFDictionary, nil)
    print("variant=\(variant) create status=\(status)")
case "use":
    guard let cert = certificate() else { print("no certificate"); exit(1) }
    var identity: SecIdentity?
    let found = SecIdentityCreateWithCertificate(nil, cert, &identity)
    var key: SecKey?
    guard found == errSecSuccess, let identity, SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key else {
        print("variant=\(variant) identity status=\(found)"); exit(1)
    }
    let start = Date()
    var error: Unmanaged<CFError>?
    let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, Data("probe".utf8) as CFData, &error)
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print("variant=\(variant) sign ok=\(signature != nil) elapsed_ms=\(ms) error=\(String(describing: error?.takeRetainedValue()))")
case "delete":
    let a = SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: commonName] as [CFString: Any] as CFDictionary)
    let b = SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(tag.utf8)] as [CFString: Any] as CFDictionary)
    print("delete cert=\(a) key=\(b)")
default:
    print("usage: s2-keyprobe create|use|delete"); exit(2)
}
