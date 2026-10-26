import Foundation
import Security
import Testing
@_spi(Testing) @testable import RemoteTransport

// R7（docs/plans/2026-10-14-yse/r7-identity-transient.md §6 T2–T5b）：鑰匙圈「讀不到」不得刪除重建本機身分；
// 只有明確的 errSecItemNotFound 才重建。真鑰匙圈＋逐次注入的讀取結果；清理方式同 KeychainIdentitySmokeTests。

// FaultyKeychainLookups 只在 DEBUG 編入（Release 不帶測試替身）
#if os(macOS) && DEBUG
extension KeychainSerialized {
@Suite(.serialized) struct KeychainIdentityTransientTests {
    let service = "com.ibridgezhao.yse.test." + UUID().uuidString.prefix(8).lowercased()
    let suite = "yse.test.identity." + UUID().uuidString

    func store(audit: any AuditSink = NoopAuditSink(), lookups: any KeychainLookups = LiveKeychainLookups()) -> KeychainDeviceIdentityStore {
        KeychainDeviceIdentityStore(service: service, defaultsSuite: suite, audit: audit, lookups: lookups, missingConfirmDelay: 0)
    }

    func faulty(_ faults: (FaultyKeychainLookups.Query, OSStatus)...) -> FaultyKeychainLookups {
        let lookups = FaultyKeychainLookups()
        for (query, status) in faults { lookups.fail(query, status: status) }
        return lookups
    }

    /// 測試中途中止（#require 失敗）也要清掉目前 CN 的項目，不在登入鑰匙圈留殘留
    func discardOnExit() {
        try? store().reset()
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func cleanUp(_ names: [String]) -> Bool {
        try? store().reset()
        return names.allSatisfy { !securityFindsCertificate(named: $0) } && !keyExists(tag: store().keyTag)
    }

    /// 讀不到：throw 指定錯誤；憑證、私鑰、CN 都在；無 identityReset；之後讀到原身分
    func expectPreserved(_ lookups: FaultyKeychainLookups, throws expected: IdentityError) throws {
        defer { discardOnExit() }
        let original = try store().loadOrCreate()
        let cn = try #require(store().currentCommonName)
        let audit = SpyAuditSink()
        #expect(throws: expected) { try store(audit: audit, lookups: lookups).loadOrCreate() }
        #expect(store().currentCommonName == cn)
        #expect(securityFindsCertificate(named: cn) && keyExists(tag: store().keyTag))
        #expect(!audit.events.contains(.identityReset))
        #expect(try store().loadOrCreate().fingerprint == original.fingerprint)
        #expect(cleanUp([cn]))
    }

    @Test func unreadableKeyKeepsIdentity() throws {
        try expectPreserved(faulty((.key, errSecInteractionNotAllowed)), throws: .keychainUnavailable(errSecInteractionNotAllowed))
    }

    @Test func unreadableCertificateKeepsIdentity() throws {
        try expectPreserved(faulty((.certificate, errSecInteractionNotAllowed)), throws: .keychainUnavailable(errSecInteractionNotAllowed))
    }

    @Test func certificateSuccessWithoutResultIsUnreadable() throws {
        try expectPreserved(faulty((.certificate, errSecSuccess)), throws: .keychainUnavailable(errSecInternalError))
    }

    @Test func unreadableIdentityKeepsIdentity() throws {
        try expectPreserved(faulty((.identity, errSecInteractionNotAllowed)), throws: .keychainUnavailable(errSecInteractionNotAllowed))
    }

    @Test func userCanceledMapsToDenied() throws {
        try expectPreserved(faulty((.key, errSecUserCanceled)), throws: .keychainDenied)
    }

    /// 一半 NotFound、一半讀不到：無法下結論＝不刪
    @Test func missingCertificateWithUnreadableKeyKeepsIdentity() throws {
        try expectPreserved(faulty((.certificate, errSecItemNotFound), (.key, errSecInteractionNotAllowed)),
                            throws: .keychainUnavailable(errSecInteractionNotAllowed))
    }

    /// 兩半都讀不到：回憑證那一半的 status
    @Test func bothUnreadableReportsCertificateStatus() throws {
        try expectPreserved(faulty((.certificate, errSecInteractionNotAllowed), (.key, errSecNotAvailable)),
                            throws: .keychainUnavailable(errSecInteractionNotAllowed))
    }

    /// 前 2 次 NotFound（間隔後從頭再查仍是，之後轉真鑰匙圈）：確認不完整 → 重建，且重建後的讀回正常（R7 §11）
    @Test(arguments: [FaultyKeychainLookups.Query.certificate, .identity])
    func explicitNotFoundRebuilds(query: FaultyKeychainLookups.Query) throws {
        defer { discardOnExit() }
        let original = try store().loadOrCreate()
        let oldCN = try #require(store().currentCommonName)
        let audit = SpyAuditSink()
        let lookups = FaultyKeychainLookups()
        lookups.fail(query, times: 2, status: errSecItemNotFound)
        let rebuilt = try store(audit: audit, lookups: lookups).loadOrCreate()
        let newCN = try #require(store().currentCommonName)
        #expect(rebuilt.fingerprint != original.fingerprint)
        #expect(newCN != oldCN)
        #expect(!securityFindsCertificate(named: oldCN))
        #expect(audit.events.filter { $0 == .identityReset }.count == 1)
        #expect(cleanUp([oldCN, newCN]))
    }

    // MARK: 刪除前兩次確認（R7 §11）

    /// 只有第 1 次 NotFound（之後讀得到）：當成暫態，不刪、不重建
    @Test func singleNotFoundDoesNotRebuild() throws {
        defer { discardOnExit() }
        let original = try store().loadOrCreate()
        let cn = try #require(store().currentCommonName)
        let audit = SpyAuditSink()
        let loaded = try store(audit: audit, lookups: faulty((.certificate, errSecItemNotFound))).loadOrCreate()
        #expect(loaded.fingerprint == original.fingerprint)
        #expect(store().currentCommonName == cn)
        #expect(securityFindsCertificate(named: cn) && keyExists(tag: store().keyTag))
        #expect(!audit.events.contains(.identityReset))
        #expect(cleanUp([cn]))
    }

    /// 兩次判定之間另一個 store 已建好新身分：第二次重讀 CN 拿到新身分，不得以舊 CN 刪掉共享 tag 的新私鑰
    @Test func secondCheckRereadsCommonName() throws {
        defer { discardOnExit() }
        _ = try store().loadOrCreate()
        let oldCN = try #require(store().currentCommonName)
        let rebuilder = RebuildOnFirstCertificateLookup { _ = try? self.store().reset(); return try? self.store().loadOrCreate() }
        let audit = SpyAuditSink()
        let loaded = try store(audit: audit, lookups: rebuilder).loadOrCreate()
        let newCN = try #require(store().currentCommonName)
        #expect(newCN != oldCN)
        #expect(loaded.fingerprint == rebuilder.rebuilt?.fingerprint)
        #expect(!audit.events.contains(.identityReset))
        #expect(securityFindsCertificate(named: newCN) && keyExists(tag: store().keyTag))
        #expect(cleanUp([oldCN, newCN]))
    }

    /// 空檔中 CN 換成新身分 Y，而第二次查 Y 又回 NotFound：對 Y 只看到一次，不得刪 Y（security review R7 §11 MEDIUM）
    @Test func changedCommonNameIsNotDeletedOnSingleNotFound() throws {
        defer { discardOnExit() }
        _ = try store().loadOrCreate()
        let oldCN = try #require(store().currentCommonName)
        let rebuilder = RebuildOnFirstCertificateLookup(notFoundCount: 2) { _ = try? self.store().reset(); return try? self.store().loadOrCreate() }
        let audit = SpyAuditSink()
        #expect(throws: IdentityError.keychainUnavailable(errSecItemNotFound)) { try self.store(audit: audit, lookups: rebuilder).loadOrCreate() }
        let newCN = try #require(store().currentCommonName)
        #expect(newCN != oldCN)
        #expect(securityFindsCertificate(named: newCN) && keyExists(tag: store().keyTag))
        #expect(!audit.events.contains(.identityReset))
        #expect(try store().loadOrCreate().fingerprint == rebuilder.rebuilt?.fingerprint)
        #expect(cleanUp([oldCN, newCN]))
    }

    /// 剛建好的身分讀回時讀不到：不刪、保留 CN；下次讀到即恢復，不重建
    @Test func unreadableReadBackAfterCreateKeepsNewItems() throws {
        defer { discardOnExit() }
        let audit = SpyAuditSink()
        #expect(throws: IdentityError.keychainUnavailable(errSecInteractionNotAllowed)) {
            try store(audit: audit, lookups: faulty((.identity, errSecInteractionNotAllowed))).loadOrCreate()
        }
        let cn = try #require(store().currentCommonName)
        #expect(securityFindsCertificate(named: cn) && keyExists(tag: store().keyTag))
        _ = try store(audit: audit).loadOrCreate()
        #expect(store().currentCommonName == cn)
        #expect(!audit.events.contains(.identityReset))
        #expect(cleanUp([cn]))
    }

    // MARK: 唯讀查詢

    @Test func existingFingerprintNeverCreates() throws {
        defer { discardOnExit() }
        #expect(try store().existingFingerprint() == nil)
        #expect(store().currentCommonName == nil)
        #expect(!keyExists(tag: store().keyTag))
    }

    @Test func existingFingerprintMatchesLoadedIdentity() throws {
        defer { discardOnExit() }
        let identity = try store().loadOrCreate()
        let cn = try #require(store().currentCommonName)
        #expect(try store().existingFingerprint() == identity.fingerprint)
        #expect(cleanUp([cn]))
    }

    /// 部分遺失時唯讀查詢回 nil，但不清殘餘、不稽核（重建只在 loadOrCreate）
    @Test func existingFingerprintLeavesPartialLossAlone() throws {
        defer { discardOnExit() }
        _ = try store().loadOrCreate()
        let cn = try #require(store().currentCommonName)
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: cn] as [CFString: Any] as CFDictionary)
        let audit = SpyAuditSink()
        #expect(try store(audit: audit).existingFingerprint() == nil)
        #expect(keyExists(tag: store().keyTag))
        #expect(store().currentCommonName == cn)
        #expect(audit.events.isEmpty)
        #expect(cleanUp([cn]))
    }

    @Test func existingFingerprintThrowsWhenUnreadable() throws {
        defer { discardOnExit() }
        _ = try store().loadOrCreate()
        let cn = try #require(store().currentCommonName)
        #expect(throws: IdentityError.keychainUnavailable(errSecInteractionNotAllowed)) {
            try store(lookups: faulty((.key, errSecInteractionNotAllowed))).existingFingerprint()
        }
        #expect(throws: IdentityError.keychainDenied) {
            try store(lookups: faulty((.key, errSecUserCanceled))).existingFingerprint()
        }
        #expect(store().currentCommonName == cn)
        #expect(cleanUp([cn]))
    }
}
}

/// 第 1 次憑證查詢：先讓另一個 store 重設並重建身分（模擬兩次判定之間的空檔）；前 `notFoundCount` 次回 NotFound，之後轉真鑰匙圈
final class RebuildOnFirstCertificateLookup: KeychainLookups, @unchecked Sendable {
    private let base = LiveKeychainLookups()
    private let rebuild: @Sendable () -> DeviceIdentity?
    private let lock = NSLock()
    private var calls = 0
    private let notFoundCount: Int
    private(set) var rebuilt: DeviceIdentity?

    init(notFoundCount: Int = 1, rebuild: @escaping @Sendable () -> DeviceIdentity?) {
        self.notFoundCount = notFoundCount
        self.rebuild = rebuild
    }

    func certificate(label: String) -> (OSStatus, CFTypeRef?) {
        let call = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if call == 1 {
            let identity = rebuild()
            lock.withLock { rebuilt = identity }
        }
        return call <= notFoundCount ? (errSecItemNotFound, nil) : base.certificate(label: label)
    }

    func keyStatus(tag: Data) -> OSStatus { base.keyStatus(tag: tag) }
    func identity(for certificate: SecCertificate) -> (OSStatus, SecIdentity?) { base.identity(for: certificate) }
}
#endif
