import Foundation
import RemoteProtocol
import RemoteTransport

// 中繼的外部邊界（protocol＋替身，CLAUDE.md 慣例；sprint-2-detail.md §4.11）

/// 本機身分：RelayHost 只需要指紋（比對 marker、列信任紀錄）與預熱
protocol RelayIdentity: Sendable {
    /// 取得身分（沒有或已遺失就建立／重建）
    func fingerprint() throws(IdentityError) -> Fingerprint
    /// 唯讀（R7）：不建立、不重建；沒有身分或鑰匙圈讀不到＝nil
    func storedFingerprint() -> Fingerprint?
    func warmUp() async throws(IdentityError)
}

/// 傳輸伺服端（正式＝TransportServer 包裝；測試＝Fake）
protocol RelayServing: AnyObject, Sendable {
    func start() async throws
    func stop()
    func openPairingWindow() -> QRPairingPayload
    func approvePairing()
    func rejectPairing()
    func cancelPairing()
    func revoke(peerID: UUID)
    /// 曲庫換版時推給所有已連線 iPad（S3）
    func broadcastCatalogChanged(version: String)
    /// 連線是否仍在（S4 受管指令的連線撤離，見 `TransportServer.isConnectionAlive`）
    func isConnectionAlive(_ id: UUID) -> Bool
    /// 播放狀態推給所有已連線 iPad（S4）
    func broadcastPlayback(_ event: RemoteProtocol.PlaybackEvent)
    var events: AsyncStream<ServerEvent> { get }
}

protocol RelayPreferences: AnyObject, Sendable {
    /// F-R-05：預設關
    var relayEnabled: Bool { get set }
    /// CR-011：上次預熱成功時的「完整 CDHash＋本機身分指紋」
    var lastWarmedMarker: String? { get set }
}

struct RelayDependencies {
    let identity: any RelayIdentity
    let trust: any TrustStore
    let preferences: any RelayPreferences
    /// 曲庫（S3）；中繼關閉時不會被呼叫
    let catalog: any RelayCatalog
    /// 播放控制與狀態輪詢（S4）；中繼關閉或無連線時不送任何 Apple Event（D13）
    let playback: any RelayPlayback
    /// 本程式的完整 CDHash（十六進位）；取不到回 nil（→ fail closed）
    let cdHash: @Sendable () -> String?
    let makeServer: @Sendable () throws -> any RelayServing
    let now: @Sendable () -> Date
    /// 登入時啟動（S6 F-R-06）：正式＝LiveLoginItem；預設 inert，測試與 `RelayHost.inert()` 不碰系統登入項目
    var loginItem: any LoginItemControlling = InertLoginItem()
}

/// App 啟動時中繼要怎麼起來（CR-011，純函式）
enum RelayStartup {
    enum Action: Equatable {
        case stayOff, autoWarmUp, waitForUser
    }

    /// 完整 CDHash＋本機身分指紋；任一取不到＝nil
    static func marker(cdHash: String?, identity: Fingerprint) -> String? {
        guard let cdHash, !cdHash.isEmpty else { return nil }
        return "v1:" + cdHash + ":" + identity.bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 同一建置且同一身分已授權過才自動預熱；其他（含無法比對）一律等使用者
    static func decide(enabled: Bool, stored: String?, current: String?) -> Action {
        guard enabled else { return .stayOff }
        guard let stored, let current, stored == current else { return .waitForUser }
        return .autoWarmUp
    }
}

enum RelayLifecycleEvent: Equatable, Sendable {
    case screenLocked, screenUnlocked, willSleep, didWake
}
