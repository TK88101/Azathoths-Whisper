import Foundation
@_spi(Testing) import RemoteTransport
import Security
import Testing
@testable import YogSothothsEcho

// S2 T7（iPad hosted；sprint-2-detail.md §4.3、CR-010 ⑪）：模擬器 Keychain 上的身分建立、部分遺失重建、清理後 0 殘留
@Suite(.serialized) struct KeychainIdentitySmokeTests {
    let service = "com.ibridgezhao.yse.test." + UUID().uuidString.prefix(8).lowercased()
    let suite = "yse.test.identity." + UUID().uuidString

    func store(audit: any AuditSink = NoopAuditSink(), lookups: any KeychainLookups = LiveKeychainLookups()) -> KeychainDeviceIdentityStore {
        KeychainDeviceIdentityStore(service: service, defaultsSuite: suite, audit: audit, lookups: lookups)
    }

    var storedCN: String? { UserDefaults(suiteName: suite)?.string(forKey: service + ".cn") }

    func certificateExists(_ cn: String) -> Bool {
        SecItemCopyMatching([kSecClass: kSecClassCertificate, kSecAttrLabel: cn] as [CFString: Any] as CFDictionary, nil) == errSecSuccess
    }

    func keyExists() -> Bool {
        SecItemCopyMatching([kSecClass: kSecClassKey, kSecAttrApplicationTag: Data((service + ".key").utf8)]
                            as [CFString: Any] as CFDictionary, nil) == errSecSuccess
    }

    @Test func createLoadWarmUpAndCleanUp() async throws {
        let first = try store().loadOrCreate()
        let cn = try #require(storedCN)
        #expect(try store().loadOrCreate().fingerprint == first.fingerprint)
        try await store().warmUp()
        #expect(certificateExists(cn) && keyExists())
        try store().reset()
        #expect(!certificateExists(cn) && !keyExists())
    }

    /// security review S2 LOW-4：私鑰與憑證只留在本機（不隨備份或移機轉到別台裝置——每台 iPad 各自一個身分，CR-010 ③）
    @Test func identityStaysOnThisDevice() throws {
        _ = try store().loadOrCreate()
        let cn = try #require(storedCN)
        func accessible(_ query: [CFString: Any]) -> String? {
            var result: CFTypeRef?
            var q = query
            q[kSecReturnAttributes] = true
            guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
                  let attributes = result as? [CFString: Any] else { return nil }
            return attributes[kSecAttrAccessible] as? String
        }
        let thisDevice = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        #expect(accessible([kSecClass: kSecClassKey, kSecAttrApplicationTag: Data((service + ".key").utf8)]) == thisDevice)
        #expect(accessible([kSecClass: kSecClassCertificate, kSecAttrLabel: cn]) == thisDevice)
        try store().reset()
    }

    @Test func partialKeychainLossRebuildsAndInvalidatesTrust() throws {
        let audit = SpyAuditSink()
        let original = try store().loadOrCreate()
        let oldCN = try #require(storedCN)
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: oldCN] as [CFString: Any] as CFDictionary)
        let rebuilt = try store(audit: audit).loadOrCreate()
        let newCN = try #require(storedCN)
        #expect(rebuilt.fingerprint != original.fingerprint)
        #expect(audit.events.contains(.identityReset))
        try store().reset()
        #expect(!certificateExists(oldCN) && !certificateExists(newCN) && !keyExists())
    }

    // MARK: R7（r7-identity-transient.md §6 T0、T10a–c）：iOS 分支——鑰匙圈讀不到時不刪身分、配對仍有效

    #if DEBUG   // FaultyKeychainLookups 只在 DEBUG 編入
    /// 身分列舉只有第 1 次回指定結果，之後轉真鑰匙圈
    func faultyIdentity(_ status: OSStatus, result: CFTypeRef? = nil) -> FaultyKeychainLookups {
        let lookups = FaultyKeychainLookups()
        lookups.fail(.identity, status: status, result: result)
        return lookups
    }

    @Test func unreadableIdentityEnumerationKeepsIdentity() throws {
        defer { try? store().reset() }
        let original = try store().loadOrCreate()
        let cn = try #require(storedCN)
        let audit = SpyAuditSink()
        let faulty = store(audit: audit, lookups: faultyIdentity(errSecInteractionNotAllowed))
        #expect(throws: IdentityError.keychainUnavailable(errSecInteractionNotAllowed)) { try faulty.loadOrCreate() }
        #expect(certificateExists(cn) && keyExists() && storedCN == cn)
        #expect(!audit.events.contains(.identityReset))
        #expect(try faulty.loadOrCreate().fingerprint == original.fingerprint)
    }

    /// 列舉成功卻沒有相符的身分＝資料不一致，不當成不存在（R7 R-d）
    @Test func enumerationWithoutMatchIsUnreadable() throws {
        defer { try? store().reset() }
        _ = try store().loadOrCreate()
        let cn = try #require(storedCN)
        #expect(throws: IdentityError.keychainUnavailable(errSecInternalError)) {
            try store(lookups: faultyIdentity(errSecSuccess, result: [] as CFArray)).loadOrCreate()
        }
        #expect(certificateExists(cn) && keyExists() && storedCN == cn)
    }

    /// 讀不到的那一輪看不到配對，但身分與信任紀錄都保留，下一輪恢復
    @Test func pairedMacSurvivesUnreadableKeychain() throws {
        defer { try? store().reset() }
        let trust = InMemoryTrustStore()
        let identity = try store().loadOrCreate()
        let cn = try #require(storedCN)
        try trust.add(PeerRecord(peerID: UUID(), fingerprint: Fingerprint(bytes: Data(repeating: 9, count: 32))!,
                                 localFingerprint: identity.fingerprint, name: "Mac", pairedAt: Date()))
        func connector(_ identityStore: any DeviceIdentityStore) -> LiveRemoteConnector {
            LiveRemoteConnector(identityStore: identityStore, trust: trust, discover: { _, _ in [] }, makeAttempts: { _ in FakeMacAttempts() })
        }
        #expect(!connector(store(lookups: faultyIdentity(errSecInteractionNotAllowed))).hasPairedMac)
        #expect(certificateExists(cn) && keyExists() && storedCN == cn)
        #expect(connector(store()).hasPairedMac)
    }
    #endif
}

@MainActor
struct ConnectionPresentationTests {
    @Test func everyFailureHasAMessageAndStateIDsAreDistinct() {
        let states: [ConnectionViewModel.State] = [.unpaired(.scanning), .unpaired(.cameraDenied), .pairing, .connecting,
                                                   .connected(macName: "x"), .retrying(inSeconds: 1), .needsRepair, .suspended,
                                                   .pairingFailed(.rejected)]
        #expect(Set(states.map(ConnectionPresentation.stateID)).count == states.count)
        // 同義的失敗共用一句，其餘各自一句（使用者要能分辨「被拒」「過期」「不是這台」「找不到」「連不上」）
        let message = ConnectionPresentation.failureMessage
        #expect(message(.expired) == message(.unavailable))
        #expect(message(.notOnLink) == message(.network) && message(.network) == message(.timeout))
        let distinct: [PairingFailure] = [.rejected, .expired, .cancelled, .invalid, .macPinMismatch, .notFound, .network]
        for (i, a) in distinct.enumerated() {
            for b in distinct[(i + 1)...] { #expect(message(a) != message(b), "\(a) 與 \(b) 不應同一句") }
        }
    }
}
