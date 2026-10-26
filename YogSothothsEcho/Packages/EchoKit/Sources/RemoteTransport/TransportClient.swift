import Foundation
import Network
import RemoteProtocol

public struct ClientConfiguration: Sendable {
    public var identity: DeviceIdentity
    public var trust: any TrustStore
    public var audit: any AuditSink
    public var interfaces: @Sendable () -> [NetworkInterface]
    public var allowLoopback: Bool
    public var timings: TransportTimings

    public init(identity: DeviceIdentity, trust: any TrustStore, audit: any AuditSink,
                interfaces: @escaping @Sendable () -> [NetworkInterface] = { NetworkInterface.current() },
                allowLoopback: Bool = true, timings: TransportTimings = .production) {
        self.identity = identity
        self.trust = trust
        self.audit = audit
        self.interfaces = interfaces
        self.allowLoopback = allowLoopback
        self.timings = timings
    }
}

public enum PairingFailure: Equatable, Sendable {
    case rejected, expired, cancelled
    /// 配對窗不存在、已被佔用或已作廢（需重新掃碼）
    case unavailable
    /// proof 被拒（同一 QR 不可再試）
    case invalid
    /// 連上的 Mac 不是 QR 上的那台
    case macPinMismatch
    case notOnLink, network, timeout
    /// 區網內沒看到開著中繼的 Mac（未開中繼、等待鑰匙圈授權、不同網路）
    case notFound
}

public enum PairingAttemptResult: Equatable, Sendable {
    case approved(PeerRecord)
    case failed(PairingFailure)
}

public enum ConnectFailure: Error, Equatable, Sendable {
    case notPaired, pinMismatch, rejectedByMac, notOnLink, network, timeout
    /// 區網內沒看到開著中繼的 Mac
    case notFound
    /// 看得到開著中繼的 Mac，但都不是配對的那台（釘選全部不符）：照一般退避，不走 notFound 的短間隔（S4 security LOW-1）
    case otherMacsOnly
}

/// iPad 端（sprint-2-detail.md §4.7）。每次 pair／connect 開一條新連線；重連排程由呼叫端依 `ReconnectBackoff` 決定
public final class TransportClient: Sendable {
    let configuration: ClientConfiguration
    private let verifyQueue = DispatchQueue(label: "yse.transport.client.verify")

    public init(configuration: ClientConfiguration) { self.configuration = configuration }

    /// 掃到 QR 後配對。iPad 只連 Bonjour 解析的端點；`onPending` 收到 Mac 端顯示的末 4 碼（本機自算比對）
    public func pair(endpoint: NWEndpoint, payload: QRPairingPayload, deviceName: String, timeout: TimeInterval? = nil,
                     onPending: (@Sendable (String) -> Void)? = nil) async -> PairingAttemptResult {
        let identity = configuration.identity
        let link = Link(configuration: configuration, verifyQueue: verifyQueue, endpoint: endpoint,
                        pins: [payload.macFingerprint])
        defer { link.close() }
        switch await link.open(timeout: configuration.timings.connectTimeout) {
        case .failure(.pinMismatch): return .failed(.macPinMismatch)
        case .failure(.notOnLink): return .failed(.notOnLink)
        case .failure(.timeout): return .failed(.timeout)
        case .failure(.rejectedByMac): return .failed(.unavailable)
        case .failure: return .failed(.network)
        case .success: break
        }
        guard let exporter = TLSConfiguration.exporter(link.connection) else { return .failed(.network) }
        let proof = PairingProof.compute(secret: payload.secret, sessionID: payload.sessionID, macFingerprint: payload.macFingerprint,
                                         ipadFingerprint: identity.fingerprint, exporter: exporter)
        let name = String(deviceName.utf8.prefix(TransportLimits.deviceNameMaxBytes)) ?? "iPad"
        Wire.send(Wire.encode(.pairProof, PairProof(sessionID: payload.sessionID, proof: proof, deviceName: name)), on: link.connection)
        let deadline = Date().addingTimeInterval(timeout ?? configuration.timings.pairingResponseTimeout)
        // proof 送出後的等待不隨呼叫端取消：Mac 可能已寫入信任紀錄，中途放棄會讓兩端不一致（security 補查）。
        // 非結構化 Task 不繼承取消；期限仍由 deadline 封頂
        let configuration = configuration
        return await Task {
            await Self.pairingOutcome(link: link, payload: payload, configuration: configuration,
                                      deadline: deadline, onPending: onPending)
        }.value
    }

    private static func pairingOutcome(link: Link, payload: QRPairingPayload, configuration: ClientConfiguration, deadline: Date,
                                       onPending: (@Sendable (String) -> Void)?) async -> PairingAttemptResult {
        let identity = configuration.identity
        while let message = await link.nextMessage(until: deadline) {
            guard case .success(let header) = EnvelopeHeader.decode(message),
                  EnvelopeRules.check(header, direction: .fromMac, path: .pairing) == nil else { return .failed(.network) }
            switch header.kind {
            case .pairPending:
                guard let pending = Wire.body(message, as: PairPending.self), pending.suffix == identity.fingerprint.suffix else {
                    return .failed(.invalid)
                }
                onPending?(pending.suffix)
            case .pairResult:
                guard let result = Wire.body(message, as: PairResult.self) else { return .failed(.network) }
                switch result.outcome {
                case .approved:
                    let record = PeerRecord(peerID: UUID(), fingerprint: payload.macFingerprint,
                                            localFingerprint: identity.fingerprint,
                                            name: DeviceName.sanitize(payload.instanceName, fallback: "Mac"), pairedAt: Date())
                    do { try configuration.trust.add(record) } catch { return .failed(.network) }
                    return .approved(record)
                case .rejected: return .failed(.rejected)
                case .expired: return .failed(.expired)
                case .cancelled: return .failed(.cancelled)
                }
            case .error:
                switch Wire.body(message, as: ErrorBody.self)?.code {
                case .pairingInvalid?: return .failed(.invalid)
                default: return .failed(.unavailable)
                }
            default:
                return .failed(.network)
            }
        }
        return link.isClosed ? .failed(.unavailable) : .failed(.timeout)
    }

    /// 以已配對的 Mac 指紋（只取 validRecords）連線，等到 session.hello
    public func connect(endpoint: NWEndpoint) async -> Result<ClientSession, ConnectFailure> {
        let pins = Set(configuration.trust.validRecords(for: configuration.identity.fingerprint).map(\.fingerprint))
        guard !pins.isEmpty else { return .failure(.notPaired) }
        let link = Link(configuration: configuration, verifyQueue: verifyQueue, endpoint: endpoint, pins: pins)
        if case .failure(let failure) = await link.open(timeout: configuration.timings.connectTimeout) {
            link.close()
            return .failure(failure)
        }
        let deadline = Date().addingTimeInterval(configuration.timings.connectTimeout)
        guard let message = await link.nextMessage(until: deadline),
              case .success(let header) = EnvelopeHeader.decode(message), header.kind == .sessionHello,
              let hello = Wire.body(message, as: SessionHello.self), hello.isValid else {
            let failure: ConnectFailure = link.isClosed ? .rejectedByMac : .timeout
            link.close()
            return .failure(failure)
        }
        return .success(ClientSession(link: link, nonce: hello.sessionNonce, timings: configuration.timings))
    }
}

/// 一條 TLS＋WebSocket 連線與其收件匣
final class Link: Sendable {
    struct Inbox: Sendable {
        var messages: [Data] = []
        var closed = false
        var lastPong = Date()
        var verifyResult: Bool?
        /// session 建立後改由這兩個處理者接收（S3：不再輪詢收件匣）
        var onMessage: (@Sendable (Data) -> Void)?
        var onClose: (@Sendable () -> Void)?
    }

    let connection: NWConnection
    let configuration: ClientConfiguration
    private let queue = DispatchQueue(label: "yse.transport.link")
    private let inbox = Locked(Inbox())

    init(configuration: ClientConfiguration, verifyQueue: DispatchQueue, endpoint: NWEndpoint, pins: Set<Fingerprint>) {
        self.configuration = configuration
        let inbox = self.inbox
        let parameters = TLSConfiguration.parameters(identity: configuration.identity, role: .client, verifyQueue: verifyQueue) { fp in
            let ok = fp.map { pins.contains($0) } ?? false
            inbox.withLock { $0.verifyResult = ok }
            return ok
        }
        connection = NWConnection(to: endpoint, using: parameters)
    }

    var isClosed: Bool { inbox.withLock { $0.closed } }
    var lastPong: Date { inbox.withLock { $0.lastPong } }

    func open(timeout: TimeInterval) async -> Result<Void, ConnectFailure> {
        let ready: Bool = await withCheckedContinuation { continuation in
            let resumed = Locked(false)
            let finish: @Sendable (Bool) -> Void = { value in
                if resumed.withLock({ done in defer { done = true }; return !done }) { continuation.resume(returning: value) }
            }
            connection.stateUpdateHandler = { [weak self] update in
                switch update {
                case .ready: finish(true)
                case .failed, .cancelled:
                    self?.markClosed()
                    finish(false)
                case .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
        guard ready else {
            switch inbox.withLock({ $0.verifyResult }) {
            case false?: return .failure(.pinMismatch)
            case true?: return .failure(.rejectedByMac)
            case nil: return .failure(isClosed ? .network : .timeout)
            }
        }
        // ready 後、送任何應用訊息前：對端必須在本機子網內（§4.7）
        guard case .hostPort(let host, _)? = connection.currentPath?.remoteEndpoint, let address = IPAddressBytes(host: host),
              LocalNetworkPolicy.isOnLink(address, interfaces: configuration.interfaces(), allowLoopback: configuration.allowLoopback) else {
            configuration.audit.record(.nonLocalPeer)
            return .failure(.notOnLink)
        }
        receiveLoop()
        return .success(())
    }

    private func receiveLoop() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error != nil {
                markClosed()
                return
            }
            switch Wire.opcode(context) {
            case .pong?: inbox.withLock { $0.lastPong = Date() }
            // Mac 以 ping 確認 iPad 有在讀（S3 security review HIGH-1）；Network.framework 預設不自動回
            case .ping?: Wire.sendControl(.pong, on: connection, payload: data ?? Data())   // 帶回相同內容（RFC 6455）
            case .close?:
                markClosed()
                return
            default:
                if let data, !data.isEmpty {
                    let route = inbox.withLock { box -> (@Sendable (Data) -> Void)? in
                        if let handler = box.onMessage { return handler }
                        box.messages.append(data)
                        return nil
                    }
                    route?(data)
                }
            }
            receiveLoop()
        }
    }

    func nextMessage(until deadline: Date) async -> Data? {
        while Date() < deadline {
            let (message, closed) = inbox.withLock { box -> (Data?, Bool) in
                box.messages.isEmpty ? (nil, box.closed) : (box.messages.removeFirst(), false)
            }
            if let message { return message }
            if closed { return nil }
            // 被取消即返回（try? 會吞掉 CancellationError，使迴圈空轉到 deadline）
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return nil }
        }
        return nil
    }

    func close() {
        markClosed()
        connection.cancel()
    }

    /// 只在第一次轉為關閉時通知 onClose（在鎖外呼叫）
    private func markClosed() {
        let notify = inbox.withLock { box -> (@Sendable () -> Void)? in
            guard !box.closed else { return nil }
            box.closed = true
            return box.onClose
        }
        notify?()
    }

    /// 改由處理者接收；收件匣裡尚未取走的訊息依序先交出。已關閉則立即呼叫 onClose
    func route(message: @escaping @Sendable (Data) -> Void, closed: @escaping @Sendable () -> Void) {
        let (backlog, alreadyClosed) = inbox.withLock { box -> ([Data], Bool) in
            box.onMessage = message
            box.onClose = closed
            defer { box.messages = [] }
            return (box.messages, box.closed)
        }
        backlog.forEach(message)
        if alreadyClosed { closed() }
    }
}

/// 已建立的 session：心跳（ping 間隔、pong 期限）、請求／回應關聯與 Mac 推送的事件（S3）
public final class ClientSession: Sendable {
    public static let defaultRequestTimeout: TimeInterval = 10

    /// 未指定逾時時依 kind 取（受管播放指令要等 Mac 的准入預算，sprint-4-detail.md §4.8）
    static func timeout(for kind: MessageKind, explicit: TimeInterval?) -> TimeInterval {
        explicit ?? PlaybackLimits.clientTimeout(kind)
    }

    let link: Link
    let nonce: Data
    private let timings: TransportTimings
    private let seq = Locked<UInt64>(0)
    /// 取序號＋排入送出的串行化（見 sendInOrder）
    private let sendOrder = NSLock()
    private let heartbeatQueue = DispatchQueue(label: "yse.transport.heartbeat")
    private let timeoutQueue = DispatchQueue(label: "yse.transport.request-timeout")
    private let waiters = Locked<[UUID: CheckedContinuation<Result<Data, EchoRequestError>, Never>]>([:])
    private let eventContinuation: AsyncStream<InboundEvent>.Continuation
    /// Mac 推送的 `event.*`；連線結束時串流結束
    public let events: AsyncStream<InboundEvent>

    init(link: Link, nonce: Data, timings: TransportTimings) {
        self.link = link
        self.nonce = nonce
        self.timings = timings
        (events, eventContinuation) = AsyncStream.makeStream()
        link.route(message: { [weak self] in self?.received($0) }, closed: { [weak self] in self?.closedByLink() })
        scheduleHeartbeat()
    }

    public var isOpen: Bool { !link.isClosed }

    public func close() { link.close() }

    /// 連線結束（Mac 斷線、心跳逾時、被解除或本機關閉）或呼叫端被取消時返回
    public func waitUntilClosed() async {
        while isOpen {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }

    /// 送一個業務請求並等同一 id 的回覆。Mac 回 `error`＝`.remote(code)`；逾時、斷線、取消各自對應
    /// `id`：預設每次新建；量測時由呼叫端指定，讓 iPad 與 Mac 兩邊的紀錄逐筆對應（S4 #4-1 D2）
    public func request<Request: Encodable, Response: Decodable>(
        _ kind: MessageKind, _ body: Request, as type: Response.Type, timeout: TimeInterval? = nil, id: UUID = UUID()
    ) async throws(EchoRequestError) -> Response {
        let timeout = Self.timeout(for: kind, explicit: timeout)
        let result: Result<Data, EchoRequestError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // 同一個 id 還在等＝呼叫端誤用：立刻失敗，不擠掉先前的等待者（S4 後半 security LOW-3）
                let refusal = waiters.withLock { pending -> EchoRequestError? in
                    if Task.isCancelled { return .cancelled }
                    if link.isClosed { return .disconnected }
                    if pending[id] != nil { return .invalidResponse }
                    pending[id] = continuation
                    return nil
                }
                if let refusal { return continuation.resume(returning: .failure(refusal)) }
                sendInOrder(kind, body, id: id)
                timeoutQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(id, .failure(.timeout)) }
            }
        } onCancel: {
            finish(id, .failure(.cancelled))
        }
        let data = try result.get()
        guard case .success(let header) = EnvelopeHeader.decode(data) else { throw .invalidResponse }
        if header.kind == .error {
            guard let error = Wire.body(data, as: ErrorBody.self) else { throw .invalidResponse }
            throw .remote(error.code)
        }
        guard header.kind == kind.replyKind, let response = Wire.body(data, as: type) else { throw .invalidResponse }
        return response
    }

    /// 取序號與排入送出在同一把鎖內（security 複核 HIGH）：NWConnection 依呼叫順序排隊，送出順序因此等於序號順序；
    /// 否則並行請求的大序號可能先上線，Mac 的 ReplayGuard（嚴格遞增）會把晚到的小序號當重放拒絕
    private func sendInOrder<Request: Encodable>(_ kind: MessageKind, _ body: Request, id: UUID) {
        sendOrder.withLock {
            Wire.send(Wire.encode(kind, body, id: id, seq: nextSeq(), nonce: nonce), on: link.connection)
        }
    }

    private func finish(_ id: UUID, _ result: Result<Data, EchoRequestError>) {
        waiters.withLock { $0.removeValue(forKey: id) }?.resume(returning: result)
    }

    private func received(_ data: Data) {
        guard case .success(let header) = EnvelopeHeader.decode(data) else { return }
        if header.kind == .eventCatalogChanged || header.kind == .eventPlayback {
            eventContinuation.yield(InboundEvent(kind: header.kind, message: data))
        } else {
            finish(header.id, .success(data))
        }
    }

    private func closedByLink() {
        let pending = waiters.withLock { all -> [CheckedContinuation<Result<Data, EchoRequestError>, Never>] in
            defer { all = [:] }
            return Array(all.values)
        }
        pending.forEach { $0.resume(returning: .failure(.disconnected)) }
        eventContinuation.finish()
    }

    func nextSeq() -> UInt64 { seq.withLock { $0 += 1; return $0 } }

    private func scheduleHeartbeat() {
        heartbeatQueue.asyncAfter(deadline: .now() + timings.heartbeatInterval) { [weak self] in
            guard let self, self.isOpen else { return }
            if Date().timeIntervalSince(self.link.lastPong) > self.timings.heartbeatDeadline {
                self.link.close()
                return
            }
            Wire.sendControl(.ping, on: self.link.connection)
            self.scheduleHeartbeat()
        }
    }
}
