import Foundation
import Network
import Security

// S2-P1／P2：本機迴路 TLS 1.3 雙向憑證＋指紋釘選；記錄兩端 verify 次數、exporter。
public final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    public init(_ value: Value) { stored = value }
    public var value: Value { lock.withLock { stored } }
    public func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}

public struct TLSSettings: Sendable {
    public var disableTicketsAndResumption: Bool
    public init(disableTicketsAndResumption: Bool) { self.disableTicketsAndResumption = disableTicketsAndResumption }
}

public struct ConnectionOutcome: Sendable, CustomStringConvertible {
    public var clientReady = false
    public var echoed = false
    public var clientExporter: Data?
    public var serverExporter: Data?
    public var error: String?
    public var description: String {
        "ready=\(clientReady) echoed=\(echoed) exporterMatch=\(clientExporter != nil && clientExporter == serverExporter) err=\(error ?? "-")"
    }
}

public enum TLSProbe {
    public static let exporterLabel = "EXPORTER-yse-pair-v1"
    static let queue = DispatchQueue(label: "s2probe.tls")
    static let ping = Data("yse-ping".utf8)

    public static func exporter(_ connection: NWConnection) -> Data? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return nil }
        let label = exporterLabel
        let data: DispatchData? = label.withCString { pointer in
            sec_protocol_metadata_create_secret(metadata.securityProtocolMetadata, label.utf8.count, pointer, 32) as DispatchData?
        }
        return data.map { Data($0) }
    }

    /// verifyCount：此端 verify block 被呼叫的次數（resumption 時可能為 0）
    public static func parameters(identity: SecIdentity, expecting peer: Data, settings: TLSSettings,
                                  requirePeer: Bool, verifyCount: Box<Int>, verifyAccepted: Box<[Bool]>) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_local_identity(options, sec_identity_create(identity)!)
        if requirePeer { sec_protocol_options_set_peer_authentication_required(options, true) }
        if settings.disableTicketsAndResumption {
            sec_protocol_options_set_tls_tickets_enabled(options, false)
            sec_protocol_options_set_tls_resumption_enabled(options, false)
        }
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let chain = SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate]
            let ok = chain?.first.map { MiniCert.fingerprint(SecCertificateCopyData($0) as Data) == peer } ?? false
            verifyCount.mutate { $0 += 1 }
            verifyAccepted.mutate { $0.append(ok) }
            complete(ok)
        }, queue)
        let parameters = NWParameters(tls: tls)
        parameters.requiredInterfaceType = .loopback
        return parameters
    }

    public final class Server: @unchecked Sendable {
        public let listener: NWListener
        public let verifyCount = Box(0)
        public let verifyAccepted = Box<[Bool]>([])
        public let exporters = Box<[Data]>([])
        public let received = Box(0)

        public init(identity: SecIdentity, expecting peer: Data, settings: TLSSettings) throws {
            listener = try NWListener(using: TLSProbe.parameters(identity: identity, expecting: peer, settings: settings,
                                                                 requirePeer: true, verifyCount: verifyCount,
                                                                 verifyAccepted: verifyAccepted), on: .any)
            listener.newConnectionHandler = { [exporters, received] connection in
                connection.stateUpdateHandler = { state in
                    guard case .ready = state else { return }
                    if let e = TLSProbe.exporter(connection) { exporters.mutate { $0.append(e) } }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                        guard let data else { return }
                        received.mutate { $0 += 1 }
                        connection.send(content: data, completion: .contentProcessed { _ in })
                    }
                }
                connection.start(queue: TLSProbe.queue)
            }
        }

        public func start() async throws -> NWEndpoint.Port {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint.Port, Error>) in
                let once = Box(false)
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready: if !once.value { once.mutate { $0 = true }; continuation.resume(returning: listener.port!) }
                    case .failed(let e): if !once.value { once.mutate { $0 = true }; continuation.resume(throwing: e) }
                    default: break
                    }
                }
                listener.start(queue: TLSProbe.queue)
            }
        }

        public func stop() { listener.cancel() }
    }

    /// 連一次、送 ping、等回聲；回傳後連線即關
    public static func connect(port: NWEndpoint.Port, parameters: NWParameters, server: Server,
                               timeout: TimeInterval = 3) async -> ConnectionOutcome {
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        defer { connection.cancel() }
        var outcome = ConnectionOutcome()
        let ready: String? = await withCheckedContinuation { continuation in
            let once = Box(false)
            let finish: @Sendable (String?) -> Void = { r in
                if !once.value { once.mutate { $0 = true }; continuation.resume(returning: r) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(nil)
                case .failed(let e): finish("failed \(e)")
                case .waiting(let e): finish("waiting \(e)")
                case .cancelled: finish("cancelled")
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish("timeout") }
        }
        if let ready { outcome.error = ready; return outcome }
        outcome.clientReady = true
        outcome.clientExporter = exporter(connection)
        let echoed: Bool = await withCheckedContinuation { continuation in
            let once = Box(false)
            let finish: @Sendable (Bool) -> Void = { r in
                if !once.value { once.mutate { $0 = true }; continuation.resume(returning: r) }
            }
            connection.send(content: ping, completion: .contentProcessed { _ in })
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in finish(data == ping) }
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
        outcome.echoed = echoed
        // server 端 ready 與 exporter 記錄可能稍晚
        let deadline = Date(timeIntervalSinceNow: 1)
        while server.exporters.value.isEmpty, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        outcome.serverExporter = server.exporters.value.last
        return outcome
    }
}
