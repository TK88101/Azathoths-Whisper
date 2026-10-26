import Foundation
import Security

/// 本機長期身分（CR-010 ③；設計 §4.2-1）。
/// `SecIdentity` 是建立後不再變更的 CF 物件，只在組 TLS 參數時讀取（`sec_identity_create`），不跨執行緒修改；
/// 本型別不提供任何可變 API——這是 `@unchecked Sendable` 的理由（sprint-2-detail.md §4.3，本模組唯一的例外）。
public struct DeviceIdentity: @unchecked Sendable {
    public let secIdentity: SecIdentity
    public let certificateDER: Data
    public let fingerprint: Fingerprint

    public init(secIdentity: SecIdentity) throws(IdentityError) {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(secIdentity, &certificate) == errSecSuccess, let certificate else {
            throw .keychainUnavailable(errSecItemNotFound)
        }
        self.secIdentity = secIdentity
        certificateDER = SecCertificateCopyData(certificate) as Data
        fingerprint = Fingerprint(der: certificateDER)
    }
}

public enum IdentityError: Error, Equatable, Sendable {
    /// 使用者在鑰匙圈授權框按了拒絕／取消，或密碼驗證失敗
    case keychainDenied
    case keychainUnavailable(OSStatus)
    case certificateGeneration
}

/// 本機身分的取得、重建與預熱（sprint-2-detail.md §4.3）
public protocol DeviceIdentityStore: Sendable {
    /// 讀取既有身分；不存在或部分遺失則重建（重建後舊信任紀錄因 localFingerprint 不符而自動失效，§4.4）
    func loadOrCreate() throws(IdentityError) -> DeviceIdentity
    func reset() throws(IdentityError)
    /// 以私鑰做一次本機簽章，讓鑰匙圈授權框在使用者在場時出現（CR-010 ⑥）
    func warmUp() async throws(IdentityError)
}

/// 測試替身：只接受呼叫端當次產生的身分（不讀任何檔案或夾具）
public final class InMemoryDeviceIdentityStore: DeviceIdentityStore {
    private struct State {
        var index = 0
        var warmUpCount = 0
    }

    private let identities: [DeviceIdentity]
    private let warmUpResult: Result<Void, IdentityError>
    private let state = Locked(State())

    public init(identities: [DeviceIdentity], warmUpResult: Result<Void, IdentityError> = .success(())) {
        precondition(!identities.isEmpty)
        self.identities = identities
        self.warmUpResult = warmUpResult
    }

    public var warmUpCount: Int { state.withLock { $0.warmUpCount } }

    public func loadOrCreate() throws(IdentityError) -> DeviceIdentity {
        identities[state.withLock { min($0.index, identities.count - 1) }]
    }

    public func reset() throws(IdentityError) {
        state.withLock { $0.index += 1 }
    }

    public func warmUp() async throws(IdentityError) {
        state.withLock { $0.warmUpCount += 1 }
        try warmUpResult.get()
    }
}
