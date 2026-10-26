import Foundation

/// 傳輸與配對的數值常數（sprint-2-detail.md §4.9）；實作與測試一律引用這裡
public enum TransportLimits {
    public static let qrLifetime: TimeInterval = 60
    public static let approvalTimeout: TimeInterval = 60
    public static let handshakeTimeout: TimeInterval = 10
    public static let heartbeatInterval: TimeInterval = 5
    public static let heartbeatDeadline: TimeInterval = 15
    public static let maxPingsPerSecond = 2
    public static let maxMessageBytes = 65_536
    public static let maxUnclassifiedConnections = 4
    public static let maxUnclassifiedPerSource = 2
    public static let maxNewConnectionsPerSecond = 10
    public static let maxNewConnectionsPerSourcePerSecond = 3
    public static let controlPerSecond = 20
    public static let maxInvalidPairingAttempts = 10
    public static let pairingCooldown: TimeInterval = 10
    public static let reconnectCap: TimeInterval = 30
    public static let deviceNameMaxBytes = 64
    public static let displayNameMaxCharacters = 32
    public static let nonceBytes = 16
    public static let sessionIDBytes = 16
    public static let proofBytes = 32

    // CR-012（sprint-3-detail.md §4.5）：讀取類配額與資源上限。maxMessageBytes 不變（兩端 64 KiB）
    /// Mac 回應的完整外層訊息實際編碼位元組上限；留 4 KiB 給餘裕
    public static let responseBudgetBytes = 61_440
    public static let readPerSecond = 60
    public static let maxInFlightPerConnection = 8
    public static let maxArtworkInFlightPerConnection = 4
    public static let maxArtworkInFlightTotal = 8
    public static let maxPendingSendBytesPerConnection = 1_048_576
    public static let maxPendingSendBytesTotal = 4_194_304
}
