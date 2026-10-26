import Foundation
import Network
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S3 T14／S2 延後 LOW-1（sprint-3-detail.md §4.12）：revoke 不論落在 classify 之前、兩步之間或之後，
// 被解除的 iPad 都不得留在正常路徑（N-04 撤銷立即中斷）

#if os(macOS)
@Suite(.serialized) struct RevokeClassifyRaceTests {
    private func waitFor(_ timeout: TimeInterval = 3, _ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func pairedPeerID(_ h: Harness) async throws -> UUID {
        guard case .approved = await h.pair() else { throw CancellationError() }
        return try #require(h.macTrust.validRecords(for: h.macIdentity.fingerprint).first?.peerID)
    }

    @Test func revokeBetweenTrustReadAndLockRejectsConnection() async throws {
        let h = try await Harness()
        let peerID = try await pairedPeerID(h)
        let fired = Locked(false)
        h.server.classifySeam.withLock { seam in
            seam = { [server = h.server] in
                guard !fired.withLock({ done in defer { done = true }; return done }) else { return }
                server.revoke(peerID: peerID)
            }
        }
        let events = Locked<[ServerEvent]>([])
        let collector = Task { for await event in h.server.events { events.withLock { $0.append(event) } } }
        let peer = try #require(await TestPeer.tls(port: h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint))
        // 不得被收進正常路徑：收不到 session.hello，也不得發出 peerConnected（不能靠 1.5 s 心跳逾時才斷）
        #expect(await peer.nextKind(timeout: 1)?.kind != "session.hello")
        #expect(fired.withLock { $0 })
        #expect(!events.withLock { $0 }.contains(.peerConnected(peerID)))
        #expect(h.server.connectedPeers.isEmpty)
        collector.cancel()
    }

    @Test func revokeAfterClassifyDisconnects() async throws {
        let h = try await Harness()
        let peerID = try await pairedPeerID(h)
        let peer = try #require(await TestPeer.tls(port: h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint))
        #expect(await peer.nextKind()?.kind == "session.hello")
        h.server.revoke(peerID: peerID)
        #expect(await peer.waitClosed())
        #expect(h.server.connectedPeers.isEmpty)
    }

    /// S2 遺留：心跳逾時被巡檢清掉的連線沒有送 peerDisconnected（Mac 裝置清單會一直顯示已連線）
    @Test func idleTimeoutAnnouncesDisconnect() async throws {
        let h = try await Harness()
        let peerID = try await pairedPeerID(h)
        let events = Locked<[ServerEvent]>([])
        let collector = Task { for await event in h.server.events { events.withLock { $0.append(event) } } }
        let peer = try #require(await TestPeer.tls(port: h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint))
        #expect(await peer.nextKind()?.kind == "session.hello")
        #expect(await peer.waitClosed(timeout: 4))                      // 不送 ping → heartbeatDeadline 後被清
        #expect(await waitFor { events.withLock { $0 }.contains(.peerDisconnected(peerID)) })
        collector.cancel()
    }

    @Test func revokeBeforeConnectingIsRejected() async throws {
        let h = try await Harness()
        let peerID = try await pairedPeerID(h)
        h.server.revoke(peerID: peerID)
        let peer = await TestPeer.tls(port: h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint)
        if let peer { #expect(await peer.waitClosed()) }
        #expect(h.server.connectedPeers.isEmpty)
    }
}
#endif
