import Foundation
import RemoteProtocol
import RemoteTransport

/// 已建立的連線（ConnectionViewModel 只需要名稱、是否還開著、關閉與等待結束）
protocol RemoteSessionHandle: AnyObject, Sendable {
    var macName: String { get }
    /// 曲庫請求（S3）
    var client: any EchoClient { get }
    /// 播放請求與狀態（S4）；與 client 為同一個連線上的同一個實例
    var playback: any PlaybackClient { get }
    var isOpen: Bool { get }
    func close()
    func waitUntilClosed() async
}

/// iPad 對 Mac 的配對與連線（外部邊界：protocol＋替身）
protocol RemoteConnecting: Sendable {
    var hasPairedMac: Bool { get }
    func pair(payload: QRPairingPayload, deviceName: String, onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult
    /// `discoveryWindow`：Bonjour 等多久。一般 4 s；上次完全看不到 Mac 時用 30 s 的「等 Mac 出現」窗，
    /// 同一個瀏覽器看到就直接連它的位址（S4 F14，thecure 2026-10-19）
    func connect(discoveryWindow: TimeInterval) async -> Result<any RemoteSessionHandle, ConnectFailure>
    /// 只刪 iPad 端的信任紀錄（Mac 端那筆對安全無影響，§4.12）
    func forgetMacs()
}

enum DiscoveryWindow {
    static let standard: TimeInterval = 4
    static let waitingForMac: TimeInterval = 30
}

extension RemoteConnecting {
    func connect() async -> Result<any RemoteSessionHandle, ConnectFailure> { await connect(discoveryWindow: DiscoveryWindow.standard) }
}

final class SessionHandle: RemoteSessionHandle {
    let macName: String
    let session: ClientSession
    /// 只建一次：事件串流只能被分流一次（EventFanout）
    private let live: LiveEchoClient
    init(macName: String, session: ClientSession) {
        self.macName = macName
        self.session = session
        live = LiveEchoClient(requester: session)
    }
    var client: any EchoClient { live }
    var playback: any PlaybackClient { live }
    var isOpen: Bool { session.isOpen }
    func close() { session.close() }
    func waitUntilClosed() async { await session.waitUntilClosed() }
}

/// 對單一 Mac 的一次嘗試（正式版包 TransportClient；測試以替身驗證挑選邏輯）
protocol MacAttempting: Sendable {
    func pair(_ mac: DiscoveredMac, payload: QRPairingPayload, deviceName: String,
              onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult
    func connect(_ mac: DiscoveredMac) async -> Result<any RemoteSessionHandle, ConnectFailure>
}

struct TransportMacAttempts: MacAttempting {
    let client: TransportClient

    func pair(_ mac: DiscoveredMac, payload: QRPairingPayload, deviceName: String,
              onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult {
        await client.pair(endpoint: mac.endpoint, payload: payload, deviceName: deviceName, onPending: onPending)
    }

    func connect(_ mac: DiscoveredMac) async -> Result<any RemoteSessionHandle, ConnectFailure> {
        await client.connect(endpoint: mac.endpoint).map { SessionHandle(macName: mac.name, session: $0) }
    }
}

/// 正式版：Keychain 身分＋UserDefaults 信任紀錄＋Bonjour 尋址（實例名只作提示，身分由釘選決定）
final class LiveRemoteConnector: RemoteConnecting {
    typealias Discover = @Sendable (_ preferring: Set<String>, _ window: TimeInterval) async -> [DiscoveredMac]
    typealias MakeAttempts = @Sendable (DeviceIdentity) -> any MacAttempting

    static let identityService = "com.ibridgezhao.yogsothothsecho.identity"

    private let identityStore: any DeviceIdentityStore
    private let trust: any TrustStore
    private let discover: Discover
    private let makeAttempts: MakeAttempts

    init(identityStore: any DeviceIdentityStore, trust: any TrustStore, discover: @escaping Discover,
         makeAttempts: @escaping MakeAttempts) {
        self.identityStore = identityStore
        self.trust = trust
        self.discover = discover
        self.makeAttempts = makeAttempts
    }

    /// `service`／`defaultsSuite` 只給測試換成隔離的 Keychain service 與 UserDefaults suite
    convenience init(service: String = identityService, defaultsSuite: String? = nil,
                     audit: any AuditSink = RenderingAuditSink(output: OSLogAuditOutput(subsystem: "com.ibridgezhao.yogsothothsecho"))) {
        let trust = UserDefaultsTrustStore(suiteName: defaultsSuite, audit: audit)
        self.init(identityStore: KeychainDeviceIdentityStore(service: service, defaultsSuite: defaultsSuite, audit: audit), trust: trust,
                  discover: { await Self.bonjourDiscover(preferring: $0, window: $1) },
                  makeAttempts: { identity in
                      TransportMacAttempts(client: TransportClient(configuration: ClientConfiguration(identity: identity, trust: trust,
                                                                                                      audit: audit)))
                  })
    }

    var hasPairedMac: Bool {
        guard let identity = try? identityStore.loadOrCreate() else { return false }
        return !trust.validRecords(for: identity.fingerprint).isEmpty
    }

    private func attempts() -> (any MacAttempting)? {
        guard let identity = try? identityStore.loadOrCreate() else { return nil }
        return makeAttempts(identity)
    }

    /// 收集 Bonjour 結果（LOW-6：分批到達的不漏掉）：看到偏好的實例名（QR 上那台、或任一台配對過的）就提早返回，否則等滿時窗
    static func bonjourDiscover(preferring names: Set<String>, window: TimeInterval = DiscoveryWindow.standard) async -> [DiscoveredMac] {
        await discover(in: MacBrowser().results(), preferring: names, window: window)
    }

    /// 什麼都沒看到時一定等滿時窗（瀏覽器一開就失敗、串流立刻結束時，不讓重連迴圈空轉）
    static func discover(in results: AsyncStream<[DiscoveredMac]>, preferring names: Set<String>, window: TimeInterval) async -> [DiscoveredMac] {
        let started = ContinuousClock.now
        let found = await MacBrowser.gather(results, window: .seconds(window)) { macs in macs.contains { names.contains($0.name) } }
        if found.isEmpty { try? await Task.sleep(until: started + .seconds(window)) }   // 被取消即返回
        return MacBrowser.order(found, preferringAny: names)
    }

    func pair(payload: QRPairingPayload, deviceName: String, onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult {
        guard let attempts = attempts() else { return .failed(.network) }
        let macs = await discover([payload.instanceName], DiscoveryWindow.standard)
        guard !macs.isEmpty else { return .failed(.notFound) }
        var last: PairingAttemptResult = .failed(.notFound)
        for mac in macs {
            last = await attempts.pair(mac, payload: payload, deviceName: deviceName, onPending: onPending)
            // 釘選不符＝不是 QR 上那台，換下一個；其他結果都是那台 Mac 的回答
            if last != .failed(.macPinMismatch) { return last }
        }
        return last
    }

    func connect(discoveryWindow: TimeInterval) async -> Result<any RemoteSessionHandle, ConnectFailure> {
        guard let attempts = attempts() else { return .failure(.network) }
        guard hasPairedMac else { return .failure(.notPaired) }
        // 每一台配對過的 Mac 的實例名（配對時存的，DeviceName.sanitize 後）都當偏好：看到任一台就提早返回（S3 LOW-6、S4 F14）
        let preferred = (try? identityStore.loadOrCreate()).map { Set(trust.validRecords(for: $0.fingerprint).map(\.name)) } ?? []
        let macs = await discover(preferred, discoveryWindow)
        guard !macs.isEmpty else { return .failure(.notFound) }
        // 全部釘選不符＝看得到別台中繼、看不到配對的那台：照一般退避（security LOW-1）
        var failure: ConnectFailure = .otherMacsOnly
        for mac in macs {
            switch await attempts.connect(mac) {
            case .success(let session): return .success(session)
            case .failure(.pinMismatch): continue   // 別台 Mac
            case .failure(let error): failure = error
            }
        }
        return .failure(failure)
    }

    func forgetMacs() { try? trust.removeAll() }
}
