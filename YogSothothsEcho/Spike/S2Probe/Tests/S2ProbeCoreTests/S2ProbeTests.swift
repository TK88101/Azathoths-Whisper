import CryptoKit
import Foundation
import Network
import Security
import Testing
@testable import S2ProbeCore

/// 不進 Keychain 的暫時金鑰（只供 DER 形狀測試）
private func ephemeralKey() -> SecKey {
    SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                           kSecAttrKeySizeInBits: 256] as [CFString: Any] as CFDictionary, nil)!
}

private func x963(_ key: SecKey) -> Data {
    SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!, nil)! as Data
}

/// 外層 Certificate SEQUENCE 拆出 tbs、signature（長度 < 64 KiB 的兩位元組長式）
private func split(_ der: [UInt8]) -> (tbs: [UInt8], signature: [UInt8]) {
    func header(_ at: Int) -> (contentStart: Int, length: Int) {
        let first = der[at + 1]
        if first < 0x80 { return (at + 2, Int(first)) }
        let n = Int(first & 0x7F)
        var length = 0
        for i in 0..<n { length = length << 8 | Int(der[at + 2 + i]) }
        return (at + 2 + n, length)
    }
    let outer = header(0)
    let tbsHeader = header(outer.contentStart)
    let tbsEnd = tbsHeader.contentStart + tbsHeader.length
    let tbs = Array(der[outer.contentStart..<tbsEnd])
    let algHeader = header(tbsEnd)
    let bitString = header(algHeader.contentStart + algHeader.length)
    let signature = Array(der[(bitString.contentStart + 1)..<(bitString.contentStart + bitString.length)])
    return (tbs, signature)
}

@Suite("S2-P2 MiniCert") struct MiniCertTests {
    @Test func tbsLengthIsFixedAcrossKeysAndSerials() {
        let lengths = Set((0..<20).map { _ -> Int in
            var r = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, 16, &r)
            return MiniCert.tbs(publicKey: Array(x963(ephemeralKey())), serial: MiniCert.serial(r),
                                commonName: "yse-" + String(repeating: "a", count: 32), notBefore: Date()).count
        })
        #expect(lengths.count == 1)
    }

    @Test func serialIsPositiveNonZeroLeading() {
        for first: UInt8 in [0x00, 0x80, 0xFF, 0x7F] {
            let s = MiniCert.serial([first] + [UInt8](repeating: 0, count: 15))
            #expect(s.count == 16 && s[0] >= 0x01 && s[0] <= 0x7F)
        }
    }

    @Test func appleSecurityParsesAndKeyMatches() throws {
        let key = ephemeralKey()
        let cn = "yse-" + String(repeating: "b", count: 32)
        let der = try MiniCert.make(privateKey: key, commonName: cn)
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        let parsedKey = try #require(SecCertificateCopyKey(certificate))
        #expect(SecKeyCopyExternalRepresentation(parsedKey, nil)! as Data == x963(key))
        #expect(SecCertificateCopySubjectSummary(certificate) as String? == cn)
    }

    @Test func signatureVerifiesIndependentlyWithCryptoKit() throws {
        let key = ephemeralKey()
        let der = try MiniCert.make(privateKey: key, commonName: "yse-" + String(repeating: "c", count: 32))
        let parts = split(Array(der))
        let publicKey = try P256.Signing.PublicKey(x963Representation: x963(key))
        let signature = try P256.Signing.ECDSASignature(derRepresentation: parts.signature)
        #expect(publicKey.isValidSignature(signature, for: Data(parts.tbs)))
    }

    #if os(macOS)
    @Test func opensslParsesAllFields() throws {
        let der = try MiniCert.make(privateKey: ephemeralKey(), commonName: "yse-" + String(repeating: "d", count: 32))
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
        print("[S2-P2 openssl]\n" + text)
        #expect(process.terminationStatus == 0)
        for needle in ["Version: 3", "ecdsa-with-SHA256", "prime256v1", "CA:FALSE", "Digital Signature",
                       "TLS Web Server Authentication", "TLS Web Client Authentication", "Dec 31 23:59:59 9999 GMT"] {
            #expect(text.contains(needle), "missing \(needle)")
        }
    }
    #endif
}

@Suite("S2-P1/P2 Keychain＋TLS", .serialized) struct KeychainTLSTests {
    @Test func keychainRoundTripAndCleanup() throws {
        let identity = try SpikeIdentity.create(name: "roundtrip")
        let key = try #require(identity.privateKey())
        let certificate = try #require(SecCertificateCreateWithData(nil, identity.certificateDER as CFData))
        #expect(SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!, nil)! as Data
                == SecKeyCopyExternalRepresentation(SecCertificateCopyKey(certificate)!, nil)! as Data)
        identity.remove()
        #expect(SpikeIdentity.residue(tag: identity.tag, commonName: identity.commonName) == 0)
    }

    struct Pair { let server: SpikeIdentity; let client: SpikeIdentity; let other: SpikeIdentity }
    func withPair(_ body: (Pair) async throws -> Void) async throws {
        let pair = Pair(server: try SpikeIdentity.create(name: "server"), client: try SpikeIdentity.create(name: "client"),
                        other: try SpikeIdentity.create(name: "other"))
        defer {
            for i in [pair.server, pair.client, pair.other] { i.remove(); #expect(SpikeIdentity.residue(tag: i.tag, commonName: i.commonName) == 0) }
        }
        try await body(pair)
    }

    func clientParameters(_ p: Pair, expecting: Data, settings: TLSSettings, count: Box<Int>) -> NWParameters {
        TLSProbe.parameters(identity: p.client.identity, expecting: expecting, settings: settings,
                            requirePeer: false, verifyCount: count, verifyAccepted: Box([]))
    }

    @Test func mutualTLSWithGeneratedIdentitiesAndExporter() async throws {
        try await withPair { p in
            let settings = TLSSettings(disableTicketsAndResumption: true)
            let server = try TLSProbe.Server(identity: p.server.identity, expecting: p.client.fingerprint, settings: settings)
            defer { server.stop() }
            let port = try await server.start()
            let count = Box(0)
            let first = await TLSProbe.connect(port: port, parameters: clientParameters(p, expecting: p.server.fingerprint,
                                                                                      settings: settings, count: count), server: server)
            let second = await TLSProbe.connect(port: port, parameters: clientParameters(p, expecting: p.server.fingerprint,
                                                                                       settings: settings, count: count), server: server)
            print("[S2-P1/P2 mTLS] first=\(first) second=\(second) clientVerify=\(count.value) serverVerify=\(server.verifyCount.value) serverAccepted=\(server.verifyAccepted.value)")
            #expect(first.echoed && second.echoed)
            #expect(server.verifyAccepted.value == [true, true])
            #expect(first.clientExporter?.count == 32)
            #expect(first.clientExporter == first.serverExporter)
            #expect(second.clientExporter == second.serverExporter)
            #expect(first.clientExporter != second.clientExporter)
        }
    }

    @Test(arguments: ["client", "server"]) func pinMismatchIsRejected(side: String) async throws {
        try await withPair { p in
            let settings = TLSSettings(disableTicketsAndResumption: true)
            let server = try TLSProbe.Server(identity: p.server.identity,
                                             expecting: side == "server" ? p.other.fingerprint : p.client.fingerprint,
                                             settings: settings)
            defer { server.stop() }
            let port = try await server.start()
            let outcome = await TLSProbe.connect(port: port, parameters: clientParameters(
                p, expecting: side == "client" ? p.other.fingerprint : p.server.fingerprint, settings: settings, count: Box(0)),
                server: server, timeout: 2)
            try? await Task.sleep(for: .milliseconds(500))
            print("[S2-P2 mismatch \(side)] \(outcome) serverReceived=\(server.received.value)")
            #expect(!outcome.echoed)
            #expect(server.received.value == 0)
        }
    }

    /// 安全問題本體：第 1 條連線用正確 pin 建立後，第 2 條連線若改成「錯誤 pin」，是否仍能連上？
    /// 能連上＝resumption 跳過了指紋驗證（繞過）。分別看預設設定與關閉 tickets／resumption。
    @Test(arguments: [false, true]) func resumptionCannotBypassPin(disabled: Bool) async throws {
        try await withPair { p in
            let settings = TLSSettings(disableTicketsAndResumption: disabled)
            let server = try TLSProbe.Server(identity: p.server.identity, expecting: p.client.fingerprint, settings: settings)
            defer { server.stop() }
            let port = try await server.start()
            let count = Box(0)
            let first = await TLSProbe.connect(port: port, parameters: clientParameters(p, expecting: p.server.fingerprint,
                                                                                      settings: settings, count: count), server: server)
            let afterFirst = count.value
            let wrong = Box(0)
            let second = await TLSProbe.connect(port: port, parameters: clientParameters(p, expecting: p.other.fingerprint,
                                                                                       settings: settings, count: wrong), server: server, timeout: 2)
            print("[S2-P1 resumption disabled=\(disabled)] first=\(first) clientVerify1=\(afterFirst) second(wrong pin)=\(second) clientVerify2=\(wrong.value) serverVerify=\(server.verifyCount.value)")
            #expect(first.echoed)
            if disabled { #expect(!second.echoed && wrong.value == 1) }
        }
    }
}
