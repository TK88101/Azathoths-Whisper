import CryptoKit
import Foundation
import Security
import Testing
@testable import RemoteTransport

// S2 T3（sprint-2-detail.md §4.3）：MiniCert 封閉 profile、DeviceIdentity、InMemory 身分庫

private func ephemeralKey() -> SecKey {
    SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                           kSecAttrKeySizeInBits: 256] as [CFString: Any] as CFDictionary, nil)!
}

private func x963(_ key: SecKey) -> Data {
    SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!, nil)! as Data
}

private let goodCN = "yse-" + String(repeating: "a", count: 32)

struct MiniCertTests {
    @Test func tbsLengthIsTheProfileConstant() throws {
        for _ in 0..<20 {
            let der = try MiniCert.make(privateKey: ephemeralKey(), commonName: goodCN)
            #expect(MiniCert.split(der)?.tbs.count == MiniCert.tbsLength)
        }
    }

    @Test func rejectsCommonNameOutsideProfile() {
        for bad in ["yse-", "YSE-" + String(repeating: "a", count: 32), "yse-" + String(repeating: "A", count: 32),
                    "yse-" + String(repeating: "a", count: 31), "other"] {
            #expect(throws: MiniCert.Failure.self) { try MiniCert.make(privateKey: ephemeralKey(), commonName: bad) }
        }
    }

    @Test func appleSecurityParsesAndKeyMatches() throws {
        let key = ephemeralKey()
        let der = try MiniCert.make(privateKey: key, commonName: goodCN)
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        #expect(SecKeyCopyExternalRepresentation(SecCertificateCopyKey(certificate)!, nil)! as Data == x963(key))
        #expect(SecCertificateCopySubjectSummary(certificate) as String? == goodCN)
    }

    @Test func signatureVerifiesIndependentlyWithCryptoKit() throws {
        let key = ephemeralKey()
        let parts = try #require(MiniCert.split(try MiniCert.make(privateKey: key, commonName: goodCN)))
        let publicKey = try P256.Signing.PublicKey(x963Representation: x963(key))
        #expect(publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: parts.signature), for: parts.tbs))
    }

    @Test func serialIsPositiveNonZeroLeading() {
        for first: UInt8 in [0x00, 0x80, 0xFF, 0x7F] {
            let serial = MiniCert.serial([first] + [UInt8](repeating: 0, count: 15))
            #expect(serial.count == 16 && serial[0] >= 0x01 && serial[0] <= 0x7F)
        }
    }

    #if os(macOS)
    @Test func opensslParsesProfileFields() throws {
        let der = try MiniCert.make(privateKey: ephemeralKey(), commonName: goodCN)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("c.der")
        try der.write(to: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["x509", "-inform", "DER", "-in", file.path, "-noout", "-text"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        for needle in ["Version: 3", "ecdsa-with-SHA256", "prime256v1", "CA:FALSE", "Digital Signature",
                       "TLS Web Server Authentication", "TLS Web Client Authentication", "Dec 31 23:59:59 9999 GMT",
                       "CN=\(goodCN)"] {
            #expect(text.contains(needle), "missing \(needle)")
        }
    }

    @Test func testIdentityFactoryMakesUsableIdentityWithoutKeychain() throws {
        let identity = try TestIdentityFactory.make()
        #expect(identity.fingerprint == Fingerprint(der: identity.certificateDER))
        var key: SecKey?
        #expect(SecIdentityCopyPrivateKey(identity.secIdentity, &key) == errSecSuccess)
        let certificate = try #require(SecCertificateCreateWithData(nil, identity.certificateDER as CFData))
        #expect(SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key!)!, nil)! as Data
                == SecKeyCopyExternalRepresentation(SecCertificateCopyKey(certificate)!, nil)! as Data)
    }

    @Test func inMemoryStoreReturnsInjectedIdentityAndWarmUpResult() async throws {
        let first = try TestIdentityFactory.make()
        let second = try TestIdentityFactory.make()
        let store = InMemoryDeviceIdentityStore(identities: [first, second], warmUpResult: .failure(.keychainDenied))
        #expect(try store.loadOrCreate().fingerprint == first.fingerprint)
        #expect(try store.loadOrCreate().fingerprint == first.fingerprint)
        await #expect(throws: IdentityError.keychainDenied) { try await store.warmUp() }
        try store.reset()
        #expect(try store.loadOrCreate().fingerprint == second.fingerprint)
    }
    #endif
}
