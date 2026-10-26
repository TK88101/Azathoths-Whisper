import Foundation
import Network
import Security
@testable import RemoteTransport

/// 攻擊者／對端模擬（只在測試）：可用任意身分、送任意 frame、ping、或只開 TCP 不握手
final class TestPeer: Sendable {
    enum Event: Equatable, Sendable { case message(Data), pong, closed }

    let connection: NWConnection
    private let queue = DispatchQueue(label: "yse.test.peer")
    private let inbox = Locked<[Event]>([])
    private let readyState = Locked<Bool?>(nil)

    private init(connection: NWConnection) { self.connection = connection }

    /// TLS＋WebSocket；`serverPin` 為 nil 時接受任何伺服端憑證（攻擊者不在乎）
    static func tls(port: NWEndpoint.Port, identity: DeviceIdentity, serverPin: Fingerprint?, host: String = "127.0.0.1",
                    timeout: TimeInterval = 3) async -> TestPeer? {
        let parameters = TLSConfiguration.parameters(identity: identity, role: .client,
                                                     verifyQueue: DispatchQueue(label: "yse.test.verify")) { fp in
            serverPin.map { $0 == fp } ?? (fp != nil)
        }
        let url = URL(string: "wss://\(host.contains(":") ? "[\(host)]" : host):\(port.rawValue)/")!
        let peer = TestPeer(connection: NWConnection(to: .url(url), using: parameters))
        return await peer.start(timeout: timeout) ? peer : nil
    }

    /// 只開 TCP、不送任何 TLS 位元組（半開握手）
    static func rawTCP(port: NWEndpoint.Port) async -> TestPeer? {
        let peer = TestPeer(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp))
        return await peer.start(timeout: 2) ? peer : nil
    }

    private func start(timeout: TimeInterval) async -> Bool {
        let ok: Bool = await withCheckedContinuation { continuation in
            let once = Locked(false)
            let finish: @Sendable (Bool) -> Void = { value in
                if once.withLock({ let first = !$0; $0 = true; return first }) { continuation.resume(returning: value) }
            }
            connection.stateUpdateHandler = { [inbox] state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled:
                    finish(false)
                    inbox.withLock { $0.append(.closed) }
                case .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
        if ok { receiveLoop() }
        return ok
    }

    private func receiveLoop() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            let opcode = (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode
            if opcode == .pong {
                inbox.withLock { $0.append(.pong) }
            } else if opcode == .ping {
                // 與正式 client 一樣回 Mac 的 ping（S3：Mac 以此確認對端有在讀）
                self.connection.send(content: data ?? Data(), contentContext: .init(identifier: "pong", metadata: [NWProtocolWebSocket.Metadata(opcode: .pong)]),
                                     isComplete: true, completion: .idempotent)
            } else if let data, !data.isEmpty {
                inbox.withLock { $0.append(.message(data)) }
            }
            if error != nil || context?.isFinal == true && data == nil {
                inbox.withLock { $0.append(.closed) }
                return
            }
            receiveLoop()
        }
    }

    var exporter: Data? { TLSConfiguration.exporter(connection) }

    func send(_ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        connection.send(content: data, contentContext: .init(identifier: "msg", metadata: [metadata]), isComplete: true,
                        completion: .idempotent)
    }

    func sendPing() {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        connection.send(content: Data(), contentContext: .init(identifier: "ping", metadata: [metadata]), isComplete: true,
                        completion: .idempotent)
    }

    /// 等下一個事件（有期限）
    func next(timeout: TimeInterval = 2) async -> Event? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = inbox.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { return event }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    /// 等到下一則應用訊息並解出 kind
    func nextKind(timeout: TimeInterval = 2) async -> (kind: String, data: Data)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let event = await next(timeout: deadline.timeIntervalSinceNow) else { return nil }
            if case .message(let data) = event,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let kind = object["kind"] as? String {
                return (kind, data)
            }
            if event == .closed { return nil }
        }
        return nil
    }

    func waitClosed(timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .failed = connection.state { return true }
            if case .cancelled = connection.state { return true }
            if let event = await next(timeout: 0.05), event == .closed { return true }
        }
        return false
    }

    func cancel() { connection.cancel() }
}

/// 可前進的測試時鐘
final class TestClock: Sendable {
    private let value = Locked(Date(timeIntervalSince1970: 1_000_000))
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

func envelope(kind: String, body: [String: Any] = [:], seq: UInt64? = nil, nonce: Data? = nil) -> Data {
    var object: [String: Any] = ["v": 1, "id": UUID().uuidString, "kind": kind, "body": body]
    if let seq { object["seq"] = seq }
    if let nonce { object["nonce"] = nonce.base64EncodedString() }
    return json(object)
}

func errorCode(_ data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let body = object["body"] as? [String: Any] else { return nil }
    return body["code"] as? String
}
