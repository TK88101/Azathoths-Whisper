import Foundation
import Security
import Testing
@testable import RemoteTransport

// S2 T7（sprint-2-detail.md §4.3、CR-010 ⑪）：真 Keychain 冒煙。每個測試用專屬 service；
// teardown 以 CN（macOS 舊式鑰匙圈 label＝CN）與 application tag 刪除，並以 `security` 獨立核對 0 殘留。

#if os(macOS)
func securityFindsCertificate(named cn: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-certificate", "-a", "-c", cn]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("\"labl\"")
}

func keyExists(tag: String) -> Bool {
    SecItemCopyMatching([kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(tag.utf8)] as [CFString: Any] as CFDictionary, nil)
        == errSecSuccess
}

/// 碰真鑰匙圈的 suite 都收在這裡：同一行程內並行寫舊式鑰匙圈會互相干擾（實測回 -67671、甚至假的 -25300），
/// 不得與其他鑰匙圈 suite 同時跑（R7 實作紀錄）
@Suite(.serialized) struct KeychainSerialized {}

extension KeychainSerialized {
@Suite(.serialized) struct KeychainIdentitySmokeTests {
    let service = "com.ibridgezhao.yse.test." + UUID().uuidString.prefix(8).lowercased()
    let suite = "yse.test.identity." + UUID().uuidString

    func store(audit: any AuditSink = NoopAuditSink()) -> KeychainDeviceIdentityStore {
        KeychainDeviceIdentityStore(service: service, defaultsSuite: suite, audit: audit)
    }

    /// 測後清理並獨立核對；回傳是否乾淨
    func cleanUp(_ names: [String]) -> Bool {
        try? store().reset()
        return names.allSatisfy { !securityFindsCertificate(named: $0) } && !keyExists(tag: store().keyTag)
    }

    @Test func createLoadIsStableAndCleansUp() async throws {
        let first = try store().loadOrCreate()
        let cn = try #require(store().currentCommonName)
        let again = try store().loadOrCreate()
        #expect(first.fingerprint == again.fingerprint)
        #expect(securityFindsCertificate(named: cn))
        try await store().warmUp()
        #expect(cleanUp([cn]))
    }

    @Test func partialKeychainLossInvalidatesAllTrust() throws {
        let audit = SpyAuditSink()
        let original = try store().loadOrCreate()
        let oldCN = try #require(store().currentCommonName)
        let trust = InMemoryTrustStore()
        try trust.add(PeerRecord(peerID: UUID(), fingerprint: Fingerprint(bytes: Data(repeating: 1, count: 32))!,
                                 localFingerprint: original.fingerprint, name: "iPad", pairedAt: Date()))
        // 模擬部分遺失：只刪憑證、留私鑰
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: oldCN] as [CFString: Any] as CFDictionary)
        let rebuilt = try store(audit: audit).loadOrCreate()
        let newCN = try #require(store().currentCommonName)
        #expect(rebuilt.fingerprint != original.fingerprint)
        #expect(trust.validRecords(for: rebuilt.fingerprint).isEmpty)
        #expect(audit.events.contains(.identityReset))
        #expect(!securityFindsCertificate(named: oldCN))
        #expect(cleanUp([oldCN, newCN]))
    }

    @Test func resetProducesNewIdentity() throws {
        let first = try store().loadOrCreate()
        let firstCN = try #require(store().currentCommonName)
        try store().reset()
        #expect(!securityFindsCertificate(named: firstCN))
        let second = try store().loadOrCreate()
        let secondCN = try #require(store().currentCommonName)
        #expect(first.fingerprint != second.fingerprint)
        #expect(cleanUp([firstCN, secondCN]))
    }

    @Test func identityFromKeychainWorksForMutualTLS() async throws {
        let macIdentity = try store().loadOrCreate()
        let cn = try #require(store().currentCommonName)
        let server = TransportServer(configuration: ServerConfiguration(
            identity: macIdentity, trust: InMemoryTrustStore(), audit: NoopAuditSink(), serviceName: nil,
            interfaces: { [] }, timings: .test, limits: .relaxedForTests))
        let port = try await server.start()
        let payload = server.openPairingWindow()
        let client = TransportClient(configuration: ClientConfiguration(identity: try TestIdentityFactory.make(), trust: InMemoryTrustStore(),
                                                                        audit: NoopAuditSink(), interfaces: { [] }, timings: .test))
        async let result = client.pair(endpoint: .url(URL(string: "wss://127.0.0.1:\(port.rawValue)/")!), payload: payload, deviceName: "x")
        let deadline = Date().addingTimeInterval(3)
        while server.pendingPairing == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        server.approvePairing()
        if case .approved = await result {} else { Issue.record("pairing with keychain identity failed") }
        server.stop()
        #expect(cleanUp([cn]))
    }
}
}
#endif
