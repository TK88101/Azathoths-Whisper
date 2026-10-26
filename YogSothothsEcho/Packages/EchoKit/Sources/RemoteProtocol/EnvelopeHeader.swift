import Foundation

/// 每個訊息信封的共同欄位（基本設計 §4.1；`seq`／`nonce` 規則見 `EnvelopeRules`，sprint-2-detail.md §4.2）
public struct EnvelopeHeader: Codable, Sendable, Equatable {
    public let v: Int
    public let id: UUID
    public let kind: MessageKind
    /// 只在 iPad→Mac 正常路徑必填；從 1 起嚴格遞增（設計 §4.2-7）
    public let seq: UInt64?
    /// 只在 iPad→Mac 正常路徑必填；等於 Mac 在 `session.hello` 發的 sessionNonce
    public let nonce: Data?

    public init(v: Int, id: UUID, kind: MessageKind, seq: UInt64? = nil, nonce: Data? = nil) {
        self.v = v
        self.id = id
        self.kind = kind
        self.seq = seq
        self.nonce = nonce
    }

    /// 先只看版本：舊版對端送來的新 kind 應該得到「請更新」而不是「請求無效」
    private struct VersionOnly: Decodable { let v: Int }

    /// 失敗直接回協定錯誤碼（invalidRequest／protocolMismatch），可原樣放進 `error` 訊息
    public static func decode(_ data: Data) -> Result<EnvelopeHeader, ErrorCode> {
        // 先擋超長，不做任何解析
        guard data.count <= TransportLimits.maxMessageBytes else { return .failure(.invalidRequest) }
        let decoder = JSONDecoder()
        guard let version = try? decoder.decode(VersionOnly.self, from: data) else { return .failure(.invalidRequest) }
        guard version.v == ProtocolVersion.current else { return .failure(.protocolMismatch) }
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: data) else { return .failure(.invalidRequest) }
        return .success(header)
    }
}
