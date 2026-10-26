import Testing
@testable import SpikeCore

// N4 診斷補充：TLS 1.3＋雙向自簽憑證＋指紋釘選（s0-offline-2026-10-15.md T4；判定式經 Codex 辯論收緊）
struct N4PinResultTests {
    private func positive(_ variant: N4PinVariant, client: Bool? = true, server: Bool? = true,
                          version: String? = "TLSv1.3", echo: Bool = true) -> N4PinCase {
        N4PinCase(variant: variant, clientReady: true, echo: echo, negotiatedVersion: version,
                  clientVerifyAccepted: client, serverVerifyAccepted: server,
                  serverReceivedData: echo, clientReceivedData: echo, error: nil)
    }

    private func clientRejected(client: Bool? = false) -> N4PinCase {
        N4PinCase(variant: .clientPinMismatch, clientReady: false, echo: false, negotiatedVersion: nil,
                  clientVerifyAccepted: client, serverVerifyAccepted: nil,
                  serverReceivedData: false, clientReceivedData: false, error: "-9808")
    }

    /// TLS 1.3：client 送出 Finished 即 ready，server 之後才驗 client 憑證並拒絕
    private func serverRejected(client: Bool? = true, server: Bool? = false, version: String? = "TLSv1.3",
                                serverData: Bool = false, clientData: Bool = false) -> N4PinCase {
        N4PinCase(variant: .serverPinMismatch, clientReady: true, echo: false, negotiatedVersion: version,
                  clientVerifyAccepted: client, serverVerifyAccepted: server,
                  serverReceivedData: serverData, clientReceivedData: clientData, error: "echo: no reply")
    }

    private var allExpected: [N4PinCase] {
        [positive(.positiveRaw), positive(.positiveWebSocket), clientRejected(), serverRejected()]
    }

    @Test func positiveNeedsBothVerifyBlocksToAcceptOverTLS13WithEcho() {
        #expect(positive(.positiveRaw).isAsExpected)
        #expect(!positive(.positiveRaw, server: nil).isAsExpected)
        #expect(!positive(.positiveRaw, client: false).isAsExpected)
        #expect(!positive(.positiveRaw, version: "TLSv1.2").isAsExpected)
        #expect(!positive(.positiveWebSocket, echo: false).isAsExpected)
    }

    @Test func clientMismatchMustBeRejectedByTheClientsVerifyBlock() {
        #expect(clientRejected().isAsExpected)
        // 握手失敗但 client 的 verify block 根本沒被呼叫（一般握手錯誤）
        #expect(!clientRejected(client: nil).isAsExpected)
        let connected = N4PinCase(variant: .clientPinMismatch, clientReady: true, echo: true, negotiatedVersion: "TLSv1.3",
                                  clientVerifyAccepted: false, serverVerifyAccepted: true,
                                  serverReceivedData: true, clientReceivedData: true, error: nil)
        #expect(!connected.isAsExpected)
    }

    @Test func serverMismatchCountsOnlyWhenTheServerAloneRejectedAndNoDataFlowed() {
        #expect(serverRejected().isAsExpected)
        // client 的 verify 沒被觀察到：無法確定是 server 拒絕
        #expect(!serverRejected(client: nil).isAsExpected)
        // 是 client 拒絕的、或 server 沒拒絕
        #expect(!serverRejected(client: false).isAsExpected)
        #expect(!serverRejected(server: true).isAsExpected)
        #expect(!serverRejected(server: nil).isAsExpected)
        #expect(!serverRejected(version: "TLSv1.2").isAsExpected)
        // 任一方向有應用資料通過：拒絕沒擋住資料
        #expect(!serverRejected(serverData: true).isAsExpected)
        #expect(!serverRejected(clientData: true).isAsExpected)
    }

    @Test func feasibleOnlyWhenAllFourVariantsBehaveAsExpected() {
        #expect(N4PinCase.isFeasible(allExpected))
        #expect(!N4PinCase.isFeasible(Array(allExpected.dropLast())))
        var broken = allExpected
        broken[1] = positive(.positiveWebSocket, echo: false)
        #expect(!N4PinCase.isFeasible(broken))
    }
}
