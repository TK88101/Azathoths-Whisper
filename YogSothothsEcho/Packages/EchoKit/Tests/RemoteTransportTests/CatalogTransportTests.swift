import Foundation
import Network
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S3 T7（sprint-3-detail.md §4.5、§4.6；CR-012）：業務請求分派、資源上限、每 peer 單連線、broadcast、iPad 端 request／events

// MARK: 待送位元組帳本（純值；Codex 最擔心的一點）

struct SendLedgerTests {
    let a = ConnectionID(), b = ConnectionID()

    @Test func reservesWithinBothLimits() throws {
        var ledger = SendLedger(perConnectionLimit: 100, totalLimit: 150)
        let reservedt1 = ledger.reserve(60, for: a)
        let t1 = try #require(reservedt1)
        #expect(ledger.reserve(50, for: a) == nil)              // a 會到 110 > 100
        let reservedt2 = ledger.reserve(80, for: b)
        let t2 = try #require(reservedt2)
        #expect(ledger.reserve(20, for: b) == nil)              // 總量會到 160 > 150
        #expect(ledger.total == 140 && ledger.pending(for: a) == 60)
        ledger.release(t1)
        ledger.release(t2)
        #expect(ledger.total == 0)
    }

    @Test func releaseIsIdempotent() throws {
        var ledger = SendLedger(perConnectionLimit: 100, totalLimit: 100)
        let reservedtoken = ledger.reserve(40, for: a)
        let token = try #require(reservedtoken)
        ledger.release(token)
        ledger.release(token)
        #expect(ledger.total == 0 && ledger.pending(for: a) == 0)
    }

    @Test func releaseAllThenLateCompletionDoesNotGoNegative() throws {
        var ledger = SendLedger(perConnectionLimit: 100, totalLimit: 200)
        let reservedt1 = ledger.reserve(30, for: a)
        let t1 = try #require(reservedt1)
        let extra = ledger.reserve(30, for: a)
        #expect(extra != nil)
        let reservedtb = ledger.reserve(50, for: b)
        let tb = try #require(reservedtb)
        ledger.releaseAll(for: a)                               // 連線關閉／被取代
        ledger.release(t1)                                      // 晚到的完成回呼
        #expect(ledger.total == 50 && ledger.pending(for: a) == 0)
        ledger.release(tb)
        #expect(ledger.total == 0)
    }

    @Test func randomizedSequenceNeverExceedsLimitsOrGoesNegative() {
        var ledger = SendLedger(perConnectionLimit: 1_000, totalLimit: 2_500)
        let connections = (0..<4).map { _ in ConnectionID() }
        var live: [SendLedger.Token] = []
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<5_000 {
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<6:
                if let token = ledger.reserve(Int.random(in: 1...700, using: &rng), for: connections.randomElement(using: &rng)!) {
                    live.append(token)
                }
            case 6..<9:
                if !live.isEmpty { ledger.release(live.remove(at: Int.random(in: 0..<live.count, using: &rng))) }
            default:
                ledger.releaseAll(for: connections.randomElement(using: &rng)!)
            }
            #expect(ledger.total >= 0 && ledger.total <= 2_500)
            #expect(connections.allSatisfy { (0...1_000).contains(ledger.pending(for: $0)) })
        }
    }
}

// MARK: localhost 整合

/// 可程式化的業務處理：記錄呼叫、可擋住直到放行
final class ScriptedHandler: RequestHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var blocking = false
    private var callCount = 0
    let reply: @Sendable (InboundRequest) -> OutboundReply

    init(reply: @escaping @Sendable (InboundRequest) -> OutboundReply = { $0.reply(CatalogChangedEvent(version: "0123456789abcdef")) }) {
        self.reply = reply
    }

    func block() { lock.withLock { blocking = true } }
    func releaseAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            blocking = false
            defer { gates = [] }
            return gates
        }
        pending.forEach { $0.resume() }
    }
    var calls: Int { lock.withLock { callCount } }
    var waiting: Int { lock.withLock { gates.count } }

    func handle(_ request: InboundRequest) async -> OutboundReply {
        let mustWait = lock.withLock { () -> Bool in callCount += 1; return blocking }
        if mustWait {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock { () -> Bool in
                    guard blocking else { return true }
                    gates.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        return reply(request)
    }
}

private func waitFor(_ timeout: TimeInterval = 3, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

private func pairedHarness(limits: ServerLimits = .relaxedForTests, handler: (any RequestHandling)?) async throws -> Harness {
    let h = try await Harness(limits: limits, handler: handler)
    guard case .approved = await h.pair() else { throw CancellationError() }
    return h
}

private func rawPeer(_ h: Harness, identity: DeviceIdentity? = nil) async throws -> (TestPeer, Data) {
    let peer = try #require(await TestPeer.tls(port: h.port, identity: identity ?? h.ipadIdentity, serverPin: h.macIdentity.fingerprint))
    let hello = try #require(await peer.nextKind())
    let object = try #require(try JSONSerialization.jsonObject(with: hello.data) as? [String: Any])
    let body = try #require(object["body"] as? [String: Any])
    let encoded = try #require(body["sessionNonce"] as? String)
    return (peer, try #require(Data(base64Encoded: encoded)))
}

private var pageBody: [String: Any] { ["cursor": NSNull(), "limit": 10] }
private var artworkBody: [String: Any] { ["albumID": "0123456789abcdef", "size": "spine", "artworkToken": "0123456789abcdef"] }

@Suite(.serialized) struct CatalogTransportTests {
    @Test func requestRoundTripsThroughHandler() async throws {
        let handler = ScriptedHandler { $0.reply(CatalogChangedEvent(version: "00000000000000aa")) }
        let h = try await pairedHarness(handler: handler)
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        let reply = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10), as: CatalogChangedEvent.self)
        #expect(reply.version == "00000000000000aa")
        #expect(handler.calls == 1)
        session.close()
    }

    /// S4 #4-1 D2 量測：呼叫端指定的請求 ID 原樣到達伺服端（iPad 與 Mac 兩邊的紀錄靠它逐筆對應）
    @Test func callerSuppliedRequestIDReachesTheHandler() async throws {
        let seen = Locked<UUID?>(nil)
        let handler = ScriptedHandler { request in
            seen.withLock { $0 = request.id }
            return request.reply(CatalogChangedEvent(version: "00000000000000aa"))
        }
        let h = try await pairedHarness(handler: handler)
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        let id = UUID()
        _ = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 1), as: CatalogChangedEvent.self, id: id)
        #expect(seen.withLock { $0 } == id)
        session.close()
    }

    /// S4 後半 security LOW-3：同一個請求 ID 還在等回覆時再用＝立刻失敗，不得把先前的等待者擠掉（它會永遠等不到）
    @Test func duplicateRequestIDFailsFastWithoutDisplacingTheFirst() async throws {
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(handler: handler)
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        let id = UUID()
        // 舊行為：第一個等待者被擠出等待表，逾時與斷線都喚不醒它——所以不 await，只限時看它有沒有結束
        let firstVersion = Locked<String?>(nil)
        let first = Task {
            let reply = try? await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 1), as: CatalogChangedEvent.self, id: id)
            firstVersion.withLock { $0 = reply?.version ?? "failed" }
        }
        #expect(await waitFor { handler.waiting == 1 })
        await #expect(throws: EchoRequestError.invalidResponse) {
            _ = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 1), as: CatalogChangedEvent.self,
                                          timeout: 0.5, id: id)
        }
        handler.releaseAll()
        #expect(await waitFor(5) { firstVersion.withLock { $0 } != nil })
        #expect(firstVersion.withLock { $0 } == "0123456789abcdef")
        if firstVersion.withLock({ $0 }) != nil { await first.value }
        session.close()
    }

    @Test func handlerErrorArrivesAsRemoteErrorWithRetryable() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler { _ in .error(.libraryUnavailable) })
        let (peer, nonce) = try await rawPeer(h)
        peer.send(envelope(kind: "catalog.page", body: pageBody, seq: 1, nonce: nonce))
        let reply = try #require(await peer.nextKind())
        let object = try #require(try JSONSerialization.jsonObject(with: reply.data) as? [String: Any])
        let body = try #require(object["body"] as? [String: Any])
        #expect(body["code"] as? String == "libraryUnavailable" && body["retryable"] as? Bool == true)

        let session = try await h.client().connect(endpoint: h.endpoint).get()
        await #expect(throws: EchoRequestError.remote(.libraryUnavailable)) {
            try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10), as: CatalogPageResponse.self)
        }
        session.close()
    }

    @Test func noHandlerKeepsS2BehaviourInvalidRequest() async throws {
        let h = try await pairedHarness(handler: nil)
        let (peer, nonce) = try await rawPeer(h)
        peer.send(envelope(kind: "catalog.page", body: pageBody, seq: 1, nonce: nonce))
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "invalidRequest")
    }

    @Test func requestTimesOutWhenMacDoesNotAnswer() async throws {
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(handler: handler)
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        await #expect(throws: EchoRequestError.timeout) {
            try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10), as: CatalogChangedEvent.self, timeout: 0.3)
        }
        handler.releaseAll()
        session.close()
    }

    @Test func pendingRequestsEndWhenConnectionCloses() async throws {
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(handler: handler)
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        let started = Date()
        async let result: Void = {
            await #expect(throws: EchoRequestError.disconnected) {
                try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10), as: CatalogChangedEvent.self, timeout: 10)
            }
        }()
        #expect(await waitFor { handler.waiting == 1 })
        h.server.stop()
        await result
        #expect(Date().timeIntervalSince(started) < 5)
        handler.releaseAll()
    }

    @Test func readQuotaIsSeparateFromControlQuota() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let (peer, nonce) = try await rawPeer(h)
        var seq: UInt64 = 0
        for _ in 0..<(TransportLimits.readPerSecond + 15) {
            seq += 1
            peer.send(envelope(kind: "catalog.page", body: pageBody, seq: seq, nonce: nonce))
        }
        var limited = 0
        for _ in 0..<(TransportLimits.readPerSecond + 15) {
            if await peer.nextKind().flatMap({ errorCode($0.data) }) == "rateLimited" { limited += 1 }
        }
        #expect(limited > 0)
        seq += 1
        peer.send(envelope(kind: "play.toggle", seq: seq, nonce: nonce))       // 控制類的桶不受影響
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } != "rateLimited")
    }

    @Test func malformedRequestsSpendControlQuota() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let (peer, _) = try await rawPeer(h)
        for _ in 0..<(TransportLimits.controlPerSecond + 10) { peer.send(Data("{not json".utf8)) }
        var codes: [String] = []
        for _ in 0..<(TransportLimits.controlPerSecond + 10) { if let code = await peer.nextKind().flatMap({ errorCode($0.data) }) { codes.append(code) } }
        #expect(codes.contains("rateLimited") && codes.contains("invalidRequest"))
    }

    @Test func inFlightLimitAnswersBusyWithoutCallingHandler() async throws {
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(handler: handler)
        let (peer, nonce) = try await rawPeer(h)
        for seq in 1...(TransportLimits.maxInFlightPerConnection + 1) {
            peer.send(envelope(kind: "catalog.page", body: pageBody, seq: UInt64(seq), nonce: nonce))
        }
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "busy")
        #expect(await waitFor { handler.calls == TransportLimits.maxInFlightPerConnection })
        handler.releaseAll()
    }

    @Test func artworkLimitsPerConnectionAndGlobal() async throws {
        var limits = ServerLimits.relaxedForTests
        limits.maxArtworkInFlightPerConnection = 2
        limits.maxArtworkInFlightTotal = 3
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(limits: limits, handler: handler)
        let (peer, nonce) = try await rawPeer(h)
        for seq in 1...3 { peer.send(envelope(kind: "artwork.get", body: artworkBody, seq: UInt64(seq), nonce: nonce)) }
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "busy")            // 每連線 2
        #expect(await waitFor { handler.waiting == 2 })
        #expect(h.server.artworkInFlightTotal == 2)
        handler.releaseAll()
        #expect(await waitFor { h.server.artworkInFlightTotal == 0 })
    }

    /// 全域封面上限是兩台 iPad 合計（每連線 2、全域 3：A 佔 2，B 只拿得到 1）
    @Test func artworkGlobalLimitIsSharedAcrossPeers() async throws {
        var limits = ServerLimits.relaxedForTests
        limits.maxArtworkInFlightPerConnection = 2
        limits.maxArtworkInFlightTotal = 3
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(limits: limits, handler: handler)
        let second = try TestIdentityFactory.make()
        guard case .approved = await h.pair(h.client(identity: second, trust: InMemoryTrustStore())) else {
            Issue.record("second pairing"); return
        }
        let (peerA, nonceA) = try await rawPeer(h)
        let (peerB, nonceB) = try await rawPeer(h, identity: second)
        for seq in 1...2 { peerA.send(envelope(kind: "artwork.get", body: artworkBody, seq: UInt64(seq), nonce: nonceA)) }
        #expect(await waitFor { h.server.artworkInFlightTotal == 2 })
        for seq in 1...2 { peerB.send(envelope(kind: "artwork.get", body: artworkBody, seq: UInt64(seq), nonce: nonceB)) }
        #expect(await peerB.nextKind().flatMap { errorCode($0.data) } == "busy")
        #expect(h.server.artworkInFlightTotal == 3)
        handler.releaseAll()
        #expect(await waitFor { h.server.artworkInFlightTotal == 0 })
    }

    @Test func pendingBytesLimitTurnsLargeReplyIntoBusy() async throws {
        var limits = ServerLimits.relaxedForTests
        limits.maxPendingSendBytesPerConnection = 10_000
        let big = String(repeating: "x", count: 20_000)
        let h = try await pairedHarness(limits: limits, handler: ScriptedHandler { $0.reply(CatalogChangedEvent(version: big)) })
        let (peer, nonce) = try await rawPeer(h)
        peer.send(envelope(kind: "catalog.page", body: pageBody, seq: 1, nonce: nonce))
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "busy")
        #expect(await waitFor { h.server.pendingSendBytesTotal == 0 })
    }

    /// security review HIGH-2：名額在工作真正結束時才歸還——關線不歸還（否則重連即可繞過上限）
    @Test func artworkQuotaReturnsWhenWorkFinishesNotWhenConnectionCloses() async throws {
        let handler = ScriptedHandler()
        handler.block()
        let h = try await pairedHarness(handler: handler)
        let (peer, nonce) = try await rawPeer(h)
        for seq in 1...3 { peer.send(envelope(kind: "artwork.get", body: artworkBody, seq: UInt64(seq), nonce: nonce)) }
        #expect(await waitFor { h.server.artworkInFlightTotal == 3 })
        peer.cancel()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(h.server.artworkInFlightTotal == 3)                    // 工作還在跑，名額未歸還
        handler.releaseAll()
        #expect(await waitFor { h.server.artworkInFlightTotal == 0 })
        #expect(h.server.pendingSendBytesTotal == 0)
    }

    @Test func secondConnectionFromSamePeerReplacesFirstWithoutDisconnectEvent() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let events = Locked<[ServerEvent]>([])
        let collector = Task { for await event in h.server.events { events.withLock { $0.append(event) } } }
        let (first, _) = try await rawPeer(h)
        let (second, nonce) = try await rawPeer(h)
        #expect(await first.waitClosed())
        try? await Task.sleep(for: .milliseconds(200))
        #expect(h.server.connectedPeers.count == 1)
        let seen = events.withLock { $0 }
        #expect(seen.filter { if case .peerConnected = $0 { true } else { false } }.count == 2)
        #expect(!seen.contains { if case .peerDisconnected = $0 { true } else { false } })
        second.send(envelope(kind: "catalog.page", body: pageBody, seq: 1, nonce: nonce))
        #expect(await second.nextKind()?.kind == "catalog.page")
        collector.cancel()
    }

    @Test func broadcastReachesNormalSessionsAsEvents() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        #expect(await waitFor { h.server.connectedPeers.count == 1 })
        h.server.broadcast(.eventCatalogChanged, CatalogChangedEvent(version: "00000000000000cc"))
        var iterator = session.events.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event?.kind == .eventCatalogChanged)
        #expect(event?.body(as: CatalogChangedEvent.self)?.version == "00000000000000cc")
        session.close()
    }

    /// N-05：曲庫請求與回覆的內容（搜尋字串、專輯名、token）不進稽核；稽核只有封閉列舉與 UUID
    @Test func catalogContentNeverReachesAudit() async throws {
        let secret = "ZqxUniqueFakeTitle"
        let handler = ScriptedHandler { $0.reply(CatalogSearchResponse(version: "00000000000000aa", albums: [
            AlbumSummary(id: "0123456789abcdef", title: secret, artist: secret, trackCount: 1, artworkToken: "fedcba9876543210")])) }
        let h = try await pairedHarness(handler: handler)
        let (peer, nonce) = try await rawPeer(h)
        var seq: UInt64 = 0
        for _ in 0..<(TransportLimits.readPerSecond + 5) {          // 也觸發讀取配額的稽核
            seq += 1
            peer.send(envelope(kind: "catalog.search", body: ["query": secret, "limit": 5], seq: seq, nonce: nonce))
        }
        peer.send(Data(secret.utf8))                                 // 畸形請求的稽核
        for _ in 0..<(TransportLimits.readPerSecond + 6) { _ = await peer.nextKind() }
        let rendered = h.audit.events.flatMap(AuditRenderer.fields).map(\.value).joined(separator: " ")
        #expect(!h.audit.events.isEmpty)
        #expect(!rendered.contains(secret) && !rendered.contains("fedcba9876543210"))
    }


    /// security 複核 HIGH：官方 client 並行送請求時，序號送出順序必須等於取號順序（否則 Mac 當重放拒絕）
    @Test func concurrentRequestsFromOneSessionAreNeverReplayRejected() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        var replayed = 0
        for _ in 0..<10 {
            await withTaskGroup(of: EchoRequestError?.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        do {
                            _ = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10), as: CatalogChangedEvent.self)
                            return nil
                        } catch let error as EchoRequestError { return error } catch { return .invalidResponse }
                    }
                }
                for await error in group where error == .remote(.replayed) { replayed += 1 }
            }
        }
        #expect(replayed == 0, "replayed \(replayed) of 40")
        #expect(session.isOpen)
        session.close()
    }

}

// MARK: S4 T2：play.track 以 play.result 回覆、iPad 依 kind 的逾時（sprint-4-detail.md §3、§4.8）

@Suite(.serialized) struct PlaybackReplyKindTests {
    @Test func playTrackReplyArrivesAsPlayResultAndClientAcceptsIt() async throws {
        let handler = ScriptedHandler { $0.reply(PlayResult(outcome: .verified, reason: nil)) }
        let h = try await pairedHarness(handler: handler)
        let (peer, nonce) = try await rawPeer(h)
        peer.send(envelope(kind: "play.track", body: ["trackID": "00000000000000aa", "albumID": "00000000000000bb"], seq: 1, nonce: nonce))
        #expect(await peer.nextKind()?.kind == "play.result")

        let session = try await h.client().connect(endpoint: h.endpoint).get()
        let result = try await session.request(.playTrack, PlayTrackRequest(trackID: "00000000000000aa", albumID: "00000000000000bb"),
                                               as: PlayResult.self)
        #expect(result == PlayResult(outcome: .verified, reason: nil))
        session.close()
    }

    @Test func otherKindsReplyWithTheirOwnKind() async throws {
        let handler = ScriptedHandler { $0.reply(CatalogChangedEvent(version: "00000000000000aa")) }
        let h = try await pairedHarness(handler: handler)
        let (peer, nonce) = try await rawPeer(h)
        peer.send(envelope(kind: "play.toggle", body: [:], seq: 1, nonce: nonce))
        #expect(await peer.nextKind()?.kind == "play.toggle")
    }

    @Test func defaultClientTimeoutFollowsPlaybackLimits() {
        #expect(ClientSession.timeout(for: .playTrack, explicit: nil) == PlaybackLimits.clientTimeout(.playTrack))
        #expect(ClientSession.timeout(for: .catalogPage, explicit: nil) == ClientSession.defaultRequestTimeout)
        #expect(ClientSession.timeout(for: .playTrack, explicit: 0.3) == 0.3)
    }
}

// MARK: S4 T6：連線 ID 與存活查詢（sprint-4-detail.md §4.4 連線撤離）

/// 記下每個請求帶來的連線 ID
final class ConnectionRecorder: RequestHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []
    var seen: [UUID] { lock.withLock { ids } }
    func handle(_ request: InboundRequest) async -> OutboundReply {
        lock.withLock { ids.append(request.connectionID) }
        return request.reply(CatalogChangedEvent(version: "00000000000000aa"))
    }
}

@Suite(.serialized) struct ConnectionLivenessTests {
    @Test func requestCarriesConnectionIDThatDiesWithTheConnection() async throws {
        let recorder = ConnectionRecorder()
        let h = try await pairedHarness(handler: recorder)
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        _ = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10), as: CatalogChangedEvent.self)
        let id = try #require(recorder.seen.first)
        #expect(h.server.isConnectionAlive(id))
        session.close()
        #expect(await waitFor { !h.server.isConnectionAlive(id) })
    }

    /// 同一台 iPad 重連（新連線取代舊連線）：新連線拿到不同的 ID，舊 ID 立即不存活
    @Test func connectionIDsAreNeverReusedAcrossReconnects() async throws {
        let recorder = ConnectionRecorder()
        let h = try await pairedHarness(handler: recorder)
        var ids: [UUID] = []
        for _ in 0..<3 {
            let session = try await h.client().connect(endpoint: h.endpoint).get()
            _ = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10), as: CatalogChangedEvent.self)
            ids.append(try #require(recorder.seen.last))
        }
        #expect(Set(ids).count == 3)
        #expect(!h.server.isConnectionAlive(ids[0]) && !h.server.isConnectionAlive(ids[1]))
        #expect(h.server.isConnectionAlive(ids[2]))
    }

    @Test func unknownIDIsNotAlive() async throws {
        let h = try await pairedHarness(handler: ConnectionRecorder())
        #expect(!h.server.isConnectionAlive(UUID()))
    }
}
