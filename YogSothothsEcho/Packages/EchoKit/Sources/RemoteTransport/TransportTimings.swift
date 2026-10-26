import Foundation
import RemoteProtocol

/// 時間參數（sprint-2-detail.md §4.9）。正式值取自 `TransportLimits`；測試注入較短的值
public struct TransportTimings: Sendable {
    public var handshakeTimeout: TimeInterval
    public var heartbeatInterval: TimeInterval
    public var heartbeatDeadline: TimeInterval
    /// 伺服端巡檢（配對窗到期、閒置連線）的間隔
    public var sweepInterval: TimeInterval
    /// iPad 等 Mac 回覆配對結果的上限（涵蓋 Mac 確認期限）
    public var pairingResponseTimeout: TimeInterval
    public var connectTimeout: TimeInterval

    public static let production = TransportTimings(
        handshakeTimeout: TransportLimits.handshakeTimeout, heartbeatInterval: TransportLimits.heartbeatInterval,
        heartbeatDeadline: TransportLimits.heartbeatDeadline, sweepInterval: 1,
        pairingResponseTimeout: TransportLimits.approvalTimeout + 10, connectTimeout: TransportLimits.handshakeTimeout)

    public static let test = TransportTimings(handshakeTimeout: 0.6, heartbeatInterval: 0.6, heartbeatDeadline: 1.5,
                                              sweepInterval: 0.05, pairingResponseTimeout: 5, connectTimeout: 3)
}

/// 連線名額與限流（§4.7、§4.8）
public struct ServerLimits: Sendable {
    public var maxUnclassified: Int
    public var maxUnclassifiedPerSource: Int
    public var newConnectionsPerSecond: Int
    public var newConnectionsPerSourcePerSecond: Int
    // CR-012（sprint-3-detail.md §4.5）：業務請求的配額與在途、待送上限
    public var readPerSecond = TransportLimits.readPerSecond
    public var maxInFlightPerConnection = TransportLimits.maxInFlightPerConnection
    public var maxArtworkInFlightPerConnection = TransportLimits.maxArtworkInFlightPerConnection
    public var maxArtworkInFlightTotal = TransportLimits.maxArtworkInFlightTotal
    public var maxPendingSendBytesPerConnection = TransportLimits.maxPendingSendBytesPerConnection
    public var maxPendingSendBytesTotal = TransportLimits.maxPendingSendBytesTotal

    public static let standard = ServerLimits(
        maxUnclassified: TransportLimits.maxUnclassifiedConnections,
        maxUnclassifiedPerSource: TransportLimits.maxUnclassifiedPerSource,
        newConnectionsPerSecond: TransportLimits.maxNewConnectionsPerSecond,
        newConnectionsPerSourcePerSecond: TransportLimits.maxNewConnectionsPerSourcePerSecond)

    /// 功能測試在同一來源連續開大量連線；只放寬新連線速率，名額上限不變
    public static let relaxedForTests = ServerLimits(
        maxUnclassified: TransportLimits.maxUnclassifiedConnections,
        maxUnclassifiedPerSource: TransportLimits.maxUnclassifiedPerSource,
        newConnectionsPerSecond: 1_000, newConnectionsPerSourcePerSecond: 1_000)
}
