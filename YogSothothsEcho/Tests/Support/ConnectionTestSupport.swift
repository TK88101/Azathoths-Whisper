import Foundation
import RemoteTransport

/// 連線測試共用：固定的樣本 QR 載荷（秘密為測試值）與「讓 main actor 上的非結構化 Task 跑完」
enum ConnectionSamples {
    static func payload(instance: String = "Azathoth-0202") -> QRPairingPayload {
        QRPairingPayload(sessionID: Data(repeating: 1, count: 16), macFingerprint: Fingerprint(bytes: Data(repeating: 2, count: 32))!,
                         secret: Data(repeating: 3, count: 32), instanceName: instance)!
    }
}

/// 必須在 main actor 上 yield：ViewModel 的非結構化 Task 在 main actor 上跑（nonisolated async 會跑在通用 executor、讓不出 main）
@MainActor func settle() async { for _ in 0..<50 { await Task.yield() } }
