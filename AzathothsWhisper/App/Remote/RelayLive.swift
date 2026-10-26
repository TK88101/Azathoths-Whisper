import AppKit
import Foundation
import RemoteProtocol
import RemoteTransport
import Security

// 中繼的正式依賴（sprint-2-detail.md §4.11）。單元／UI 測試走 `RelayHost.inert()`，不碰 Keychain 與網路

enum RelayLive {
    static let identityService = "com.ibridgezhao.azathothswhisper.relay-identity"
    static let logSubsystem = "com.ibridgezhao.azathothswhisper"

    @MainActor
    static func makeHost() -> RelayHost {
        let audit = RenderingAuditSink(output: OSLogAuditOutput(subsystem: logSubsystem))
        let store = KeychainDeviceIdentityStore(service: identityService, audit: audit)
        let trust = UserDefaultsTrustStore(audit: audit)
        // LibraryReader 第一次被 iPad 請求時才建立 ITLibrary（H-31 草稿）；這裡只建物件，不讀曲庫、不碰 Music
        let catalog = LiveRelayCatalog()
        let playback = LiveRelayPlayback.make(catalog: catalog.service)
        let router = RelayRequestRouter(catalog: catalog.service, playback: playback.service)
        return RelayHost(dependencies: RelayDependencies(
            identity: KeychainRelayIdentity(store: store), trust: trust, preferences: UserDefaultsRelayPreferences(),
            catalog: catalog, playback: playback, cdHash: { CodeSignature.currentCDHash() },
            makeServer: {
                let identity = try store.loadOrCreate()
                return TransportRelayServer(TransportServer(configuration: ServerConfiguration(
                    identity: identity, trust: trust, audit: audit, serviceName: EchoService.instanceName(for: identity.fingerprint),
                    requestHandler: router)))
            },
            now: { Date() }, loginItem: LiveLoginItem()))
    }
}

struct KeychainRelayIdentity: RelayIdentity {
    let store: KeychainDeviceIdentityStore
    func fingerprint() throws(IdentityError) -> Fingerprint { try store.loadOrCreate().fingerprint }
    func storedFingerprint() -> Fingerprint? { (try? store.existingFingerprint()) ?? nil }
    func warmUp() async throws(IdentityError) { try await store.warmUp() }
}

/// 自動化測試與預設：永遠取不到身分（中繼預設關，不會用到）
struct UnavailableRelayIdentity: RelayIdentity {
    func fingerprint() throws(IdentityError) -> Fingerprint { throw .keychainUnavailable(errSecNotAvailable) }
    func storedFingerprint() -> Fingerprint? { nil }
    func warmUp() async throws(IdentityError) { throw .keychainUnavailable(errSecNotAvailable) }
}

final class TransportRelayServer: RelayServing {
    let server: TransportServer
    init(_ server: TransportServer) { self.server = server }
    func start() async throws { _ = try await server.start() }
    func stop() { server.stop() }
    func openPairingWindow() -> QRPairingPayload { server.openPairingWindow() }
    func approvePairing() { server.approvePairing() }
    func rejectPairing() { server.rejectPairing() }
    func cancelPairing() { server.cancelPairing() }
    func revoke(peerID: UUID) { server.revoke(peerID: peerID) }
    func broadcastCatalogChanged(version: String) { server.broadcast(.eventCatalogChanged, CatalogChangedEvent(version: version)) }
    func isConnectionAlive(_ id: UUID) -> Bool { server.isConnectionAlive(id) }
    func broadcastPlayback(_ event: RemoteProtocol.PlaybackEvent) { server.broadcast(.eventPlayback, event) }
    var events: AsyncStream<ServerEvent> { server.events }
}

/// UserDefaults 版偏好；不持有 `UserDefaults` 實例（每次以 suiteName 取用）
final class UserDefaultsRelayPreferences: RelayPreferences {
    static let enabledKey = "relayEnabled"
    static let markerKey = "relayLastWarmedMarker"
    private let suiteName: String?

    init(suiteName: String? = nil) { self.suiteName = suiteName }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    var relayEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var lastWarmedMarker: String? {
        get { defaults.string(forKey: Self.markerKey) }
        set { defaults.set(newValue, forKey: Self.markerKey) }
    }
}

/// 測試與自動化用：只在記憶體
final class InMemoryRelayPreferences: RelayPreferences, @unchecked Sendable {
    // MainActor 上的 RelayHost 是唯一讀寫者；@unchecked 只因協定要求 Sendable
    var relayEnabled = false
    var lastWarmedMarker: String?
}

enum CodeSignature {
    /// 本程式的完整 CDHash（十六進位）；取不到回 nil（CR-011：fail closed）。行程內不變，只算一次
    static func currentCDHash() -> String? { cachedCDHash }

    private static let cachedCDHash: String? = computeCDHash()

    private static func computeCDHash() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any], let unique = dictionary[kSecCodeInfoUnique as String] as? Data,
              !unique.isEmpty else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}

/// 螢幕鎖定／睡眠／喚醒 → RelayHost（CR-010 ②(l)）。`com.apple.screenIsLocked` 屬非正式通知名稱（§9 風險 ③）
@MainActor
final class RelayLifecycleObserver {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start(_ handler: @escaping @MainActor (RelayLifecycleEvent) -> Void) {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(NotificationCenter, Notification.Name, RelayLifecycleEvent)] = [
            (distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenUnlocked),
            (workspace, NSWorkspace.willSleepNotification, .willSleep),
            (workspace, NSWorkspace.didWakeNotification, .didWake),
        ]
        for (center, name, event) in pairs {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(event) }
            }
            tokens.append((center, token))
        }
    }

    func stop() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens = []
    }
}

extension RelayHost {
    /// 中繼關閉、永遠不碰 Keychain 與網路的實例（單元／UI 測試與預設參數用）
    static func inert() -> RelayHost {
        RelayHost(dependencies: RelayDependencies(
            identity: UnavailableRelayIdentity(), trust: InMemoryTrustStore(), preferences: InMemoryRelayPreferences(),
            catalog: InertRelayCatalog(), playback: InertRelayPlayback(), cdHash: { nil }, makeServer: { throw CancellationError() }, now: { Date() }))
    }
}
