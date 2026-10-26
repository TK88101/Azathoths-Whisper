import Foundation
import Network
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S2 T6（sprint-2-detail.md §4.7、§7「L」）：localhost 上的配對、session 與攻擊情境。全部走 loopback，不用 Bonjour

#if os(macOS)
private func poll(_ timeout: TimeInterval = 3, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

final class Harness: Sendable {
    let clock = TestClock()
    let audit = SpyAuditSink()
    let macIdentity: DeviceIdentity
    let ipadIdentity: DeviceIdentity
    let macTrust = InMemoryTrustStore()
    let ipadTrust = InMemoryTrustStore()
    let server: TransportServer
    let port: NWEndpoint.Port

    init(allowLoopback: Bool = true, macIdentity: DeviceIdentity? = nil, macTrust: InMemoryTrustStore? = nil,
         limits: ServerLimits = .relaxedForTests, handler: (any RequestHandling)? = nil) async throws {
        self.macIdentity = try macIdentity ?? TestIdentityFactory.make()
        ipadIdentity = try TestIdentityFactory.make()
        let clock = self.clock
        server = TransportServer(configuration: ServerConfiguration(
            identity: self.macIdentity, trust: macTrust ?? self.macTrust, audit: audit, serviceName: nil,
            interfaces: { [] }, allowLoopback: allowLoopback, now: { clock.now }, timings: .test, limits: limits,
            requestHandler: handler))
        port = try await server.start()
    }

    deinit { server.stop() }

    var endpoint: NWEndpoint { .url(URL(string: "wss://127.0.0.1:\(port.rawValue)/")!) }

    func client(identity: DeviceIdentity? = nil, trust: InMemoryTrustStore? = nil, allowLoopback: Bool = true) -> TransportClient {
        TransportClient(configuration: ClientConfiguration(identity: identity ?? ipadIdentity, trust: trust ?? ipadTrust,
                                                           audit: audit, interfaces: { [] }, allowLoopback: allowLoopback,
                                                           timings: .test))
    }

    /// 完整配對：開窗 → 掃碼 → Mac 允許
    func pair(_ client: TransportClient? = nil) async -> PairingAttemptResult {
        let payload = server.openPairingWindow()
        let client = client ?? self.client()
        async let result = client.pair(endpoint: endpoint, payload: payload, deviceName: "Test iPad")
        _ = await poll { self.server.pendingPairing != nil }
        server.approvePairing()
        return await result
    }
}

@Suite(.serialized) struct TransportPairingTests {
    @Test func pairingHappyPathBindsBothSides() async throws {
        let h = try await Harness()
        let result = await h.pair()
        guard case .approved(let record) = result else { Issue.record("\(result)"); return }
        #expect(record.fingerprint == h.macIdentity.fingerprint && record.localFingerprint == h.ipadIdentity.fingerprint)
        let macSide = h.macTrust.validRecords(for: h.macIdentity.fingerprint)
        #expect(macSide.map(\.fingerprint) == [h.ipadIdentity.fingerprint])
        #expect(macSide.first?.name == "Test iPad")
        #expect(h.ipadTrust.validRecords(for: h.ipadIdentity.fingerprint).count == 1)
        #expect(!h.server.isPairingOpen)
    }

    @Test func pendingSuffixMatchesOnBothSides() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        let seen = Locked<String?>(nil)
        async let result = h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "x") { suffix in seen.withLock { $0 = suffix } }
        #expect(await poll { h.server.pendingPairing != nil && seen.withLock { $0 } != nil })
        #expect(h.server.pendingPairing?.suffix == h.ipadIdentity.fingerprint.suffix)
        #expect(seen.withLock { $0 } == h.ipadIdentity.fingerprint.suffix)
        h.server.rejectPairing()
        #expect(await result == .failed(.rejected))
    }

    @Test func pairingFailsWhenMacPresentsOtherCertificate() async throws {
        let h = try await Harness()
        let real = h.server.openPairingWindow()
        let forged = QRPairingPayload(sessionID: real.sessionID, macFingerprint: try TestIdentityFactory.make().fingerprint,
                                      secret: real.secret, instanceName: real.instanceName)!
        #expect(await h.client().pair(endpoint: h.endpoint, payload: forged, deviceName: "x") == .failed(.macPinMismatch))
        #expect(h.macTrust.validRecords(for: h.macIdentity.fingerprint).isEmpty)
    }

    @Test func serverRejectsUnknownClientWhenPairingClosed() async throws {
        let h = try await Harness()
        let peer = await TestPeer.tls(port: h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint)
        if let peer {
            #expect(await peer.nextKind(timeout: 1) == nil)
            #expect(await peer.waitClosed())
        }
        #expect(h.audit.events.contains(.connectionRejected(.unknownPeer)) || peer == nil)
    }

    @Test func invalidProofsKeepWindowOpenAndLegitStillPairs() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        let attacker = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(), serverPin: nil))
        attacker.send(envelope(kind: "pair.proof", body: ["sessionID": payload.sessionID.base64EncodedString(),
                                                          "proof": Data(count: 32).base64EncodedString(), "deviceName": "evil"]))
        let reply = await attacker.nextKind()
        #expect(reply?.kind == "error" && reply.flatMap { errorCode($0.data) } == "pairingInvalid")
        #expect(h.server.isPairingOpen)
        async let result = h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "x")
        _ = await poll { h.server.pendingPairing != nil }
        h.server.approvePairing()
        if case .approved = await result {} else { Issue.record("legit pairing failed") }
    }

    @Test func invalidTLSDuringPairingKeepsWindowOpenAndIsCounted() async throws {
        let h = try await Harness()
        _ = h.server.openPairingWindow()
        // 用錯的 pin 去連：client 側拒絕伺服端憑證 → 伺服端看到 TLS 失敗
        _ = await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(),
                               serverPin: Fingerprint(bytes: Data(repeating: 0, count: 32))!, timeout: 1)
        #expect(await poll { h.audit.events.contains(.invalidTLS) })
        #expect(h.server.isPairingOpen)
    }

    @Test func excessInvalidPairingAttemptsTriggerCooldown() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        for _ in 0..<TransportLimits.maxInvalidPairingAttempts {
            guard let attacker = await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(), serverPin: nil) else { continue }
            attacker.send(envelope(kind: "pair.proof", body: ["sessionID": payload.sessionID.base64EncodedString(),
                                                              "proof": Data(count: 32).base64EncodedString(), "deviceName": "e"]))
            _ = await attacker.nextKind()
            attacker.cancel()
        }
        #expect(h.server.isPairingOpen)
        #expect(await h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "x", timeout: 1) != .failed(.rejected))
        #expect(h.audit.events.contains(.connectionRejected(.cooldown)))
        #expect(h.macTrust.validRecords(for: h.macIdentity.fingerprint).isEmpty)
    }

    @Test func expiredQRIsUnavailable() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        h.clock.advance(TransportLimits.qrLifetime + 1)
        #expect(await poll { !h.server.isPairingOpen })
        let result = await h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "x", timeout: 1)
        #expect(result != .failed(.rejected))
        if case .approved = result { Issue.record("expired QR must not pair") }
    }

    @Test(arguments: ["reject", "cancel"]) func finishedSessionCannotBeReused(how: String) async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        async let first = h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "x")
        _ = await poll { h.server.pendingPairing != nil }
        how == "reject" ? h.server.rejectPairing() : h.server.cancelPairing()
        #expect(await first == .failed(how == "reject" ? .rejected : .cancelled))
        let again = await h.client(identity: try TestIdentityFactory.make()).pair(endpoint: h.endpoint, payload: payload,
                                                                                deviceName: "x", timeout: 1)
        if case .approved = again { Issue.record("finished session reused") }
    }

    @Test func leakedQRRequiresApprovalAndRejectionInvalidates() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        let thief = h.client(identity: try TestIdentityFactory.make(), trust: InMemoryTrustStore())
        async let stolen = thief.pair(endpoint: h.endpoint, payload: payload, deviceName: "iPad")
        _ = await poll { h.server.pendingPairing != nil }
        // 正牌 iPad 晚到：session 已被佔用
        #expect(await h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "iPad", timeout: 1) == .failed(.unavailable))
        h.server.rejectPairing()
        #expect(await stolen == .failed(.rejected))
        #expect(h.macTrust.validRecords(for: h.macIdentity.fingerprint).isEmpty)
        if case .approved = await h.pair() {} else { Issue.record("legit re-pair failed") }
    }

    @Test func proofBoundToExporterFailsOnRelayedConnection() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        let attackerID = try TestIdentityFactory.make()
        // 配對路徑同時只能 1 條：A 取得 exporter 後斷開，再用 B 送綁 A exporter 的 proof
        let a = try #require(await TestPeer.tls(port: h.port, identity: attackerID, serverPin: nil))
        let exporterA = try #require(a.exporter)
        a.cancel()
        _ = await poll { h.server.unclassifiedCount == 0 && !h.server.hasPairingConnection }
        let b = try #require(await TestPeer.tls(port: h.port, identity: attackerID, serverPin: nil))
        let relayed = PairingProof.compute(secret: payload.secret, sessionID: payload.sessionID,
                                           macFingerprint: payload.macFingerprint, ipadFingerprint: attackerID.fingerprint,
                                           exporter: exporterA)
        b.send(envelope(kind: "pair.proof", body: ["sessionID": payload.sessionID.base64EncodedString(),
                                                   "proof": relayed.base64EncodedString(), "deviceName": "x"]))
        #expect(await b.nextKind().flatMap { errorCode($0.data) } == "pairingInvalid")
    }

    @Test func pairingPathRejectsNormalKindsAndSeqNonce() async throws {
        let h = try await Harness()
        _ = h.server.openPairingWindow()
        let p1 = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(), serverPin: nil))
        p1.send(envelope(kind: "play.toggle"))
        #expect(await p1.nextKind().flatMap { errorCode($0.data) } == "invalidRequest")
        #expect(await p1.waitClosed())
        let p2 = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(), serverPin: nil))
        p2.send(envelope(kind: "pair.proof", body: [:], seq: 1, nonce: Data(count: 16)))
        #expect(await p2.nextKind().flatMap { errorCode($0.data) } == "invalidRequest")
    }
}

@Suite(.serialized) struct TransportSessionTests {
    func paired() async throws -> Harness {
        let h = try await Harness()
        guard case .approved = await h.pair() else { throw CancellationError() }
        return h
    }

    /// 已配對的 iPad 以 TestPeer 走正常路徑，回傳 peer 與 sessionNonce
    func normalPeer(_ h: Harness) async throws -> (TestPeer, Data) {
        let peer = try #require(await TestPeer.tls(port: h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint))
        let hello = try #require(await peer.nextKind())
        #expect(hello.kind == "session.hello")
        let object = try #require(try JSONSerialization.jsonObject(with: hello.data) as? [String: Any])
        let body = try #require(object["body"] as? [String: Any])
        let encoded = try #require(body["sessionNonce"] as? String)
        return (peer, try #require(Data(base64Encoded: encoded)))
    }

    /// simplify S2 第 1 輪（效率）：等待被取消時立即返回，不得變成空轉迴圈；session 本身不受影響
    @Test func waitUntilClosedReturnsPromptlyWhenCancelled() async throws {
        let h = try await paired()
        guard case .success(let session) = await h.client().connect(endpoint: h.endpoint) else { Issue.record("connect"); return }
        let started = Date()
        let waiter = Task { await session.waitUntilClosed() }
        try await Task.sleep(for: .milliseconds(100))
        waiter.cancel()
        await waiter.value
        #expect(Date().timeIntervalSince(started) < 1)
        #expect(session.isOpen)
        session.close()
    }

    @Test func pairedClientConnectsAndGetsSession() async throws {
        let h = try await paired()
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        #expect(session.isOpen)
        #expect(await poll { h.server.connectedPeers.count == 1 })
        session.close()
    }

    @Test func replayedSeqAndWrongNonceRejected() async throws {
        let h = try await paired()
        let (peer, nonce) = try await normalPeer(h)
        peer.send(envelope(kind: "play.toggle", seq: 1, nonce: nonce))
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "invalidRequest")   // S2 尚無業務 kind
        peer.send(envelope(kind: "play.toggle", seq: 1, nonce: nonce))
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "replayed")
        peer.send(envelope(kind: "play.toggle", seq: 2, nonce: Data(repeating: 1, count: 16)))
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "replayed")
        #expect(h.audit.events.contains(.replayRejected))
    }

    @Test func previousSessionFrameRejectedOnNewConnection() async throws {
        let h = try await paired()
        let (first, oldNonce) = try await normalPeer(h)
        first.cancel()
        let (second, _) = try await normalPeer(h)
        second.send(envelope(kind: "play.toggle", seq: 1, nonce: oldNonce))
        #expect(await second.nextKind().flatMap { errorCode($0.data) } == "replayed")
    }

    @Test func normalConnectionCannotSendPairKinds() async throws {
        let h = try await paired()
        let (peer, nonce) = try await normalPeer(h)
        peer.send(envelope(kind: "pair.proof", body: [:], seq: 1, nonce: nonce))
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "invalidRequest")
    }

    @Test func unknownKindRejectedAndAudited() async throws {
        let h = try await paired()
        let (peer, nonce) = try await normalPeer(h)
        peer.send(envelope(kind: "play.everything", seq: 1, nonce: nonce))
        #expect(await peer.nextKind().flatMap { errorCode($0.data) } == "invalidRequest")
        #expect(h.audit.events.contains(.connectionRejected(.invalidRequest)))
    }

    @Test func oversizedMessageDisconnects() async throws {
        let h = try await paired()
        let (peer, _) = try await normalPeer(h)
        peer.send(Data(repeating: 0x20, count: TransportLimits.maxMessageBytes + 1024))
        #expect(await peer.waitClosed())
    }

    @Test func controlFloodGetsRateLimited() async throws {
        let h = try await paired()
        let (peer, nonce) = try await normalPeer(h)
        for seq in 1...(TransportLimits.controlPerSecond + 10) {
            peer.send(envelope(kind: "play.toggle", seq: UInt64(seq), nonce: nonce))
        }
        var codes: [String] = []
        while let next = await peer.nextKind(timeout: 0.5) { codes.append(errorCode(next.data) ?? "") }
        #expect(codes.contains("rateLimited"))
        #expect(h.audit.events.contains(.rateLimited(.control)))
    }

    @Test func pingFloodDisconnects() async throws {
        let h = try await paired()
        let (peer, _) = try await normalPeer(h)
        for _ in 0..<12 { peer.sendPing() }
        #expect(await peer.waitClosed())
        #expect(h.audit.events.contains(.pingFlood))
    }

    @Test func idleConnectionIsDroppedAfterHeartbeatDeadline() async throws {
        let h = try await paired()
        let (peer, _) = try await normalPeer(h)
        #expect(await peer.waitClosed(timeout: TransportTimings.test.heartbeatDeadline + 2))
    }

    @Test func waitUntilClosedReturnsWhenMacDrops() async throws {
        let h = try await paired()
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        let waiter = Task { await session.waitUntilClosed() }
        h.server.stop()
        let finished = await poll(3) { !session.isOpen }
        #expect(finished)
        await waiter.value
    }

    @Test func clientHeartbeatKeepsSessionAlive() async throws {
        let h = try await paired()
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        try await Task.sleep(for: .seconds(TransportTimings.test.heartbeatDeadline * 2.5))
        #expect(session.isOpen)
        session.close()
    }

    @Test func newConnectionInvokesPinVerificationEveryTime() async throws {
        let h = try await paired()
        let before = h.server.verifyCount
        for _ in 0..<3 {
            let session = try await h.client().connect(endpoint: h.endpoint).get()
            session.close()
        }
        #expect(h.server.verifyCount - before == 3)
    }

    @Test func revokedPeerIsDisconnectedAndCannotReconnect() async throws {
        let h = try await paired()
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        let record = try #require(h.macTrust.validRecords(for: h.macIdentity.fingerprint).first)
        h.server.revoke(peerID: record.peerID)
        #expect(await poll { !session.isOpen })
        if case .success = await h.client().connect(endpoint: h.endpoint) { Issue.record("revoked peer reconnected") }
        #expect(h.audit.events.contains(.peerRevoked(peerID: record.peerID)))
    }

    @Test func revokingOnePeerKeepsOther() async throws {
        let h = try await paired()
        let secondID = try TestIdentityFactory.make()
        let secondTrust = InMemoryTrustStore()
        guard case .approved = await h.pair(h.client(identity: secondID, trust: secondTrust)) else { throw CancellationError() }
        let first = try #require(h.macTrust.validRecords(for: h.macIdentity.fingerprint).first { $0.fingerprint == h.ipadIdentity.fingerprint })
        h.server.revoke(peerID: first.peerID)
        let session = try await h.client(identity: secondID, trust: secondTrust).connect(endpoint: h.endpoint).get()
        #expect(session.isOpen)
        session.close()
    }

    @Test func macIdentityRebuildInvalidatesAllIPads() async throws {
        let h = try await paired()
        h.server.stop()
        let rebuilt = try await Harness(macIdentity: try TestIdentityFactory.make(), macTrust: h.macTrust)
        // iPad 的 pin 是舊 Mac；新 Mac 的信任紀錄也因 localFingerprint 不符而失效
        if case .success = await h.client().connect(endpoint: rebuilt.endpoint) { Issue.record("rebuilt Mac accepted old iPad") }
        #expect(h.macTrust.validRecords(for: rebuilt.macIdentity.fingerprint).isEmpty)
    }

    @Test func ipadIdentityRebuildRequiresRepairing() async throws {
        let h = try await paired()
        let rebuilt = try TestIdentityFactory.make()
        if case .success = await h.client(identity: rebuilt).connect(endpoint: h.endpoint) { Issue.record("rebuilt iPad accepted") }
    }

    @Test func impostorServiceWithSameNameFailsPin() async throws {
        let h = try await paired()
        let impostor = try await Harness()
        if case .success = await h.client().connect(endpoint: impostor.endpoint) { Issue.record("impostor accepted") }
    }
}

@Suite(.serialized) struct TransportAbuseTests {
    @Test func rawTCPConnectionFloodIsCappedBeforeTLS() async throws {
        let h = try await Harness(limits: .standard)
        var peers: [TestPeer] = []
        for _ in 0..<10 { if let p = await TestPeer.rawTCP(port: h.port) { peers.append(p) } }
        #expect(await poll { h.audit.events.contains(.connectionRejected(.capacity)) })
        #expect(h.server.unclassifiedCount <= TransportLimits.maxUnclassifiedConnections)
        peers.forEach { $0.cancel() }
    }

    /// security review S2 M-2：配對路徑已被佔用時，第二個未知對端（TLS 已完成）必須被斷線，不得掛著佔資源
    @Test func secondPairingCandidateIsClosedWhileSlotIsTaken() async throws {
        let h = try await Harness()
        _ = h.server.openPairingWindow()
        let squatter = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(),
                                                       serverPin: h.macIdentity.fingerprint))
        #expect(await poll { h.server.hasPairingConnection })
        let second = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(),
                                                     serverPin: h.macIdentity.fingerprint))
        #expect(await second.waitClosed(timeout: 1))
        squatter.cancel()
    }

    /// security 補查 LOW：佔位者以合法頻率的 WebSocket ping（低於 maxPingsPerSecond）保活，也不能延長 proof 期限（期限自分類起算）
    @Test func pingingSquatterIsStillDroppedAtProofDeadline() async throws {
        let h = try await Harness()
        _ = h.server.openPairingWindow()
        let squatter = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(),
                                                       serverPin: h.macIdentity.fingerprint))
        #expect(await poll { h.server.hasPairingConnection })
        let pinger = Task { while !Task.isCancelled { squatter.sendPing(); try? await Task.sleep(for: .milliseconds(510)) } }
        defer { pinger.cancel() }
        #expect(await squatter.waitClosed(timeout: TransportTimings.test.handshakeTimeout * 3))
        #expect(!h.server.hasPairingConnection)
    }

    /// security 補查 LOW：重開配對窗時，舊窗留下、未交有效 proof 的配對連線一併斷開（open() 原子換窗，巡檢看不到空檔）
    @Test func reopeningPairingWindowDropsUnprovenPairingConnections() async throws {
        let h = try await Harness()
        _ = h.server.openPairingWindow()
        let squatter = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(),
                                                       serverPin: h.macIdentity.fingerprint))
        #expect(await poll { h.server.hasPairingConnection })
        _ = h.server.openPairingWindow()
        #expect(await squatter.waitClosed(timeout: TransportTimings.test.handshakeTimeout / 2))
    }

    /// security 補查 LOW：proof 送出後呼叫端取消，仍要等到 Mac 的結果（否則 Mac 已存紀錄而 iPad 沒存）
    @Test func cancellingPairAfterProofStillReportsMacOutcome() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        let client = h.client()
        let task = Task { await client.pair(endpoint: h.endpoint, payload: payload, deviceName: "Test iPad") }
        #expect(await poll { h.server.pendingPairing != nil })
        task.cancel()
        try await Task.sleep(for: .milliseconds(100))
        h.server.approvePairing()
        guard case .approved(let record) = await task.value else { Issue.record("cancelled pair lost Mac outcome"); return }
        #expect(h.ipadTrust.validRecords(for: h.ipadIdentity.fingerprint) == [record])
    }

    /// M-1 修正的回歸防線：proof 已被接受、等 Mac 確認的連線不受 proof 期限影響（使用者可以慢慢按允許）
    @Test func slowApprovalAfterProofDeadlineStillPairs() async throws {
        let h = try await Harness()
        let payload = h.server.openPairingWindow()
        async let result = h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "Test iPad")
        #expect(await poll { h.server.pendingPairing != nil })
        try await Task.sleep(for: .seconds(TransportTimings.test.handshakeTimeout * 2))
        h.server.approvePairing()
        if case .approved = await result {} else { Issue.record("slow approval lost") }
    }

    /// security review S2 M-1：進了配對路徑卻不送 proof 的連線，在期限（handshakeTimeout）後被斷，正牌 iPad 隨後可配對
    @Test func silentPairingConnectionIsDroppedAndLegitIPadCanPair() async throws {
        let h = try await Harness()
        _ = h.server.openPairingWindow()
        let squatter = try #require(await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(),
                                                       serverPin: h.macIdentity.fingerprint))
        #expect(await poll { h.server.hasPairingConnection })
        #expect(await squatter.waitClosed(timeout: TransportTimings.test.handshakeTimeout + 1))
        #expect(!h.server.hasPairingConnection)
        if case .approved = await h.pair() {} else { Issue.record("legit iPad could not pair after squatter") }
    }

    /// §7：不回應的 TCP 對端＋網路 queue 被佔住——watchdog 在獨立 queue，仍須在期限內取消並釋放名額（T6 DoD）
    @Test func stalledHandshakeIsCancelledByWatchdog() async throws {
        let h = try await Harness(limits: .standard)
        guard let peer = await TestPeer.rawTCP(port: h.port) else { Issue.record("raw TCP did not connect"); return }
        #expect(await poll { h.server.unclassifiedCount == 1 })
        let timeout = TransportTimings.test.handshakeTimeout
        let released = Locked(false)
        h.server.occupyNetworkQueue(for: timeout + 2) { released.withLock { $0 = true } }
        #expect(await poll(timeout + 1) { h.audit.events.contains(.handshakeTimeout) })
        #expect(h.server.unclassifiedCount == 0)
        #expect(!released.withLock { $0 }, "watchdog 應在網路 queue 仍被佔住時觸發")
        peer.cancel()
    }

    @Test func halfOpenHandshakesReleaseSlotsOnWatchdog() async throws {
        let h = try await Harness(limits: .standard)
        var peers: [TestPeer] = []
        for _ in 0..<TransportLimits.maxUnclassifiedPerSource { if let p = await TestPeer.rawTCP(port: h.port) { peers.append(p) } }
        #expect(await poll(TransportTimings.test.handshakeTimeout + 2) { h.audit.events.contains(.handshakeTimeout) })
        #expect(await poll { h.server.unclassifiedCount == 0 })
        let result = await h.pair()
        guard case .approved = result else { Issue.record("slots not released: \(result) audit=\(h.audit.events)"); return }
        peers.forEach { $0.cancel() }
    }

    @Test func nonLocalPeerIsCancelledBeforeTLS() async throws {
        let h = try await Harness(allowLoopback: false)
        _ = h.server.openPairingWindow()
        _ = await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(), serverPin: nil, timeout: 1)
        #expect(await poll { h.audit.events.contains(.nonLocalPeer) })
        #expect(h.server.verifyCount == 0)
    }

    @Test func clientDisconnectsWhenResolvedPeerIsNotOnLink() async throws {
        let h = try await Harness()
        guard case .approved = await h.pair() else { throw CancellationError() }
        let result = await h.client(allowLoopback: false).connect(endpoint: h.endpoint)
        #expect(result.failure == .notOnLink)
    }

    @Test(arguments: ["127.0.0.1", "::1"]) func inboundEndpointIsHostPort(host: String) async throws {
        let h = try await Harness()
        _ = h.server.openPairingWindow()
        _ = await TestPeer.tls(port: h.port, identity: try TestIdentityFactory.make(), serverPin: nil, host: host, timeout: 1)
        #expect(await poll { h.server.nonHostPortInbound == 0 && h.server.verifyCount >= 1 })
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
/// F-2（`docs/plans/2026-10-17-yse-f2-pairing-event-order.md`）：iPad proof 剛完成 open→pending 轉移、效果尚未送出時，
/// 另一執行緒的配對操作不得讓同窗的 terminal 事件排到 pending 之前
@Suite(.serialized) struct PairingEventOrderTests {
    struct RaceResult { let events: [ServerEvent]; let rivalFinishedInGap: Bool }

    static let gapWait: TimeInterval = 0.5

    func race(_ h: Harness, rival: @escaping @Sendable () -> Void) async -> RaceResult {
        let fired = Locked(false), finishedInGap = Locked(false), collected = Locked<[ServerEvent]>([])
        h.server.afterTransitionSeam.withLock { seam in
            seam = { effects in
                guard effects.contains(where: { if case .showConfirm = $0 { true } else { false } }),
                      !fired.withLock({ let was = $0; $0 = true; return was }) else { return }
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global().async { rival(); done.signal() }
                let finished = done.wait(timeout: .now() + Self.gapWait) == .success
                finishedInGap.withLock { $0 = finished }
            }
        }
        let events = h.server.events
        let collector = Task {
            for await event in events {
                switch event {
                case .pairingPending, .pairingFinished: collected.withLock { $0.append(event) }
                default: break
                }
                if collected.withLock({ $0.count }) >= 2 { return }
            }
        }
        let payload = h.server.openPairingWindow()
        async let attempt = h.client().pair(endpoint: h.endpoint, payload: payload, deviceName: "iPad", timeout: 3)
        _ = await poll(5) { collected.withLock { $0.count } >= 2 }
        collector.cancel()
        _ = await attempt
        h.server.afterTransitionSeam.withLock { $0 = nil }
        return RaceResult(events: collected.withLock { $0 }, rivalFinishedInGap: finishedInGap.withLock { $0 })
    }

    func shape(_ events: [ServerEvent]) -> [String] {
        events.map { if case .pairingFinished(let o) = $0 { "finished(\(o.rawValue))" } else { "pending" } }
    }

    @Test func pendingIsNotOvertakenByConcurrentCancel() async throws {
        let h = try await Harness()
        let result = await race(h) { h.server.cancelPairing() }
        #expect(shape(result.events) == ["pending", "finished(cancelled)"])
        #expect(!result.rivalFinishedInGap)
    }

    @Test func pendingIsNotOvertakenByConcurrentOpen() async throws {
        let h = try await Harness()
        let result = await race(h) { _ = h.server.openPairingWindow() }
        #expect(shape(result.events) == ["pending", "finished(cancelled)"])
        #expect(!result.rivalFinishedInGap)
    }

    @Test func pendingIsNotOvertakenByConcurrentSweep() async throws {
        let h = try await Harness()
        let result = await race(h) {
            h.clock.advance(TransportLimits.approvalTimeout + 1)
            h.server.sweep()
        }
        #expect(shape(result.events) == ["pending", "finished(expired)"])
        #expect(!result.rivalFinishedInGap)
    }
}
#endif
