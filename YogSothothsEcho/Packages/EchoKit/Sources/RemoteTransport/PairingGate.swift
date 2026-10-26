import Foundation

/// verify block 讀的不可變快照（sprint-2-detail.md §4.7）。由狀態轉移在**釋放狀態鎖後**發布；
/// 只接受版本較新的快照（晚到的舊快照丟棄）。verify 只決定能否完成 TLS，ready 後仍由狀態鎖內的真狀態再確認。
public final class PairingGate: Sendable {
    public struct Snapshot: Equatable, Sendable {
        public let version: UInt64
        /// 只由 `TrustStore.validRecords(for: 本機身分指紋)` 建立
        public let trusted: Set<Fingerprint>
        public let pairingOpen: Bool

        public init(version: UInt64, trusted: Set<Fingerprint>, pairingOpen: Bool) {
            self.version = version
            self.trusted = trusted
            self.pairingOpen = pairingOpen
        }
    }

    public enum Admission: Equatable, Sendable {
        case trusted, pairingCandidate, reject
    }

    private let snapshot = Locked(Snapshot(version: 0, trusted: [], pairingOpen: false))

    public init() {}

    public var current: Snapshot { snapshot.withLock { $0 } }

    public func publish(_ next: Snapshot) {
        snapshot.withLock { if next.version > $0.version { $0 = next } }
    }

    public func admits(_ fingerprint: Fingerprint) -> Admission {
        let now = current
        if now.trusted.contains(fingerprint) { return .trusted }
        return now.pairingOpen ? .pairingCandidate : .reject
    }
}
