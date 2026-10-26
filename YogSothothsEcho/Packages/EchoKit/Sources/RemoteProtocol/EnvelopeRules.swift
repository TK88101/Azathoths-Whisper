// 路徑與方向的 kind 白名單、seq／nonce 必填與禁填（sprint-2-detail.md §4.2）

public enum MessageDirection: Sendable {
    case fromIPad, fromMac
}

/// 配對路徑＝未知指紋、配對窗 open 時的連線；正常路徑＝已信任對端（§4.7 連線分類）
public enum ConnectionPath: Sendable {
    case pairing, normal
}

public enum EnvelopeRules {
    /// 只能走配對路徑的 kind（伺服端判 pathMismatch 也用這一份）
    public static let pairKinds: Set<MessageKind> = [.pairProof, .pairPending, .pairResult]
    /// 讀取類（CR-012）：扣讀取配額；其餘合規請求扣控制類配額
    public static let readKinds: Set<MessageKind> = [.catalogPage, .catalogSearch, .albumTracks, .artworkGet]
    /// 封面：另受每連線／全域在途上限
    public static let artworkKinds: Set<MessageKind> = [.artworkGet]
    /// iPad 在正常路徑上不得送的（Mac 專屬的推送與結果）
    private static let macOnlyKinds: Set<MessageKind> = [.sessionHello, .playResult, .eventPlayback, .eventCatalogChanged]

    static func allowed(_ kind: MessageKind, direction: MessageDirection, path: ConnectionPath) -> Bool {
        switch (direction, path) {
        case (.fromIPad, .pairing): kind == .pairProof
        case (.fromMac, .pairing): [.pairPending, .pairResult, .error].contains(kind)
        case (.fromIPad, .normal): !pairKinds.contains(kind) && !macOnlyKinds.contains(kind)
        case (.fromMac, .normal): !pairKinds.contains(kind)
        }
    }

    /// 合規回 nil，否則回應回給對端的錯誤碼。nonce 缺＝`replayed`、seq 缺＝`invalidRequest`（§4.8 ReplayGuard 同一語意）
    public static func check(_ header: EnvelopeHeader, direction: MessageDirection, path: ConnectionPath) -> ErrorCode? {
        guard allowed(header.kind, direction: direction, path: path) else { return .invalidRequest }
        guard direction == .fromIPad, path == .normal else {
            return header.seq == nil && header.nonce == nil ? nil : .invalidRequest
        }
        guard let nonce = header.nonce else { return .replayed }
        guard nonce.count == TransportLimits.nonceBytes, header.seq != nil else { return .invalidRequest }
        return nil
    }
}
