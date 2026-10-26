#if os(macOS)
import Foundation
import Network
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S3 security review（附錄 E）：已配對但惡意的 iPad。探針改寫自安全評審的 ZProbe*（scratchpad），縮到幾秒內跑完

/// 不讀取的對端：連上後永不呼叫 receiveMessage（除非測試要它開始讀）
final class SilentPeer: @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "test.silent-peer")

    init?(port: NWEndpoint.Port, identity: DeviceIdentity, pin: Fingerprint) async {
        let parameters = TLSConfiguration.parameters(identity: identity, role: .client, verifyQueue: DispatchQueue(label: "test.silent-verify")) {
            $0 == pin
        }
        connection = NWConnection(to: .url(URL(string: "wss://127.0.0.1:\(port.rawValue)/")!), using: parameters)
        let ready: Bool = await withCheckedContinuation { continuation in
            let once = Locked(false)
            connection.stateUpdateHandler = { state in
                let finish = { (value: Bool) in
                    if once.withLock({ done in defer { done = true }; return !done }) { continuation.resume(returning: value) }
                }
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled, .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
        }
        guard ready else { return nil }
    }

    func send(_ data: Data) {
        connection.send(content: data, contentContext: .init(identifier: "m", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)]),
                        isComplete: true, completion: .idempotent)
    }

    func ping() {
        connection.send(content: Data(), contentContext: .init(identifier: "p", metadata: [NWProtocolWebSocket.Metadata(opcode: .ping)]),
                        isComplete: true, completion: .idempotent)
    }
}

private func pairedHarness(limits: ServerLimits = .relaxedForTests, handler: (any RequestHandling)?) async throws -> Harness {
    let h = try await Harness(limits: limits, handler: handler)
    guard case .approved = await h.pair() else { throw CancellationError() }
    return h
}

private func waitFor(_ timeout: TimeInterval = 3, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@Suite(.serialized) struct CatalogSecurityTests {
    /// HIGH-1：不讀取的 iPad 狂送垃圾 frame（1 B 換 130 B 回覆的放大）——每秒拒絕次數遠超正常就斷線
    @Test func silentPeerFloodIsCutOff() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let peer = try #require(await SilentPeer(port: h.port, identity: h.ipadIdentity, pin: h.macIdentity.fingerprint))
        // 只送 1 個 ping（每秒 2 個以上會被判 ping 洪水而斷線）；測試心跳期限 1.5 s，所以 1 s 內就檢查
        let sent = 20_000
        peer.ping()
        for _ in 0..<sent { peer.send(Data("x".utf8)) }
        try? await Task.sleep(for: .seconds(1))
        let handled = h.server.normalFramesHandled
        #expect(handled > 0, "Mac 應該有處理部分 frame")
        #expect(handled < sent / 4, "handled \(handled) of \(sent)")
        #expect(h.server.connectedPeers.isEmpty)
        peer.connection.cancel()
    }

    /// HIGH-2：「連線 → 送 8 個 → 重連」不得繞過在途上限：名額按 iPad 計，工作真的結束才歸還
    @Test func reconnectingDoesNotBypassInFlightLimit() async throws {
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(handler: handler)
        let body: [String: Any] = ["cursor": NSNull(), "limit": 10]
        for _ in 0..<4 {
            let peer = try #require(await TestPeer.tls(port: h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint))
            let hello = try #require(await peer.nextKind())
            let object = try #require(try JSONSerialization.jsonObject(with: hello.data) as? [String: Any])
            let nonceText = try #require((object["body"] as? [String: Any])?["sessionNonce"] as? String)
            let nonce = try #require(Data(base64Encoded: nonceText))
            for seq in 1...TransportLimits.maxInFlightPerConnection {
                peer.send(envelope(kind: "catalog.page", body: body, seq: UInt64(seq), nonce: nonce))
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(handler.calls <= TransportLimits.maxInFlightPerConnection, "handler calls \(handler.calls)")
        handler.releaseAll()
    }

    /// HIGH-1：不讀取的 iPad（收不到 Mac 的 ping、也就不會回 pong）在心跳期限內被斷線，Mac 堆積的回覆因此有上限
    @Test func peerThatNeverReadsIsDisconnected() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let peer = try #require(await SilentPeer(port: h.port, identity: h.ipadIdentity, pin: h.macIdentity.fingerprint))
        #expect(await waitFor { h.server.connectedPeers.count == 1 })
        // iPad 照常送 ping（lastActivity 會更新），但從不讀
        let keepAlive = Task { for _ in 0..<10 { peer.ping(); try? await Task.sleep(for: .milliseconds(500)) } }
        #expect(await waitFor(TransportTimings.test.heartbeatDeadline + 2) { h.server.connectedPeers.isEmpty })
        keepAlive.cancel()
        peer.connection.cancel()
    }

    /// security 複核 NEW-1：不讀的 iPad 自己定時送 pong（沒帶 Mac ping 的隨機內容）不得撐住連線
    @Test func unsolicitedPongsDoNotKeepNonReaderAlive() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let peer = try #require(await SilentPeer(port: h.port, identity: h.ipadIdentity, pin: h.macIdentity.fingerprint))
        #expect(await waitFor { h.server.connectedPeers.count == 1 })
        let forge = Task {
            for i in 0..<20 {
                if i % 2 == 0 { peer.ping() }        // 約每 0.6 s 一個，低於每秒 2 個的 ping 上限（否則會被判 ping 洪水而假綠）
                peer.connection.send(content: Data("forged".utf8), contentContext: .init(identifier: "pong", metadata: [NWProtocolWebSocket.Metadata(opcode: .pong)]),
                                     isComplete: true, completion: .idempotent)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        #expect(await waitFor(TransportTimings.test.heartbeatDeadline + 2) { h.server.connectedPeers.isEmpty })
        forge.cancel()
        peer.connection.cancel()
    }

    /// 回 pong 的正常 client 不會被誤斷
    @Test func readingClientStaysConnectedPastHeartbeatDeadline() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        try? await Task.sleep(for: .seconds(TransportTimings.test.heartbeatDeadline * 2))
        #expect(session.isOpen && h.server.connectedPeers.count == 1)
        session.close()
    }

    /// LOW-2：限流與畸形請求的稽核要取樣，不能每則一筆
    @Test func rejectionAuditIsSampled() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let peer = try #require(await SilentPeer(port: h.port, identity: h.ipadIdentity, pin: h.macIdentity.fingerprint))
        for _ in 0..<200 { peer.send(Data("x".utf8)) }
        try? await Task.sleep(for: .milliseconds(800))
        let rejections = h.audit.events.filter { $0 == .rateLimited(.control) || $0 == .connectionRejected(.invalidRequest) }
        #expect(rejections.count <= 4, "audit rejections \(rejections.count)")
        peer.connection.cancel()
    }
}

/// MEDIUM-1：單一 grapheme 帶數萬個組合符號（NFKC 正規化 O(n²)）不得通過驗證
struct PathologicalQueryTests {
    @Test func combiningMarkBombIsRejected() {
        let bomb = "a" + String(repeating: "\u{0301}", count: 15_000) + String(repeating: "\u{0316}", count: 15_000)
        #expect(bomb.count == 1)
        #expect(!CatalogSearchRequest(query: bomb, limit: 5).isValid)
    }

    @Test func ordinaryLongQueryStillValid() {
        #expect(CatalogSearchRequest(query: String(repeating: "é", count: 64), limit: 5).isValid)
    }
}
#endif
