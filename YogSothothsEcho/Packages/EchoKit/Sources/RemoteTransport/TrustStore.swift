import Foundation

/// 對端信任紀錄（sprint-2-detail.md §4.4）。**有效 ⇔ `localFingerprint` 等於目前本機身分指紋**——唯一判定處是
/// `TrustStore.validRecords(for:)`；本機身分一換，舊紀錄自動全部失效（CR-010 ③）。
public struct PeerRecord: Codable, Equatable, Sendable {
    public let peerID: UUID
    /// 對端 leaf DER 的 SHA-256（取自 verify 看到的憑證，不取自對端自報）
    public let fingerprint: Fingerprint
    /// 建立此紀錄時的本機身分指紋
    public let localFingerprint: Fingerprint
    /// 已淨化的顯示名稱（不是身分）
    public let name: String
    public let pairedAt: Date

    public init(peerID: UUID, fingerprint: Fingerprint, localFingerprint: Fingerprint, name: String, pairedAt: Date) {
        self.peerID = peerID
        self.fingerprint = fingerprint
        self.localFingerprint = localFingerprint
        self.name = name
        self.pairedAt = pairedAt
    }
}

/// 只有 `validRecords(for:)` 一個讀取口：不給「讀全部」或「依對端指紋查」的 API，避免誤用失效紀錄
/// `TransportServer` 會在配對序列鎖內呼叫 `add`：實作不得同步呼叫同一 server 的 API（F-2）
public protocol TrustStore: Sendable {
    func validRecords(for localFingerprint: Fingerprint) -> [PeerRecord]
    /// 同（對端指紋、本機指紋）＝覆寫；同時刪掉本機指紋不符的失效紀錄
    func add(_ record: PeerRecord) throws
    func remove(peerID: UUID) throws
    func removeAll() throws
}

enum TrustRecords {
    static func adding(_ record: PeerRecord, to records: [PeerRecord]) -> [PeerRecord] {
        records.filter { $0.localFingerprint == record.localFingerprint && $0.fingerprint != record.fingerprint } + [record]
    }
}

public final class InMemoryTrustStore: TrustStore {
    private let records = Locked<[PeerRecord]>([])
    public init() {}

    public func validRecords(for localFingerprint: Fingerprint) -> [PeerRecord] {
        records.withLock { $0.filter { $0.localFingerprint == localFingerprint } }
    }

    public func add(_ record: PeerRecord) throws { records.withLock { $0 = TrustRecords.adding(record, to: $0) } }
    public func remove(peerID: UUID) throws { records.withLock { $0.removeAll { $0.peerID == peerID } } }
    public func removeAll() throws { records.withLock { $0 = [] } }
}

/// UserDefaults 版：JSON 陣列。不跨執行緒傳遞 `UserDefaults` 實例——每次以 suiteName 取用，寫入以鎖序列化
public final class UserDefaultsTrustStore: TrustStore {
    public static let defaultKey = "yse.trust.v1"
    private let suiteName: String?
    private let key: String
    private let audit: any AuditSink
    private let writeLock = Locked<Void>(())

    public init(suiteName: String? = nil, key: String = UserDefaultsTrustStore.defaultKey, audit: any AuditSink = NoopAuditSink()) {
        self.suiteName = suiteName
        self.key = key
        self.audit = audit
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// 解碼失敗＝視為空並稽核（不崩潰、不自動修復）
    private func load() -> [PeerRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let records = try? JSONDecoder().decode([PeerRecord].self, from: data) else {
            audit.record(.trustStoreCorrupt)
            return []
        }
        return records
    }

    private func save(_ records: [PeerRecord]) throws {
        defaults.set(try JSONEncoder().encode(records), forKey: key)
    }

    public func validRecords(for localFingerprint: Fingerprint) -> [PeerRecord] {
        load().filter { $0.localFingerprint == localFingerprint }
    }

    public func add(_ record: PeerRecord) throws {
        try writeLock.withLock { _ in try self.save(TrustRecords.adding(record, to: self.load())) }
    }

    public func remove(peerID: UUID) throws {
        try writeLock.withLock { _ in try self.save(self.load().filter { $0.peerID != peerID }) }
    }

    public func removeAll() throws {
        try writeLock.withLock { _ in try self.save([]) }
    }
}
