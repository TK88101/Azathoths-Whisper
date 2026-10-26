import Foundation
import Security

/// 身分庫對鑰匙圈的「讀取」呼叫（R7，`r7-identity-transient.md` §5 D5）：測試要能把某次查詢換成指定結果。
/// 寫入（建立私鑰、加入憑證、刪除）不經此處
@_spi(Testing) public protocol KeychainLookups: Sendable {
    func certificate(label: String) -> (OSStatus, CFTypeRef?)
    func keyStatus(tag: Data) -> OSStatus
    #if os(macOS)
    func identity(for certificate: SecCertificate) -> (OSStatus, SecIdentity?)
    #else
    func allIdentities() -> (OSStatus, CFTypeRef?)
    #endif
}

@_spi(Testing) public struct LiveKeychainLookups: KeychainLookups {
    public init() {}

    public func certificate(label: String) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassCertificate, kSecAttrLabel: label, kSecReturnRef: true]
                                         as [CFString: Any] as CFDictionary, &result)
        return (status, result)
    }

    public func keyStatus(tag: Data) -> OSStatus {
        SecItemCopyMatching([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag] as [CFString: Any] as CFDictionary, nil)
    }

    #if os(macOS)
    public func identity(for certificate: SecCertificate) -> (OSStatus, SecIdentity?) {
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        return (status, identity)
    }
    #else
    public func allIdentities() -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassIdentity, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitAll]
                                         as [CFString: Any] as CFDictionary, &result)
        return (status, result)
    }
    #endif
}

#if DEBUG
/// 測試替身（只在 DEBUG；Release 不帶，security review R7 LOW）：指定查詢的前 n 次回指定結果，之後轉給 `base`（逐次腳本，不是持續覆寫：重建後的讀回要能走真鑰匙圈）。
/// 狀態只在 `lock` 內讀寫；`CFTypeRef` 不是 Sendable，故以 `@unchecked Sendable` 包住
@_spi(Testing) public final class FaultyKeychainLookups: KeychainLookups, @unchecked Sendable {
    public enum Query: Sendable { case certificate, key, identity }

    private struct Fault {
        var remaining: Int
        let status: OSStatus
        let result: CFTypeRef?
    }

    private let base: any KeychainLookups
    private let lock = NSLock()
    private var faults: [Query: Fault] = [:]

    public init(base: any KeychainLookups = LiveKeychainLookups()) { self.base = base }

    public func fail(_ query: Query, times: Int = 1, status: OSStatus, result: CFTypeRef? = nil) {
        lock.withLock { faults[query] = Fault(remaining: times, status: status, result: result) }
    }

    /// 該查詢還有排定的結果就取出一次
    private func take(_ query: Query) -> (OSStatus, CFTypeRef?)? {
        lock.withLock {
            guard var fault = faults[query], fault.remaining > 0 else { return nil }
            fault.remaining -= 1
            faults[query] = fault
            return (fault.status, fault.result)
        }
    }

    public func certificate(label: String) -> (OSStatus, CFTypeRef?) {
        take(.certificate) ?? base.certificate(label: label)
    }

    public func keyStatus(tag: Data) -> OSStatus {
        take(.key)?.0 ?? base.keyStatus(tag: tag)
    }

    #if os(macOS)
    public func identity(for certificate: SecCertificate) -> (OSStatus, SecIdentity?) {
        guard let (status, result) = take(.identity) else { return base.identity(for: certificate) }
        guard let result, CFGetTypeID(result) == SecIdentityGetTypeID() else { return (status, nil) }
        return (status, (result as! SecIdentity))
    }
    #else
    public func allIdentities() -> (OSStatus, CFTypeRef?) {
        take(.identity) ?? base.allIdentities()
    }
    #endif
}
#endif
