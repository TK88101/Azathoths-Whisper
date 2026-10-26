import Foundation
import Network
import ProbeShared

// N4／N4 釘選診斷／N5 共用的 Network.framework 小工具：狀態等待、端點、echo 收發。
enum NetProbe {
    static let timeout: TimeInterval = 5

    /// 先設好 newConnectionHandler 再呼叫。nil＝ready；否則是錯誤描述
    static func waitReady(_ listener: NWListener, queue: DispatchQueue,
                          timeout: TimeInterval = timeout) async -> String? {
        await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(nil)
                case .failed(let error): once.resume("listener failed: \(error)")
                default: break
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { once.resume("listener timeout") }
        }
    }

    /// nil＝ready；否則是「<label> failed／waiting／timeout」。
    /// `.waiting` 直接當失敗：只適用本機迴路（迴路上 waiting＝不會好轉）；真實網路路徑不要用這個

    static func waitReady(_ connection: NWConnection, label: String, queue: DispatchQueue,
                          timeout: TimeInterval = timeout) async -> String? {
        await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(nil)
                case .failed(let error): once.resume("\(label) failed: \(error)")
                case .waiting(let error): once.resume("\(label) waiting: \(error)")
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { once.resume("\(label) timeout") }
        }
    }

    /// 本機迴路端點。WebSocket 的 HTTP 升級需要 URL（Host／path）：
    /// 2026-10-15 實測 host:port 端點疊 WebSocket 時連線被中止（POSIX 53），改 `wss://` URL 即成功
    static func loopbackEndpoint(port: NWEndpoint.Port, webSocket: Bool) -> NWEndpoint {
        guard webSocket, let url = URL(string: "wss://127.0.0.1:\(port.rawValue)/") else {
            return .hostPort(host: "127.0.0.1", port: port)
        }
        return .url(url)
    }

    /// 伺服端：每個連線收一則就原樣送回；收到資料時呼叫 onData（記錄伺服端確實收到應用資料）
    static func installEcho(on listener: NWListener, webSocket: Bool, queue: DispatchQueue,
                            onData: @escaping @Sendable () -> Void = {}) {
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receiveOnce(connection, webSocket: webSocket) { data in
                guard let data else { return }
                onData()
                sendOnce(connection, data, webSocket: webSocket) { _ in }
            }
        }
    }

    /// 送 ping、收一則回覆；回傳收到的資料（nil＝什麼都沒收到）。是否為正確回聲由呼叫端比對 `pingPayload`
    static let pingPayload = Data("ping".utf8)

    static func echo(over connection: NWConnection, webSocket: Bool, queue: DispatchQueue,
                     notes: inout [String]) async -> Data? {
        let payload = pingPayload
        let reply: Data? = await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            sendOnce(connection, payload, webSocket: webSocket) { error in if error != nil { once.resume(nil) } }
            receiveOnce(connection, webSocket: webSocket) { data in once.resume(data) }
            queue.asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
        }
        if reply == nil { notes.append("echo: no reply") }
        return reply
    }

    private static func tlsMetadata(_ connection: NWConnection) -> sec_protocol_metadata_t? {
        (connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata)?.securityProtocolMetadata
    }

    static func negotiatedSuite(_ connection: NWConnection) -> UInt16? {
        tlsMetadata(connection).map { sec_protocol_metadata_get_negotiated_tls_ciphersuite($0).rawValue }
    }

    static func negotiatedVersion(_ connection: NWConnection) -> String? {
        guard let metadata = tlsMetadata(connection) else { return nil }
        switch sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata) {
        case .TLSv13: return "TLSv1.3"
        case .TLSv12: return "TLSv1.2"
        default: return "other"
        }
    }

    /// 在 TLS 參數上疊 WebSocket（在 TLS 之上）
    static func addWebSocket(to parameters: NWParameters) {
        let stack = parameters.defaultProtocolStack
        stack.applicationProtocols = [NWProtocolWebSocket.Options()] + stack.applicationProtocols
    }

    private static func sendOnce(_ connection: NWConnection, _ data: Data, webSocket: Bool,
                                 completion: @escaping @Sendable (NWError?) -> Void) {
        let context = webSocket
            ? NWConnection.ContentContext(identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
            : .defaultMessage
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed(completion))
    }

    /// WebSocket 收一則訊息；純 TCP 串流收最多 64 bytes（不能用 receiveMessage：要等 EOF 才返回）
    private static func receiveOnce(_ connection: NWConnection, webSocket: Bool,
                                    handler: @escaping @Sendable (Data?) -> Void) {
        if webSocket {
            connection.receiveMessage { data, _, _, _ in handler(data) }
        } else {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in handler(data) }
        }
    }
}
