import Foundation
import Security

/// 真 Keychain 的本機身分庫（sprint-2-detail.md §4.3）。
/// - 私鑰：`kSecAttrApplicationTag = <service>.key`；憑證：label＝CN（macOS 舊式鑰匙圈加憑證時 label 一律＝CN，2026-10-15 實測），
///   iOS 明設 label＝CN。CN（非機密）存 UserDefaults。
/// - 任一半遺失＝刪掉殘餘、重建身分並稽核 `identityReset`；舊信任紀錄因 localFingerprint 不符自動失效（§4.4），不需另外清。
///   「遺失」只認鑰匙圈明確回 `errSecItemNotFound`；其他回應（未解鎖、暫時不可用、結果不可用）＝讀不到，throw、不刪不建（R7）。
/// - 不持有 `UserDefaults` 實例：每次以 suiteName 取用。
public final class KeychainDeviceIdentityStore: DeviceIdentityStore {
    private let service: String
    private let defaultsSuite: String?
    private let audit: any AuditSink
    private let lookups: any KeychainLookups
    private let missingConfirmDelay: TimeInterval
    private let lock = Locked<Void>(())

    /// 第一次讀到「不存在」後，隔多久從頭再查一次（R7 §11；暫定值、未量測）
    public static let defaultMissingConfirmDelay: TimeInterval = 0.3

    public convenience init(service: String, defaultsSuite: String? = nil, audit: any AuditSink = NoopAuditSink()) {
        self.init(service: service, defaultsSuite: defaultsSuite, audit: audit, lookups: LiveKeychainLookups())
    }

    /// 測試用：可換掉鑰匙圈讀取結果（R7）
    @_spi(Testing) public init(service: String, defaultsSuite: String? = nil, audit: any AuditSink = NoopAuditSink(),
                               lookups: any KeychainLookups, missingConfirmDelay: TimeInterval = defaultMissingConfirmDelay) {
        self.service = service
        self.defaultsSuite = defaultsSuite
        self.audit = audit
        self.lookups = lookups
        #if DEBUG
        self.missingConfirmDelay = missingConfirmDelay
        #else
        // 正式版不得縮短確認間隔（security review R7 §11 LOW）
        self.missingConfirmDelay = max(missingConfirmDelay, Self.defaultMissingConfirmDelay)
        #endif
    }

    var keyTag: String { service + ".key" }
    private var cnKey: String { service + ".cn" }
    private var defaults: UserDefaults { defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    var currentCommonName: String? { defaults.string(forKey: cnKey) }

    /// 既有身分第一次讀到「不存在」先不刪：放鎖、隔 `missingConfirmDelay` 從頭再查（重讀 CN），
    /// 同一個 CN 仍不存在才刪除重建（R7 §11）
    public func loadOrCreate() throws(IdentityError) -> DeviceIdentity {
        switch try locked({ try self.firstLookLocked() }) {
        case .loaded(let identity): return identity
        case .suspectedMissing(let commonName):
            Thread.sleep(forTimeInterval: missingConfirmDelay)
            return try locked({ try self.confirmLocked(suspected: commonName) })
        }
    }

    private enum FirstLook: Sendable {
        case loaded(DeviceIdentity)
        case suspectedMissing(commonName: String)
    }

    private func locked<R: Sendable>(_ body: @Sendable () throws -> R) throws(IdentityError) -> R {
        do {
            return try lock.withLock { _ in try body() }
        } catch let error as IdentityError {
            throw error
        } catch {
            throw .keychainUnavailable(errSecInternalError)
        }
    }

    private func firstLookLocked() throws(IdentityError) -> FirstLook {
        guard let commonName = currentCommonName else { return .loaded(try create()) }
        guard let identity = try storedIdentity(commonName: commonName) else { return .suspectedMissing(commonName: commonName) }
        return .loaded(identity)
    }

    /// 既有身分的刪除、稽核只在這裡：重讀 CN，仍是第一次那個且仍不存在才刪
    private func confirmLocked(suspected: String) throws(IdentityError) -> DeviceIdentity {
        guard let commonName = currentCommonName else { return try create() }   // CN 已被清掉＝首次建立
        if let identity = try storedIdentity(commonName: commonName) { return identity }
        // 空檔裡換成了別的身分：對它只看到一次「不存在」，不刪，下次呼叫再判
        guard commonName == suspected else { throw .keychainUnavailable(errSecItemNotFound) }
        deleteItems(commonName: commonName)
        audit.record(.identityReset)
        return try create()
    }

    /// 找到＝身分；明確不存在＝nil；讀不到＝throw
    private func storedIdentity(commonName: String) throws(IdentityError) -> DeviceIdentity? {
        switch existingIdentity(commonName: commonName) {
        case .found(let identity): return identity
        case .missing: return nil
        case .unreadable(let status): throw Self.identityError(for: status)
        }
    }

    /// 唯讀（R7）：不建立、不刪除、不稽核。沒有身分（首次或已遺失）＝nil；鑰匙圈讀不到＝throw
    public func existingFingerprint() throws(IdentityError) -> Fingerprint? {
        try locked {
            guard let commonName = self.currentCommonName else { return nil }
            return try self.storedIdentity(commonName: commonName)?.fingerprint
        }
    }

    public func reset() throws(IdentityError) {
        lock.withLock { _ in
            if let cn = self.currentCommonName { self.deleteItems(commonName: cn) }
            self.deleteKey()
            self.defaults.removeObject(forKey: self.cnKey)
        }
    }

    public func warmUp() async throws(IdentityError) {
        let identity = try loadOrCreate()
        let result: Result<Void, IdentityError> = await Task.detached(priority: .userInitiated) {
            var key: SecKey?
            guard SecIdentityCopyPrivateKey(identity.secIdentity, &key) == errSecSuccess, let key else {
                return .failure(.keychainUnavailable(errSecItemNotFound))
            }
            var error: Unmanaged<CFError>?
            guard SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, Data("yse-warm-up".utf8) as CFData, &error) != nil else {
                let code = error.map { OSStatus(CFErrorGetCode($0.takeRetainedValue())) } ?? errSecInternalError
                return .failure(Self.identityError(for: code))
            }
            return .success(())
        }.value
        try result.get()
    }

    // MARK: Keychain

    private func create() throws(IdentityError) -> DeviceIdentity {
        deleteKey()
        #if os(iOS)
        // 只留本機：不隨備份或移機轉到別台 iPad（每台各自一個身分，CR-010 ③；security review S2 LOW-4）
        let localOnly: [CFString: Any] = [kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        #else
        let localOnly: [CFString: Any] = [:]
        #endif
        let keyAttributes = localOnly.merging([kSecAttrIsPermanent: true, kSecAttrApplicationTag: Data(keyTag.utf8),
                                               kSecAttrLabel: keyTag]) { $1 }
        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: keyAttributes,
        ]
        #if os(macOS)
        // ad-hoc 簽名取不到 data protection keychain 的 entitlement：明確走舊式鑰匙圈
        attributes[kSecUseDataProtectionKeychain] = false
        #endif
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else { throw .keychainUnavailable(errSecInternalError) }
        let cn = MiniCert.randomCommonName()
        let der: Data
        do { der = try MiniCert.make(privateKey: key, commonName: cn) } catch {
            deleteKey()
            throw .certificateGeneration
        }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            deleteKey()
            throw .certificateGeneration
        }
        let status = SecItemAdd(localOnly.merging([kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: cn]) { $1 }
                                as CFDictionary, nil)
        guard status == errSecSuccess else {
            deleteKey()
            throw .keychainUnavailable(status)
        }
        defaults.set(cn, forKey: cnKey)
        switch existingIdentity(commonName: cn) {
        case .found(let identity): return identity
        // 剛建好的讀不到≠不存在：保留項目與 CN，下次讀到即恢復（R7 D3b）
        case .unreadable(let status): throw Self.identityError(for: status)
        case .missing:
            deleteItems(commonName: cn)
            defaults.removeObject(forKey: cnKey)
            throw .keychainUnavailable(errSecItemNotFound)
        }
    }

    // MARK: 讀取判定（R7，r7-identity-transient.md §5 D1–D2；只寫這一處）

    private enum Lookup: Sendable {
        case found(DeviceIdentity)
        case missing
        case unreadable(OSStatus)
    }

    /// 只有明確的 `errSecItemNotFound` 才算不存在；success 由呼叫端再檢查結果是否可用
    private static func lookup(for status: OSStatus) -> Lookup? {
        switch status {
        case errSecSuccess: nil
        case errSecItemNotFound: .missing
        default: .unreadable(status)
        }
    }

    /// 讀不到時的錯誤：授權框被拒或驗證失敗＝denied（loadOrCreate、existingFingerprint、warmUp 共用）
    private static func identityError(for status: OSStatus) -> IdentityError {
        status == errSecUserCanceled || status == errSecAuthFailed ? .keychainDenied : .keychainUnavailable(status)
    }

    /// 憑證與私鑰兩半都先查完：任一半讀不到＝讀不到（憑證那一半優先）；否則任一半不存在＝不存在
    private func existingIdentity(commonName cn: String) -> Lookup {
        let (certificateStatus, result) = lookups.certificate(label: cn)
        let certificate = result.flatMap { CFGetTypeID($0) == SecCertificateGetTypeID() ? ($0 as! SecCertificate) : nil }
        let certificateHalf = certificateStatus == errSecSuccess && certificate == nil
            ? .unreadable(errSecInternalError) : Self.lookup(for: certificateStatus)
        let keyHalf = Self.lookup(for: lookups.keyStatus(tag: Data(keyTag.utf8)))
        switch (certificateHalf, keyHalf) {
        case (.unreadable(let status), _), (_, .unreadable(let status)): return .unreadable(status)
        case (.missing, _), (_, .missing): return .missing
        default: break
        }
        guard let certificate else { return .unreadable(errSecInternalError) }   // 上面已判定；此處只為解開 optional
        return identity(pairing: certificate)
    }

    #if os(macOS)
    private func identity(pairing certificate: SecCertificate) -> Lookup {
        let (status, identity) = lookups.identity(for: certificate)
        if let failure = Self.lookup(for: status) { return failure }
        guard let identity, let device = try? DeviceIdentity(secIdentity: identity) else { return .unreadable(errSecInternalError) }
        return .found(device)
    }
    #else
    private func identity(pairing certificate: SecCertificate) -> Lookup {
        let der = SecCertificateCopyData(certificate) as Data
        let (status, result) = lookups.allIdentities()
        if let failure = Self.lookup(for: status) { return failure }
        // 列舉成功卻沒有相符的＝資料不一致，不當成不存在（R7 R-d）
        guard let all = result as? [SecIdentity],
              let device = all.lazy.compactMap({ try? DeviceIdentity(secIdentity: $0) }).first(where: { $0.certificateDER == der })
        else { return .unreadable(errSecInternalError) }
        return .found(device)
    }
    #endif

    private func deleteKey() {
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(keyTag.utf8)] as [CFString: Any] as CFDictionary)
    }

    private func deleteItems(commonName cn: String) {
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: cn] as [CFString: Any] as CFDictionary)
        deleteKey()
    }
}
