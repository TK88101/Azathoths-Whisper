import Foundation
import Network
import RemoteProtocol

public struct ServerConfiguration: Sendable {
    public var identity: DeviceIdentity
    public var trust: any TrustStore
    public var audit: any AuditSink
    /// Bonjour 實例名；nil＝不廣播（測試）
    public var serviceName: String?
    public var interfaces: @Sendable () -> [NetworkInterface]
    /// loopback 是否算區網（正式＝true 也無妨：loopback 只可能是本機）
    public var allowLoopback: Bool
    /// 配對窗用的時鐘（可注入）；限流、心跳、握手期限用實際時間
    public var now: @Sendable () -> Date
    public var timings: TransportTimings
    public var limits: ServerLimits
    /// 正常路徑的業務請求處理者（S3）；nil＝與 S2 相同，一律 invalidRequest
    public var requestHandler: (any RequestHandling)?

    public init(identity: DeviceIdentity, trust: any TrustStore, audit: any AuditSink, serviceName: String?,
                interfaces: @escaping @Sendable () -> [NetworkInterface] = { NetworkInterface.current() },
                allowLoopback: Bool = true, now: @escaping @Sendable () -> Date = { Date() },
                timings: TransportTimings = .production, limits: ServerLimits = .standard,
                requestHandler: (any RequestHandling)? = nil) {
        self.identity = identity
        self.trust = trust
        self.audit = audit
        self.serviceName = serviceName
        self.interfaces = interfaces
        self.allowLoopback = allowLoopback
        self.now = now
        self.timings = timings
        self.limits = limits
        self.requestHandler = requestHandler
    }
}

public enum ServerEvent: Equatable, Sendable {
    case pairingPending(name: String, suffix: String)
    case pairingFinished(PairOutcome)
    case peerConnected(UUID)
    case peerDisconnected(UUID)
    case listenerFailed
}

public struct PendingPairing: Equatable, Sendable {
    public let name: String
    public let suffix: String
}

public enum ServerError: Error, Sendable {
    case listener
}

/// Mac 端（sprint-2-detail.md §4.7）。所有可變狀態在單一鎖內；Network 回呼在 `networkQueue`；
/// 鎖內只做純狀態轉移，送訊息與 cancel 在鎖外。stored property 全為 `let` 且 Sendable。
public final class TransportServer: Sendable {
    enum Role: Equatable, Sendable {
        case unclassified, pairing, normal(UUID)
    }

    struct Entry: Sendable {
        let connection: NWConnection
        let source: String
        var role: Role = .unclassified
        /// TLS ready 後才會分類；仍未分類＝握手未完成
        var isClassified: Bool { role != .unclassified }
        /// 配對連線的 proof 已被接受（進過 pending）：之後由配對窗狀態機的效果負責關閉，巡檢不碰
        var proofAccepted = false
        /// 分類完成的時刻；proof 期限自此起算（不看會被 ping 刷新的 lastActivity；security 補查）
        var classifiedAt: Date?
        /// 在配對路徑上、尚未交出有效 proof（換窗、窗關閉、proof 逾期時都要斷的那一類）——唯一判定處
        var isUnprovenPairing: Bool { role == .pairing && !proofAccepted }
        var replay: ReplayGuard?
        var control: TokenBucket
        var read: TokenBucket
        var pings: TokenBucket
        var lastActivity: Date
        /// 已交給處理者、尚未回覆的工作（只為斷線時取消；名額按 peer 計，見 State）
        var tasks: [UUID: Task<Void, Never>] = [:]
        /// 伺服端 ping 的 pong（security review HIGH-1）：iPad 要讀到 ping 才能回，回得了＝有在讀；
        /// 逾期沒有 pong 的正常連線由巡檢關閉，不讀的 iPad 讓 Mac 堆積的回覆因此有上限
        var lastPong: Date?
        /// 尚未被回應的 ping 隨機內容（RFC 6455：pong 必須帶回相同內容；只接受相符者，偽造 pong 無效——security 複核 NEW-1）
        var pendingPing: Data?
        var lastServerPing: Date?
        /// 被拒絕的請求計數（1 秒窗）：遠超正常上限＝濫用，直接斷線（security review HIGH-1）
        var rejectionWindowStart: Date?
        var rejectionsInWindow = 0
        /// 拒絕類稽核的取樣時刻（每連線每秒最多 1 筆；security review LOW-2）
        var lastRejectionAudit: Date?
    }

    struct State: Sendable {
        var running = false
        var window = PairingWindow()
        var pending: PendingPairing?
        var entries: [ConnectionID: Entry] = [:]
        var newGlobal: KeyedRateLimiter<String>
        var newPerSource: KeyedRateLimiter<String>
        var version: UInt64 = 0
        var verifyCount = 0
        var nonHostPortInbound = 0
        /// 在途名額按 peer 計、在工作真正結束時才歸還（不在斷線或被取代時歸還；security review HIGH-2）
        var peerInFlight: [UUID: Int] = [:]
        var peerArtworkInFlight: [UUID: Int] = [:]
        var artworkInFlightTotal = 0
        var ledger: SendLedger
        /// 測試用計數：正常路徑實際處理的 frame 數、撤銷期限到時強制關閉的連線數
        var normalFramesHandled = 0
        var forcedCloses = 0

        /// 從表上移除一條連線：釋放待送帳、取消在途工作（`Task.cancel()` 不阻塞，處理者的取消回呼不會回呼本物件）。
        /// 在途名額不在此歸還——工作可能仍在跑，等它結束時由 complete 歸還。只由 TransportServer.detach 呼叫
        mutating func removeEntry(_ id: ConnectionID) -> Entry? {
            guard let entry = entries.removeValue(forKey: id) else { return nil }
            ledger.releaseAll(for: id)
            entry.tasks.values.forEach { $0.cancel() }
            return entry
        }
    }

    let configuration: ServerConfiguration
    let gate = PairingGate()
    private let state: Locked<State>
    private let listenerBox = Locked<NWListener?>(nil)
    /// 配對事件的線性化點（F-2）：轉移＋其效果（含 `ServerEvent` 送出）整段串行，事件順序＝轉移順序。
    /// 鎖序固定 `pairingSerial → state`；持 `state` 時不得取它。效果內呼叫的 `AuditSink`／`TrustStore` 不得同步回呼本物件
    private let pairingSerial = NSLock()
    /// 測試接縫：classify 進狀態鎖（讀信任紀錄並定角色）之前呼叫（LOW-1 測試用；生產碼不設）
    let classifySeam = Locked<(@Sendable () -> Void)?>(nil)
    /// 測試接縫：配對轉移後、執行效果前呼叫（F-2 紅燈測試用；生產碼不設）
    let afterTransitionSeam = Locked<(@Sendable ([PairingEffect]) -> Void)?>(nil)
    private let networkQueue = DispatchQueue(label: "yse.transport.server")
    private let verifyQueue = DispatchQueue(label: "yse.transport.server.verify")
    /// 握手期限與巡檢在獨立 queue：網路 queue 被佔住時仍會觸發（§4.7）
    private let watchdogQueue = DispatchQueue(label: "yse.watchdog")
    private let gateQueue = DispatchQueue(label: "yse.transport.gate")
    private let continuation: AsyncStream<ServerEvent>.Continuation
    public let events: AsyncStream<ServerEvent>

    public init(configuration: ServerConfiguration) {
        self.configuration = configuration
        let limits = configuration.limits
        state = Locked(State(
            newGlobal: KeyedRateLimiter(capacity: limits.newConnectionsPerSecond, refillPerSecond: Double(limits.newConnectionsPerSecond)),
            newPerSource: KeyedRateLimiter(capacity: limits.newConnectionsPerSourcePerSecond,
                                           refillPerSecond: Double(limits.newConnectionsPerSourcePerSecond)),
            ledger: SendLedger(perConnectionLimit: limits.maxPendingSendBytesPerConnection,
                               totalLimit: limits.maxPendingSendBytesTotal)))
        (events, continuation) = AsyncStream.makeStream()
    }

    // MARK: 對外狀態（設定頁與測試用）

    public var isPairingOpen: Bool { state.withLock { $0.window.isOpen } }
    public var pendingPairing: PendingPairing? { state.withLock { $0.pending } }
    public var connectedPeers: [UUID] {
        state.withLock { $0.entries.values.compactMap { if case .normal(let id) = $0.role { id } else { nil } } }
    }
    var unclassifiedCount: Int { state.withLock { $0.entries.values.filter { !$0.isClassified }.count } }
    var hasPairingConnection: Bool { state.withLock { $0.entries.values.contains { $0.role == .pairing } } }
    var verifyCount: Int { state.withLock { $0.verifyCount } }
    var nonHostPortInbound: Int { state.withLock { $0.nonHostPortInbound } }
    var artworkInFlightTotal: Int { state.withLock { $0.artworkInFlightTotal } }
    var pendingSendBytesTotal: Int { state.withLock { $0.ledger.total } }
    var normalFramesHandled: Int { state.withLock { $0.normalFramesHandled } }
    var forcedCloses: Int { state.withLock { $0.forcedCloses } }
    /// revoke 送出 notPaired 後，對端不讀也要在此期限內強制關閉（security review LOW-1）
    static let revokeCloseDeadline: TimeInterval = 2
    /// 測試用：把網路 queue 佔住一段時間（驗 watchdog 不依賴它，§4.7）；佔住結束後呼叫 `released`
    func occupyNetworkQueue(for seconds: TimeInterval, released: @escaping @Sendable () -> Void) {
        networkQueue.async {
            Thread.sleep(forTimeInterval: seconds)
            released()
        }
    }

    // MARK: 生命週期

    public func start() async throws -> NWEndpoint.Port {
        let parameters = TLSConfiguration.parameters(identity: configuration.identity, role: .server, verifyQueue: verifyQueue) {
            [weak self] fingerprint in self?.verify(fingerprint) ?? false
        }
        guard let listener = try? NWListener(using: parameters, on: .any) else { throw ServerError.listener }
        if let name = configuration.serviceName { listener.service = NWListener.Service(name: name, type: EchoService.type) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listenerBox.withLock { $0 = listener }
        state.withLock { $0.running = true }
        refreshGate()
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let resumed = Locked(false)
            /// 只在第一次到達終態時 resume；之後的失敗改為事件
            let claim: @Sendable () -> Bool = { resumed.withLock { done in defer { done = true }; return !done } }
            listener.stateUpdateHandler = { [weak self] update in
                switch update {
                case .ready:
                    if let port = listener.port, claim() { continuation.resume(returning: port) }
                case .failed, .cancelled:
                    if claim() { continuation.resume(throwing: ServerError.listener) } else { self?.continuation.yield(.listenerFailed) }
                default:
                    break
                }
            }
            listener.start(queue: networkQueue)
        }
        scheduleSweep()
        return port
    }

    public func stop() {
        let connections = pairingStep { s -> ([NWConnection], [PairingEffect]) in
            s.running = false
            let effects = s.window.cancel()
            s.pending = nil
            let all = Array(s.entries.keys).compactMap { self.detach(&s, $0, announce: false)?.connection }
            return (all, effects)
        }
        listenerBox.withLock { $0?.cancel(); $0 = nil }
        connections.forEach { $0.cancel() }
        refreshGate()
    }

    // MARK: 配對（RelayHost 呼叫）

    public func openPairingWindow() -> QRPairingPayload {
        let identity = configuration.identity
        let name = configuration.serviceName ?? EchoService.instanceName(for: identity.fingerprint)
        let (payload, _) = pairingStep({ s -> ((QRPairingPayload, [NWConnection]), [PairingEffect]) in
            let (payload, effects) = s.window.open(sessionID: Random.bytes(TransportLimits.sessionIDBytes), secret: Random.bytes(32),
                                                   macFingerprint: identity.fingerprint, instanceName: name, now: configuration.now())
            s.pending = nil
            // 舊窗留下、未交有效 proof 的配對連線不得延續到新窗（open() 原子換窗，巡檢看不到窗關閉的空檔；security 補查）
            let unprovenIDs = s.entries.filter { $0.value.isUnprovenPairing }.map(\.key)
            return ((payload, unprovenIDs.compactMap { self.detach(&s, $0)?.connection }), effects)
        }, beforePerform: { _, unproven in unproven.forEach { self.reject(.pairingUnavailable, on: $0, close: true) } })
        refreshGate()
        return payload
    }

    public func approvePairing() { transition { $0.approve(peerID: UUID(), now: self.configuration.now()) } }
    public func rejectPairing() { transition { $0.reject() } }
    public func cancelPairing() { transition { $0.cancel() } }

    /// 解除：只刪該對端信任紀錄並立即中斷，不刪本機身分（CR-010 ③）
    public func revoke(peerID: UUID) {
        // 線性化點（LOW-1）：同一把鎖內「刪信任紀錄 → 摘除該 peer 的正常連線」；classify 也在這把鎖內讀信任紀錄。
        // TrustStore 協定規定不得同步回呼本物件，鎖內呼叫安全
        let doomed = state.withLock { s -> [NWConnection] in
            try? configuration.trust.remove(peerID: peerID)
            let ids = s.entries.filter { $0.value.role == .normal(peerID) }.map(\.key)
            return ids.compactMap { self.detach(&s, $0)?.connection }
        }
        refreshGate()
        doomed.forEach { connection in
            Wire.send(Wire.error(.notPaired), on: connection)
            Wire.closeAfterPendingSends(connection)
            // 對端不讀時送不完、永遠關不掉：期限到就強制關（security review LOW-1）
            watchdogQueue.asyncAfter(deadline: .now() + Self.revokeCloseDeadline) { [weak self] in
                guard connection.state != .cancelled else { return }
                connection.cancel()
                self?.state.withLock { $0.forcedCloses += 1 }
            }
        }
        configuration.audit.record(.peerRevoked(peerID: peerID))
    }

    private func transition(_ body: @Sendable (inout PairingWindow) -> [PairingEffect]) {
        pairingStep { s -> ((), [PairingEffect]) in
            let effects = body(&s.window)
            if s.window.outcome != nil { s.pending = nil }
            return ((), effects)
        }
        refreshGate()
    }

    /// 配對窗轉移的唯一入口（F-2，`docs/plans/2026-10-17-yse-f2-pairing-event-order.md`）：狀態鎖內轉移，鎖外執行效果；
    /// 兩段都在 `pairingSerial` 內，下一個轉移要等本次效果做完（`recordPeer` 先於 `.pairingFinished(.approved)` 的次序不變）
    private func pairingStep<R: Sendable>(_ body: @Sendable (inout State) -> (R, [PairingEffect]),
                                          beforePerform: (R) -> Void = { _ in }) -> R {
        pairingSerial.lock()
        defer { pairingSerial.unlock() }
        let (result, effects) = state.withLock(body)
        if let seam = afterTransitionSeam.withLock({ $0 }) { seam(effects) }
        beforePerform(result)
        perform(effects)
        return result
    }

    // MARK: 閘門快照（序列化發布，避免舊快照覆寫新快照）

    func refreshGate() {
        gateQueue.sync {
            let trusted = Set(configuration.trust.validRecords(for: configuration.identity.fingerprint).map(\.fingerprint))
            let snapshot = state.withLock { s -> PairingGate.Snapshot in
                s.version += 1
                return PairingGate.Snapshot(version: s.version, trusted: s.running ? trusted : [], pairingOpen: s.running && s.window.isOpen)
            }
            gate.publish(snapshot)
        }
    }

    func verifyForTesting(_ fingerprint: Fingerprint?) -> Bool { verify(fingerprint) }

    /// verify block（verifyQueue）：先讀快照（gate 鎖）→ 釋放 → 再進狀態鎖計數。兩把鎖永不巢狀（§4.7 鎖序）
    private func verify(_ fingerprint: Fingerprint?) -> Bool {
        guard let fingerprint else { return false }
        let admission = gate.admits(fingerprint)
        let cooling = state.withLock { s in
            s.verifyCount += 1
            return s.window.isCoolingDown(now: configuration.now())
        }
        switch admission {
        case .trusted:
            return true
        case .pairingCandidate where !cooling:
            return true
        case .pairingCandidate:
            configuration.audit.record(.connectionRejected(.cooldown))
            return false
        case .reject:
            configuration.audit.record(.connectionRejected(.unknownPeer))
            return false
        }
    }

    // MARK: 接受連線（start 之前：區網、名額、速率）

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint, let address = IPAddressBytes(host: host) else {
            state.withLock { $0.nonHostPortInbound += 1 }
            connection.cancel()
            configuration.audit.record(.connectionRejected(.notOnLink))
            return
        }
        guard LocalNetworkPolicy.isOnLink(address, interfaces: configuration.interfaces(), allowLoopback: configuration.allowLoopback) else {
            connection.cancel()
            configuration.audit.record(.nonLocalPeer)
            return
        }
        let source = address.normalized.base64EncodedString()
        let id = ConnectionID()
        let realNow = Date()
        let limits = configuration.limits
        let verdict = state.withLock { s -> AuditEvent? in
            guard s.running else { return .connectionRejected(.capacity) }
            guard s.newGlobal.take("all", now: realNow), s.newPerSource.take(source, now: realNow) else {
                return .rateLimited(.newConnection)
            }
            let unclassified = s.entries.values.filter { $0.role == .unclassified }
            guard unclassified.count < limits.maxUnclassified,
                  unclassified.filter({ $0.source == source }).count < limits.maxUnclassifiedPerSource else {
                return .connectionRejected(.capacity)
            }
            s.entries[id] = Entry(connection: connection, source: source,
                                  control: TokenBucket(capacity: TransportLimits.controlPerSecond,
                                                       refillPerSecond: Double(TransportLimits.controlPerSecond), now: realNow),
                                  read: TokenBucket(capacity: limits.readPerSecond, refillPerSecond: Double(limits.readPerSecond),
                                                    now: realNow),
                                  pings: TokenBucket(capacity: TransportLimits.maxPingsPerSecond,
                                                     refillPerSecond: Double(TransportLimits.maxPingsPerSecond), now: realNow),
                                  lastActivity: realNow)
            return nil
        }
        if let verdict {
            connection.cancel()
            configuration.audit.record(verdict)
            return
        }
        connection.stateUpdateHandler = { [weak self] update in self?.connection(id, changed: update) }
        connection.start(queue: networkQueue)
        watchdogQueue.asyncAfter(deadline: .now() + configuration.timings.handshakeTimeout) { [weak self] in
            self?.handshakeDeadline(id)
        }
    }

    private func handshakeDeadline(_ id: ConnectionID) {
        let stalled = state.withLock { s -> NWConnection? in
            guard let entry = s.entries[id], !entry.isClassified else { return nil }
            _ = self.detach(&s, id)
            return entry.connection
        }
        guard let stalled else { return }
        stalled.cancel()
        configuration.audit.record(.handshakeTimeout)
    }

    private func connection(_ id: ConnectionID, changed update: NWConnection.State) {
        switch update {
        case .ready:
            classify(id)
        case .failed:
            let (removed, countsAsInvalidTLS) = state.withLock { s -> (Entry?, Bool) in
                let entry = self.detach(&s, id)
                let invalid = entry.map { !$0.isClassified && s.window.isOpen } ?? false
                if invalid { s.window.recordInvalidAttempt(now: configuration.now()) }
                return (entry, invalid)
            }
            if countsAsInvalidTLS { configuration.audit.record(.invalidTLS) }
            removed?.connection.cancel()
            closed(id, entry: removed)
        case .cancelled:
            closed(id, entry: state.withLock { self.detach(&$0, id) })
        default:
            break
        }
    }

    private func closed(_ id: ConnectionID, entry: Entry?) {
        let changed = pairingStep { s -> (Bool, [PairingEffect]) in
            let effects = s.window.connectionClosed(id)
            if !effects.isEmpty { s.pending = nil }
            return (!effects.isEmpty, effects)
        }
        if changed { refreshGate() }
    }

    private enum Classification {
        /// replaced＝同一 peer 被取代的舊正常連線（已摘下、在鎖外關閉；不送 peerDisconnected，peer 仍在線）
        case accepted(Role, replaced: [NWConnection])
        /// 配對窗開著但配對路徑已被佔用：告知「已失效」再斷（正牌 iPad 立即得到 unavailable）
        case pairingSlotTaken
        case rejected
    }

    /// ready 後在狀態鎖內以真狀態再確認角色（快照可能過期）；被拒的連線一律在鎖外斷開（security review S2 M-2）
    private func classify(_ id: ConnectionID) {
        guard let connection = connectionFor(id) else { return }
        let fingerprint = TLSConfiguration.peerFingerprint(connection)
        let nonce = Random.bytes(TransportLimits.nonceBytes)
        if let seam = classifySeam.withLock({ $0 }) { seam() }
        finishClassify(decide(id, fingerprint: fingerprint, nonce: nonce), connection: connection, id: id, nonce: nonce)
    }

    /// 進鎖讀信任紀錄並以真狀態定角色（與 revoke 同一把鎖：讀取與判定是原子的，LOW-1）
    private func decide(_ id: ConnectionID, fingerprint: Fingerprint?, nonce: Data) -> Classification {
        state.withLock { s -> Classification in
            let records = configuration.trust.validRecords(for: configuration.identity.fingerprint)
            guard var entry = s.entries[id] else { return .rejected }
            guard let fingerprint else {
                _ = self.detach(&s, id)
                return .rejected
            }
            var replaced: [NWConnection] = []
            if let record = records.first(where: { $0.fingerprint == fingerprint }) {
                entry.role = .normal(record.peerID)
                entry.replay = ReplayGuard(nonce: nonce)
                // 每 peer 一條正常連線（CR-012）：新連線取代舊連線（peer 仍在線，不送 disconnected）
                let older = s.entries.filter { $0.key != id && $0.value.role == .normal(record.peerID) }.map(\.key)
                replaced = older.compactMap { self.detach(&s, $0, announce: false)?.connection }
            } else if s.window.isOpen, !s.entries.values.contains(where: { $0.role == .pairing }) {
                entry.role = .pairing
            } else {
                _ = self.detach(&s, id)
                return s.window.isOpen ? .pairingSlotTaken : .rejected
            }
            entry.lastActivity = Date()
            entry.classifiedAt = entry.lastActivity
            entry.lastPong = entry.lastActivity
            s.entries[id] = entry
            if case .normal(let peerID) = entry.role { continuation.yield(.peerConnected(peerID)) }
            return .accepted(entry.role, replaced: replaced)
        }
    }

    private func finishClassify(_ verdict: Classification, connection: NWConnection, id: ConnectionID, nonce: Data) {
        switch verdict {
        case .rejected:
            connection.cancel()
            configuration.audit.record(.connectionRejected(.unknownPeer))
        case .pairingSlotTaken:
            reject(.pairingUnavailable, on: connection, close: true)
            configuration.audit.record(.connectionRejected(.unknownPeer))
        case .accepted(let role, let replaced):
            replaced.forEach { $0.cancel() }
            // 鎖外：期間可能已被 revoke 摘下（已送 notPaired 並關閉），那就不送 hello、不開始收訊
            guard state.withLock({ $0.entries[id] != nil }) else { return }
            if case .normal = role {
                Wire.send(Wire.encode(.sessionHello, SessionHello(sessionNonce: nonce)), on: connection)
            }
            receive(id, on: connection)
        }
    }

    // MARK: 收訊

    private func receive(_ id: ConnectionID, on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            guard error == nil else { connection.cancel(); return }
            switch Wire.opcode(context) {
            case .ping?:
                guard self.acceptPing(id) else {
                    self.configuration.audit.record(.pingFlood)
                    connection.cancel()
                    return
                }
                Wire.sendControl(.pong, on: connection)
            case .pong?:
                self.state.withLock { s in
                    guard let expected = s.entries[id]?.pendingPing, expected == (data ?? Data()) else { return }
                    s.entries[id]?.pendingPing = nil
                    s.entries[id]?.lastPong = Date()
                }
            case .close?:
                connection.cancel()
                return
            default:
                if let data, !data.isEmpty, !self.handle(data, from: id, on: connection) { return }
            }
            self.receive(id, on: connection)
        }
    }

    private func released(_ reservation: SendLedger.Token) {
        state.withLock { $0.ledger.release(reservation) }
    }

    private func acceptPing(_ id: ConnectionID) -> Bool {
        let now = Date()
        return state.withLock { s in
            guard let ok = s.entries[id]?.pings.take(now: now) else { return false }
            s.entries[id]?.lastActivity = now
            return ok
        }
    }

    /// 回傳 false＝連線已關，停止收訊
    private func handle(_ data: Data, from id: ConnectionID, on connection: NWConnection) -> Bool {
        guard let role = state.withLock({ $0.entries[id]?.role }) else { return false }
        switch role {
        case .pairing: return handlePairing(data, from: id, on: connection)
        case .normal: return handleNormal(data, from: id, on: connection)
        case .unclassified: return true
        }
    }

    private func reject(_ code: ErrorCode, replyingTo requestID: UUID = UUID(), on connection: NWConnection, close: Bool) {
        Wire.send(Wire.error(code, replyingTo: requestID), on: connection)
        if close { Wire.closeAfterPendingSends(connection) }
    }

    /// 每秒被拒絕超過這個數＝濫用（正常 iPad 受自己的節流限制，不會接近；busy 不計）
    static var maxRejectionsPerSecond: Int { 3 * TransportLimits.controlPerSecond }

    /// 正常路徑的錯誤回覆：一樣記待送帳（不豁免小訊息），帳滿就不回。每秒拒絕次數遠超正常上限就斷線
    private func rejectNormal(_ code: ErrorCode, replyingTo requestID: UUID = UUID(), id: ConnectionID, on connection: NWConnection,
                              close: Bool = false) {
        if code != .busy, countRejectionIsAbusive(id) {
            configuration.audit.record(.rateLimited(.control))
            let doomed = state.withLock { self.detach(&$0, id)?.connection }
            doomed?.cancel()
            return
        }
        sendCounted(Wire.error(code, replyingTo: requestID), to: id, on: connection)
        if close { Wire.closeAfterPendingSends(connection) }
    }

    private func countRejectionIsAbusive(_ id: ConnectionID) -> Bool {
        let now = Date()
        return state.withLock { s -> Bool in
            guard var entry = s.entries[id] else { return false }
            if let start = entry.rejectionWindowStart, now.timeIntervalSince(start) < 1 {
                entry.rejectionsInWindow += 1
            } else {
                entry.rejectionWindowStart = now
                entry.rejectionsInWindow = 1
            }
            s.entries[id] = entry
            return entry.rejectionsInWindow > Self.maxRejectionsPerSecond
        }
    }

    /// 拒絕類稽核取樣：每連線每秒最多 1 筆（security review LOW-2；內容本就只有封閉列舉）
    private func auditRejection(_ event: AuditEvent, _ id: ConnectionID, now: Date) {
        let record = state.withLock { s -> Bool in
            guard let last = s.entries[id]?.lastRejectionAudit, now.timeIntervalSince(last) < 1 else {
                s.entries[id]?.lastRejectionAudit = now
                return true
            }
            return false
        }
        if record { configuration.audit.record(event) }
    }

    private func handlePairing(_ data: Data, from id: ConnectionID, on connection: NWConnection) -> Bool {
        guard case .success(let header) = EnvelopeHeader.decode(data),
              EnvelopeRules.check(header, direction: .fromIPad, path: .pairing) == nil else {
            configuration.audit.record(.connectionRejected(.pathMismatch))
            reject(.invalidRequest, on: connection, close: true)
            return false
        }
        guard let fingerprint = TLSConfiguration.peerFingerprint(connection), let exporter = TLSConfiguration.exporter(connection) else {
            connection.cancel()
            return false
        }
        let body = Wire.body(data, as: PairProof.self) ?? PairProof(sessionID: Data(), proof: Data(), deviceName: "")
        let now = configuration.now()
        let keepOpen = pairingStep { s -> (Bool, [PairingEffect]) in
            let effects = s.window.handleProof(body, from: id, ipadFingerprint: fingerprint, exporter: exporter, now: now)
            for case .showConfirm(let name, let suffix) in effects { s.pending = PendingPairing(name: name, suffix: suffix) }
            if s.window.pendingConnection == id { s.entries[id]?.proofAccepted = true }
            return (!effects.contains(.close(id)), effects)
        }
        refreshGate()
        return keepOpen
    }

    private func handleNormal(_ data: Data, from id: ConnectionID, on connection: NWConnection) -> Bool {
        let now = Date()
        state.withLock { $0.normalFramesHandled += 1 }
        let header: EnvelopeHeader
        switch EnvelopeHeader.decode(data) {
        case .success(let decoded): header = decoded
        case .failure(let code):
            // 畸形請求扣控制類配額（保留 S2「先扣 20/s」對畸形輸入的防濫用效果；CR-012）
            guard spend(.control, id, now: now, on: connection) else { return true }
            auditRejection(.connectionRejected(.invalidRequest), id, now: now)
            rejectNormal(code, id: id, on: connection)
            return true
        }
        if let code = EnvelopeRules.check(header, direction: .fromIPad, path: .normal) {
            guard spend(.control, id, now: now, on: connection) else { return true }
            if code == .replayed { auditRejection(.replayRejected, id, now: now) }
            let pathMismatch = code == .invalidRequest && EnvelopeRules.pairKinds.contains(header.kind)
            if pathMismatch { configuration.audit.record(.connectionRejected(.pathMismatch)) }
            rejectNormal(code, replyingTo: header.id, id: id, on: connection, close: pathMismatch)
            return !pathMismatch
        }
        let isRead = EnvelopeRules.readKinds.contains(header.kind)
        guard spend(isRead ? .read : .control, id, now: now, on: connection, replyingTo: header.id) else { return true }
        let replay = state.withLock { s -> ErrorCode? in
            // accept 回傳 ErrorCode?（nil＝通過）：不可接在 optional chaining 後（會與「沒有 entry」混成同一個 nil）
            guard var guardian = s.entries[id]?.replay else { return .replayed }
            let verdict = guardian.accept(nonce: header.nonce, seq: header.seq)
            s.entries[id]?.replay = guardian
            if verdict == nil { s.entries[id]?.lastActivity = now }
            return verdict
        }
        if let replay {
            auditRejection(.replayRejected, id, now: now)
            rejectNormal(replay, replyingTo: header.id, id: id, on: connection)
            return true
        }
        guard let handler = configuration.requestHandler else {
            rejectNormal(.invalidRequest, replyingTo: header.id, id: id, on: connection)
            return true
        }
        if !dispatch(header, data: data, from: id, to: handler) { rejectNormal(.busy, replyingTo: header.id, id: id, on: connection) }
        return true
    }

    /// 扣配額；不足時回 rateLimited 並稽核，回傳 false
    private func spend(_ kind: LimitKind, _ id: ConnectionID, now: Date, on connection: NWConnection,
                       replyingTo requestID: UUID = UUID()) -> Bool {
        let ok = state.withLock { s -> Bool in
            guard var entry = s.entries[id] else { return false }
            let taken = kind == .read ? entry.read.take(now: now) : entry.control.take(now: now)
            s.entries[id] = entry
            return taken
        }
        if !ok {
            auditRejection(.rateLimited(kind), id, now: now)
            rejectNormal(.rateLimited, replyingTo: requestID, id: id, on: connection)
        }
        return ok
    }

    /// 在途上限內才佔名額並建立工作（超額時不建 Task；CR-012）。名額按 peer 計：重連或取代連線拿不回名額，
    /// 要等工作真正結束（security review HIGH-2）。回傳 false＝名額不足，呼叫端回 busy
    private func dispatch(_ header: EnvelopeHeader, data: Data, from id: ConnectionID, to handler: any RequestHandling) -> Bool {
        let limits = configuration.limits
        let isArtwork = EnvelopeRules.artworkKinds.contains(header.kind)
        return state.withLock { s -> Bool in
            guard s.entries[id] != nil, case .normal(let peerID)? = s.entries[id]?.role,
                  s.peerInFlight[peerID, default: 0] < limits.maxInFlightPerConnection else { return false }
            if isArtwork {
                guard s.peerArtworkInFlight[peerID, default: 0] < limits.maxArtworkInFlightPerConnection,
                      s.artworkInFlightTotal < limits.maxArtworkInFlightTotal else { return false }
                s.peerArtworkInFlight[peerID, default: 0] += 1
                s.artworkInFlightTotal += 1
            }
            s.peerInFlight[peerID, default: 0] += 1
            let token = UUID()
            let request = InboundRequest(peerID: peerID, id: header.id, kind: header.kind, message: data, connectionID: id.uuid)
            // 在鎖內建立：工作本體非同步執行，完成時才再取鎖（不會死鎖），且 tasks 一定先登記再被移除
            s.entries[id]?.tasks[token] = Task { [weak self] in
                let reply = await handler.handle(request)
                self?.complete(token, peerID: peerID, connection: id, requestID: header.id, isArtwork: isArtwork, reply: reply)
            }
            return true
        }
    }

    /// 工作結束：一律歸還 peer 名額（連線已摘下也一樣）；連線還在才回覆——編碼後預留實際位元組，不足改回 busy
    private func complete(_ token: UUID, peerID: UUID, connection id: ConnectionID, requestID: UUID, isArtwork: Bool, reply: OutboundReply) {
        let data: Data
        switch reply {
        case .message(let message): data = message
        case .error(let code): data = Wire.error(code, replyingTo: requestID)
        }
        let connection = state.withLock { s -> NWConnection? in
            s.peerInFlight[peerID] = max(0, s.peerInFlight[peerID, default: 0] - 1)
            if isArtwork {
                s.peerArtworkInFlight[peerID] = max(0, s.peerArtworkInFlight[peerID, default: 0] - 1)
                s.artworkInFlightTotal -= 1
            }
            s.entries[id]?.tasks[token] = nil
            return s.entries[id]?.connection
        }
        guard let connection else { return }
        if !sendCounted(data, to: id, on: connection) { sendCounted(Wire.error(.busy, replyingTo: requestID), to: id, on: connection) }
    }

    /// 所有正常路徑的送出都走這裡：先以實際位元組預留待送帳，預留不到就不送；完成回呼以 token 冪等釋放
    @discardableResult
    private func sendCounted(_ payload: Data, to id: ConnectionID, on connection: NWConnection) -> Bool {
        guard let reservation = state.withLock({ $0.ledger.reserve(payload.count, for: id) }) else { return false }
        Wire.send(payload, on: connection, completion: .contentProcessed { [weak self] _ in self?.released(reservation) })
        return true
    }

    /// 該連線是否仍在（正常路徑或分類中皆算）。與連線移除（`State.detach`）同一把鎖，查詢與移除線性化
    public func isConnectionAlive(_ id: UUID) -> Bool {
        state.withLock { s in s.entries.keys.contains { $0.uuid == id } }
    }

    /// 推事件給所有正常路徑連線（配對路徑收不到）。同樣預留待送位元組，預留不到的連線略過該事件
    public func broadcast<Body: Encodable>(_ kind: MessageKind, _ body: Body) {
        let data = Wire.encode(kind, body)
        let targets = state.withLock { s in
            s.entries.compactMap { id, entry -> (ConnectionID, NWConnection)? in
                guard case .normal = entry.role else { return nil }
                return (id, entry.connection)
            }
        }
        targets.forEach { sendCounted(data, to: $0.0, on: $0.1) }
    }

    // MARK: 效果與巡檢

    private func perform(_ effects: [PairingEffect]) {
        for effect in effects {
            switch effect {
            case .recordPeer(let record):
                try? configuration.trust.add(record)
                refreshGate()
            case .sendPending(let id, let suffix):
                connectionFor(id).map { Wire.send(Wire.encode(.pairPending, PairPending(suffix: suffix)), on: $0) }
            case .sendResult(let id, let outcome):
                connectionFor(id).map { Wire.send(Wire.encode(.pairResult, PairResult(outcome: outcome)), on: $0) }
            case .sendError(let id, let code):
                connectionFor(id).map { Wire.send(Wire.error(code), on: $0) }
            case .close(let id):
                if let connection = state.withLock({ self.detach(&$0, id)?.connection }) {
                    Wire.closeAfterPendingSends(connection)
                }
            case .showConfirm(let name, let suffix):
                continuation.yield(.pairingPending(name: name, suffix: suffix))
            case .dismissConfirm:
                break
            case .audit(let event):
                configuration.audit.record(event)
                if case .pairingFinished(let outcome) = event { continuation.yield(.pairingFinished(outcome)) }
            }
        }
    }

    private func connectionFor(_ id: ConnectionID) -> NWConnection? { state.withLock { $0.entries[id]?.connection } }

    /// 唯一的移除點：摘下連線；它若是某 peer 的正常連線，就在同一把狀態鎖內送 peerDisconnected——peerConnected 也在鎖內送，
    /// 兩者順序因此等於狀態順序。只有 stop() 與「新連線取代舊連線」傳 announce: false
    private func detach(_ s: inout State, _ id: ConnectionID, announce: Bool = true) -> Entry? {
        let entry = s.removeEntry(id)
        if announce, case .normal(let peerID) = entry?.role { continuation.yield(.peerDisconnected(peerID)) }
        return entry
    }

    private func scheduleSweep() {
        watchdogQueue.asyncAfter(deadline: .now() + configuration.timings.sweepInterval) { [weak self] in
            guard let self, self.state.withLock({ $0.running }) else { return }
            self.sweep()
            self.scheduleSweep()
        }
    }

    func sweep() {
        let realNow = Date()
        let deadline = configuration.timings.heartbeatDeadline
        let pingInterval = configuration.timings.heartbeatInterval
        let proofDeadline = configuration.timings.handshakeTimeout
        let (hadEffects, idle, stalePairing, windowChanged, toPing) = pairingStep {
            s -> ((Bool, [NWConnection], [NWConnection], Bool, [(NWConnection, Data)]), [PairingEffect]) in
            let wasOpen = s.window.isOpen
            let effects = s.window.tick(now: configuration.now())
            if s.window.outcome != nil { s.pending = nil }
            // 正常連線：iPad 不送 ping（lastActivity）或不回 Mac 的 ping（lastPong＝沒在讀）都算逾期
            let idleIDs = s.entries.filter {
                guard case .normal = $0.value.role else { return false }
                return realNow.timeIntervalSince($0.value.lastActivity) > deadline
                    || realNow.timeIntervalSince($0.value.lastPong ?? .distantPast) > deadline
            }.map(\.key)
            // 一次只留一個未回應的 ping：回了才送下一個（慢的 iPad 回舊 ping 也算數）
            var toPing: [(NWConnection, Data)] = []
            for (id, entry) in s.entries {
                guard case .normal = entry.role, entry.pendingPing == nil,
                      realNow.timeIntervalSince(entry.lastServerPing ?? .distantPast) >= pingInterval else { continue }
                let payload = Random.bytes(8)
                s.entries[id]?.pendingPing = payload
                s.entries[id]?.lastServerPing = realNow
                toPing.append((entry.connection, payload))
            }
            // 配對路徑上還沒交出有效 proof 的連線：窗已不在 open，或 ready 後逾 proofDeadline＝斷（security review S2 M-1）。
            // proof 已被接受者不在此列：finish 的 .close 在鎖外執行，巡檢若搶先會蓋掉 pairResult
            let staleIDs = s.entries.filter {
                $0.value.isUnprovenPairing
                    && (!s.window.isOpen || realNow.timeIntervalSince($0.value.classifiedAt ?? .distantPast) > proofDeadline)
            }.map(\.key)
            return ((!effects.isEmpty, idleIDs.compactMap { self.detach(&s, $0)?.connection },
                     staleIDs.compactMap { self.detach(&s, $0)?.connection }, wasOpen != s.window.isOpen, toPing), effects)
        }
        if windowChanged || hadEffects { refreshGate() }
        toPing.forEach { Wire.sendControl(.ping, on: $0.0, payload: $0.1) }
        idle.forEach { $0.cancel() }
        stalePairing.forEach { reject(.pairingUnavailable, on: $0, close: true) }
    }
}

enum Random {
    static func bytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }
}
