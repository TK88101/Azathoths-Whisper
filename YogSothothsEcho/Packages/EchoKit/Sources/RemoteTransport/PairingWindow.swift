import Foundation
import RemoteProtocol

/// 一條 TLS 連線的識別（不含對端資訊）
/// 每條進站連線建立時產生一個；**一條連線一個、永不重用**（S4 連線撤離的契約：
/// 排隊中的指令以它判斷原連線是否還在；重連或被取代的新連線一定拿到不同的值）
public struct ConnectionID: Hashable, Sendable, CustomStringConvertible {
    let raw = UUID()
    public init() {}
    public var uuid: UUID { raw }
    public var description: String { "conn-" + raw.uuidString.prefix(8) }
}

/// 狀態機的輸出；由呼叫端（TransportServer、RelayHost）在鎖外執行。不含一次性秘密
public enum PairingEffect: Equatable, Sendable {
    case sendPending(ConnectionID, suffix: String)
    case sendResult(ConnectionID, PairOutcome)
    case sendError(ConnectionID, ErrorCode)
    case close(ConnectionID)
    case showConfirm(name: String, suffix: String)
    case dismissConfirm
    case recordPeer(PeerRecord)
    case audit(AuditEvent)
}

/// Mac 端配對窗純狀態機（sprint-2-detail.md §4.6；CR-010 ②）：
/// closed → open(S, fpM, 60 s) → pending(fpM, fpI, 60 s) → finished(approved／rejected／expired／cancelled)。
/// 一次性秘密 S 只在 open 內；proof 驗證在本型別內完成，外部取不到 S。
/// 呼叫端必須在單一鎖內呼叫（§4.7），以保證「驗 proof ＋ open→pending」原子。
public struct PairingWindow: Sendable {
    struct Open: Sendable, CustomReflectable {
        let sessionID: Data
        let secret: Data
        let macFingerprint: Fingerprint
        let expiresAt: Date
        var customMirror: Mirror { Mirror(self, children: ["expiresAt": expiresAt], displayStyle: .struct) }
    }

    struct Pending: Sendable {
        let connection: ConnectionID
        let macFingerprint: Fingerprint
        let ipadFingerprint: Fingerprint
        let name: String
        let deadline: Date
    }

    enum Phase: Sendable {
        case closed
        case open(Open)
        case pending(Pending)
        case finished(PairOutcome)
    }

    private(set) var phase: Phase = .closed
    public private(set) var invalidAttempts = 0
    private var cooldownUntil: Date?

    public init() {}

    public var isOpen: Bool {
        if case .open = phase { return true }
        return false
    }

    /// pending 中佔用配對路徑的那條連線（其餘配對連線都該斷）
    public var pendingConnection: ConnectionID? {
        if case .pending(let pending) = phase { return pending.connection }
        return nil
    }

    public var outcome: PairOutcome? {
        if case .finished(let outcome) = phase { return outcome }
        return nil
    }

    public func isCoolingDown(now: Date) -> Bool {
        cooldownUntil.map { now < $0 } ?? false
    }

    /// 開新窗（舊窗先取消）。回傳的載荷是 S 唯一離開狀態機的出口——只供 QR 顯示
    public mutating func open(sessionID: Data, secret: Data, macFingerprint: Fingerprint, instanceName: String,
                              now: Date) -> (QRPairingPayload, [PairingEffect]) {
        var effects = cancel()
        guard let payload = QRPairingPayload(sessionID: sessionID, macFingerprint: macFingerprint, secret: secret,
                                             instanceName: instanceName) else {
            preconditionFailure("QRPairingPayload 參數由 TransportServer 產生，不應無效")
        }
        phase = .open(Open(sessionID: sessionID, secret: secret, macFingerprint: macFingerprint,
                           expiresAt: now.addingTimeInterval(TransportLimits.qrLifetime)))
        invalidAttempts = 0
        cooldownUntil = nil
        effects.append(.audit(.pairingWindowOpened))
        return (payload, effects)
    }

    public mutating func handleProof(_ body: PairProof, from connection: ConnectionID, ipadFingerprint: Fingerprint,
                                     exporter: Data, now: Date) -> [PairingEffect] {
        guard case .open(let open) = phase, now < open.expiresAt else {
            return [.sendError(connection, .pairingUnavailable), .close(connection), .audit(.pairingProofRejected(.unavailable))]
        }
        guard body.isValid, body.sessionID == open.sessionID,
              PairingProof.verify(body.proof, secret: open.secret, sessionID: open.sessionID,
                                  macFingerprint: open.macFingerprint, ipadFingerprint: ipadFingerprint, exporter: exporter) else {
            recordInvalidAttempt(now: now)
            return [.sendError(connection, .pairingInvalid), .close(connection), .audit(.pairingProofRejected(.invalid))]
        }
        let name = DeviceName.sanitize(body.deviceName, fallback: "iPad")
        phase = .pending(Pending(connection: connection, macFingerprint: open.macFingerprint, ipadFingerprint: ipadFingerprint,
                                 name: name, deadline: now.addingTimeInterval(TransportLimits.approvalTimeout)))
        return [.sendPending(connection, suffix: ipadFingerprint.suffix), .showConfirm(name: name, suffix: ipadFingerprint.suffix)]
    }

    /// 錯 proof 與配對路徑的無效 TLS 合計（CR-010 ②(e)）；超過上限進冷卻，但不關窗
    public mutating func recordInvalidAttempt(now: Date) {
        invalidAttempts += 1
        if invalidAttempts >= TransportLimits.maxInvalidPairingAttempts {
            cooldownUntil = now.addingTimeInterval(TransportLimits.pairingCooldown)
            invalidAttempts = 0
        }
    }

    public mutating func approve(peerID: UUID, now: Date) -> [PairingEffect] {
        guard case .pending(let pending) = phase else { return [] }
        phase = .finished(.approved)
        let record = PeerRecord(peerID: peerID, fingerprint: pending.ipadFingerprint, localFingerprint: pending.macFingerprint,
                                name: pending.name, pairedAt: now)
        return [.recordPeer(record), .sendResult(pending.connection, .approved), .close(pending.connection), .dismissConfirm,
                .audit(.pairingAccepted(peerID: peerID)), .audit(.pairingFinished(.approved))]
    }

    public mutating func reject() -> [PairingEffect] { finish(.rejected) }

    /// 使用者取消、螢幕鎖定、睡眠、中繼關閉（CR-010 ②(g)(l)）
    public mutating func cancel() -> [PairingEffect] { finish(.cancelled) }

    public mutating func tick(now: Date) -> [PairingEffect] {
        switch phase {
        case .open(let open) where now >= open.expiresAt: return finish(.expired)
        case .pending(let pending) where now >= pending.deadline: return finish(.expired)
        default: return []
        }
    }

    public mutating func connectionClosed(_ connection: ConnectionID) -> [PairingEffect] {
        guard case .pending(let pending) = phase, pending.connection == connection else { return [] }
        phase = .finished(.cancelled)
        return [.dismissConfirm, .audit(.pairingFinished(.cancelled))]
    }

    private mutating func finish(_ outcome: PairOutcome) -> [PairingEffect] {
        switch phase {
        case .open:
            phase = .finished(outcome)
            return [.audit(.pairingFinished(outcome))]
        case .pending(let pending):
            phase = .finished(outcome)
            return [.sendResult(pending.connection, outcome), .close(pending.connection), .dismissConfirm,
                    .audit(.pairingFinished(outcome))]
        case .closed, .finished:
            return []
        }
    }
}
