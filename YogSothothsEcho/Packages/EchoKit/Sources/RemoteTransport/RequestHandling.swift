import Foundation
import RemoteProtocol

// 正常路徑的業務請求分派（sprint-3-detail.md §4.5）：TransportServer 通過防重放與配額後交給注入的處理者，
// 回覆以同一 request id 送出。處理者在 Azathoth 的 RelayRequestRouter，傳輸層不認識任何業務。

public struct InboundRequest: Sendable {
    public let peerID: UUID
    public let id: UUID
    public let kind: MessageKind
    /// 這個請求所在的連線（每條連線一個、永不重用；S4 連線撤離以它查存活，見 `TransportServer.isConnectionAlive`）
    public let connectionID: UUID
    let message: Data

    /// 傳輸層建立；公開只為讓上層（RelayRequestRouter）的單元測試能直接構造請求
    public init(peerID: UUID, id: UUID, kind: MessageKind, message: Data, connectionID: UUID = UUID()) {
        self.peerID = peerID
        self.id = id
        self.kind = kind
        self.connectionID = connectionID
        self.message = message
    }

    public func body<Body: Decodable>(as type: Body.Type) -> Body? { Wire.body(message, as: type) }

    /// 以 `kind.replyKind`（`play.track`→`play.result`，其餘同 kind）、同一 id 編成完整回覆訊息
    public func reply<Body: Encodable>(_ body: Body) -> OutboundReply {
        .message(Envelope.encode(kind.replyKind, body, id: id))
    }
}

public enum OutboundReply: Sendable {
    /// 已編好的完整訊息（`InboundRequest.reply`）
    case message(Data)
    case error(ErrorCode)
}

public protocol RequestHandling: Sendable {
    func handle(_ request: InboundRequest) async -> OutboundReply
}

/// Mac 推給 iPad 的事件（`event.*`）
public struct InboundEvent: Sendable {
    public let kind: MessageKind
    let message: Data

    /// 傳輸層建立；公開只為讓上層（iPad EchoClient）的單元測試能直接構造事件
    public init(kind: MessageKind, message: Data) {
        self.kind = kind
        self.message = message
    }

    public func body<Body: Decodable>(as type: Body.Type) -> Body? { Wire.body(message, as: type) }
}

public enum EchoRequestError: Error, Equatable, Sendable {
    case remote(ErrorCode)
    case timeout
    case disconnected
    case invalidResponse
    case cancelled
}
