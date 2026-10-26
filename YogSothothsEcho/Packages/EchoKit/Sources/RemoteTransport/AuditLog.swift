import Foundation
import RemoteProtocol

/// 稽核事件（sprint-2-detail.md §4.10；N-05）。關聯值只能是封閉 enum 或 UUID——型別層保證不含
/// 一次性秘密、QR 文字、exporter、proof、指紋、裝置名稱。
public enum AuditEvent: Equatable, Sendable {
    case pairingWindowOpened
    case pairingProofRejected(ProofRejection)
    case invalidTLS
    case pairingAccepted(peerID: UUID)
    case pairingFinished(PairOutcome)
    case connectionRejected(ConnectionRejection)
    case handshakeTimeout
    case replayRejected
    case rateLimited(LimitKind)
    case peerRevoked(peerID: UUID)
    case identityReset
    case nonLocalPeer
    case pingFlood
    case trustStoreCorrupt
}

public enum ProofRejection: String, Sendable, CaseIterable {
    case invalid, unavailable
}

public enum ConnectionRejection: String, Sendable, CaseIterable {
    case unknownPeer, pathMismatch, invalidRequest, oversized, notOnLink, capacity, cooldown
}

public enum LimitKind: String, Sendable, CaseIterable {
    case control, newConnection, pairing
    /// 讀取類（catalog.*、artwork.get；CR-012）
    case read
}

/// `TransportServer` 會在配對序列鎖內呼叫 `record`：實作不得同步呼叫同一 server 的 API（F-2）
public protocol AuditSink: Sendable {
    func record(_ event: AuditEvent)
}

/// 測試用：收下實際送出的事件
public final class SpyAuditSink: AuditSink {
    private let store = Locked<[AuditEvent]>([])
    public init() {}
    public var events: [AuditEvent] { store.withLock { $0 } }
    public func record(_ event: AuditEvent) { store.withLock { $0.append(event) } }
}

public struct NoopAuditSink: AuditSink {
    public init() {}
    public func record(_ event: AuditEvent) {}
}

/// 稽核事件的唯一輸出路徑：固定三欄（event、reason、peer）。值只來自封閉 enum 的 rawValue 或 UUID（§4.10）
public enum AuditRenderer {
    public struct Field: Equatable, Sendable {
        public let key: String
        public let value: String
    }

    public static func fields(_ event: AuditEvent) -> [Field] {
        let (name, reason, peer) = parts(event)
        return [Field(key: "event", value: name), Field(key: "reason", value: reason), Field(key: "peer", value: peer?.uuidString ?? "")]
    }

    private static func parts(_ event: AuditEvent) -> (String, String, UUID?) {
        switch event {
        case .pairingWindowOpened: ("pairingWindowOpened", "", nil)
        case .pairingProofRejected(let reason): ("pairingProofRejected", reason.rawValue, nil)
        case .invalidTLS: ("invalidTLS", "", nil)
        case .pairingAccepted(let peer): ("pairingAccepted", "", peer)
        case .pairingFinished(let outcome): ("pairingFinished", outcome.rawValue, nil)
        case .connectionRejected(let reason): ("connectionRejected", reason.rawValue, nil)
        case .handshakeTimeout: ("handshakeTimeout", "", nil)
        case .replayRejected: ("replayRejected", "", nil)
        case .rateLimited(let kind): ("rateLimited", kind.rawValue, nil)
        case .peerRevoked(let peer): ("peerRevoked", "", peer)
        case .identityReset: ("identityReset", "", nil)
        case .nonLocalPeer: ("nonLocalPeer", "", nil)
        case .pingFlood: ("pingFlood", "", nil)
        case .trustStoreCorrupt: ("trustStoreCorrupt", "", nil)
        }
    }
}

public protocol RenderedAuditOutput: Sendable {
    func write(_ fields: [AuditRenderer.Field])
}

public struct RenderingAuditSink: AuditSink {
    let output: any RenderedAuditOutput
    public init(output: any RenderedAuditOutput) { self.output = output }
    public func record(_ event: AuditEvent) { output.write(AuditRenderer.fields(event)) }
}
