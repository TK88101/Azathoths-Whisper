// MARK: N4 診斷補充：TLS 1.3＋雙向自簽憑證＋指紋釘選（s0-offline-2026-10-15.md T4）
// 只是診斷列，不改 N4 判定列（N4Result）。

public enum N4PinVariant: String, Codable, Sendable, CaseIterable {
    case positiveRaw = "pin-positive-raw"
    case positiveWebSocket = "pin-positive-websocket"
    /// client 期待的伺服端指紋是錯的 → 應由 client 的 verify block 拒絕
    case clientPinMismatch = "pin-client-mismatch"
    /// server 期待的 client 指紋是錯的 → 應由 server 的 verify block 拒絕
    case serverPinMismatch = "pin-server-mismatch"
}

public struct N4PinCase: Codable, Sendable, Equatable {
    public let variant: N4PinVariant
    /// client 端連線進入 ready。TLS 1.3 下 client 送出 Finished 即 ready，**不代表 server 已接受 client 憑證**
    public let clientReady: Bool
    public let echo: Bool
    public let negotiatedVersion: String?
    /// nil＝該端 verify block 沒被呼叫；否則是它的回傳值（是否接受對端葉憑證指紋）
    public let clientVerifyAccepted: Bool?
    public let serverVerifyAccepted: Bool?
    /// 伺服端／client 端是否收到任何應用資料（拒絕時兩者都必須為 false，才算拒絕擋住了資料）
    public let serverReceivedData: Bool
    public let clientReceivedData: Bool
    public let error: String?

    public init(variant: N4PinVariant, clientReady: Bool, echo: Bool, negotiatedVersion: String?,
                clientVerifyAccepted: Bool?, serverVerifyAccepted: Bool?,
                serverReceivedData: Bool, clientReceivedData: Bool, error: String?) {
        self.variant = variant
        self.clientReady = clientReady
        self.echo = echo
        self.negotiatedVersion = negotiatedVersion
        self.clientVerifyAccepted = clientVerifyAccepted
        self.serverVerifyAccepted = serverVerifyAccepted
        self.serverReceivedData = serverReceivedData
        self.clientReceivedData = clientReceivedData
        self.error = error
    }

    /// 正例：TLS 1.3、互傳成功，兩端 verify block 都接受。
    /// client 端拒絕：client 不會 ready，且是 client 的 verify block 回 false（別處的握手錯誤不算）。
    /// server 端拒絕：client 已 ready（TLS 1.3 時序）、client 的 verify 接受、server 的 verify 拒絕，
    /// 且兩個方向都沒有任何應用資料通過（2026-10-15 實測與 Codex 辯論）。
    /// 推論（S2 用）：TLS 1.3 下 client 的 ready 不代表已被 server 接受，信任要等應用層確認。
    public var isAsExpected: Bool {
        switch variant {
        case .positiveRaw, .positiveWebSocket:
            clientReady && echo && negotiatedVersion == "TLSv1.3"
                && clientVerifyAccepted == true && serverVerifyAccepted == true
        case .clientPinMismatch:
            !clientReady && clientVerifyAccepted == false && !serverReceivedData && !clientReceivedData
        case .serverPinMismatch:
            clientReady && negotiatedVersion == "TLSv1.3"
                && clientVerifyAccepted == true && serverVerifyAccepted == false
                && !serverReceivedData && !clientReceivedData && !echo
        }
    }

    /// 四個變體都在且都符合預期，才記「此組合在本機迴路可行」
    public static func isFeasible(_ cases: [N4PinCase]) -> Bool {
        N4PinVariant.allCases.allSatisfy { variant in
            cases.contains { $0.variant == variant } && cases.filter { $0.variant == variant }.allSatisfy(\.isAsExpected)
        }
    }
}
