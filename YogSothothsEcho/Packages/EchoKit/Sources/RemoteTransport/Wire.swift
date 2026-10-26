import Foundation
import Network
import RemoteProtocol

/// 信封的編解碼與 WebSocket 收送（設計 §4.1）
enum Wire {
    struct BodyOnly<Body: Decodable>: Decodable {
        let body: Body
    }

    static func encode<Body: Encodable>(_ kind: MessageKind, _ body: Body, id: UUID = UUID(), seq: UInt64? = nil,
                                        nonce: Data? = nil) -> Data {
        Envelope.encode(kind, body, id: id, seq: seq, nonce: nonce)
    }

    static func body<Body: Decodable>(_ data: Data, as type: Body.Type) -> Body? {
        try? JSONDecoder().decode(BodyOnly<Body>.self, from: data).body
    }

    static func error(_ code: ErrorCode, replyingTo id: UUID = UUID()) -> Data {
        encode(.error, ErrorBody(code: code, retryable: code.isRetryable), id: id)
    }

    /// `completion` 預設不追蹤；待送位元組記帳時傳 `.contentProcessed`（CR-012）
    static func send(_ data: Data, on connection: NWConnection, completion: NWConnection.SendCompletion = .idempotent) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        connection.send(content: data, contentContext: .init(identifier: "yse", metadata: [metadata]), isComplete: true,
                        completion: completion)
    }

    static func sendControl(_ opcode: NWProtocolWebSocket.Opcode, on connection: NWConnection, payload: Data = Data()) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        connection.send(content: payload, contentContext: .init(identifier: "yse-control", metadata: [metadata]),
                        isComplete: true, completion: .idempotent)
    }

    /// 先前排入的訊息送完後才關閉（送 result／error 之後關線用）
    static func closeAfterPendingSends(_ connection: NWConnection) {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    static func opcode(_ context: NWConnection.ContentContext?) -> NWProtocolWebSocket.Opcode? {
        (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode
    }
}

