import Foundation
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S2 T8（sprint-2-detail.md §4.10、§4.7 鎖序、§7）

private let allEvents: [AuditEvent] = [
    .pairingWindowOpened, .invalidTLS, .pairingAccepted(peerID: UUID()), .handshakeTimeout, .replayRejected,
    .peerRevoked(peerID: UUID()), .identityReset, .nonLocalPeer, .pingFlood, .trustStoreCorrupt,
] + ProofRejection.allCases.map { .pairingProofRejected($0) } + PairOutcome.allCases.map { .pairingFinished($0) }
    + ConnectionRejection.allCases.map { .connectionRejected($0) } + LimitKind.allCases.map { .rateLimited($0) }

struct AuditRendererTests {
    @Test func auditRendererFieldsAreFixedAndContainNoSecrets() {
        let secret = Data(repeating: 0x5A, count: 32)
        let payload = QRPairingPayload(sessionID: Data(repeating: 1, count: 16), macFingerprint: Fingerprint(bytes: Data(repeating: 2, count: 32))!,
                                       secret: secret, instanceName: "Azathoth-0202")!
        let forbidden = [secret.base64EncodedString(), payload.encoded(), "5a5a5a5a", "Test iPad", "0202020202"]
        let sink = SpyRenderedSink()
        for event in allEvents { RenderingAuditSink(output: sink).record(event) }
        #expect(sink.lines.count == allEvents.count)
        for fields in sink.lines {
            #expect(fields.map(\.key) == ["event", "reason", "peer"])
            for value in fields.map(\.value) {
                #expect(forbidden.allSatisfy { !value.lowercased().contains($0.lowercased()) }, "\(value)")
            }
        }
    }

    @Test func peerFieldIsOnlyUUIDOrEmpty() {
        for event in allEvents {
            let peer = AuditRenderer.fields(event).first { $0.key == "peer" }!.value
            #expect(peer.isEmpty || UUID(uuidString: peer) != nil)
        }
    }
}

final class SpyRenderedSink: RenderedAuditOutput {
    private let store = Locked<[[AuditRenderer.Field]]>([])
    var lines: [[AuditRenderer.Field]] { store.withLock { $0 } }
    func write(_ fields: [AuditRenderer.Field]) { store.withLock { $0.append(fields) } }
}

struct TLSSettingsTests {
    @Test func tlsParametersDisableTicketsAndResumption() {
        #expect(TLSConfiguration.ticketsEnabled == false)
        #expect(TLSConfiguration.resumptionEnabled == false)
        #expect(TLSConfiguration.exporterLabel == "EXPORTER-yse-pair-v1" && TLSConfiguration.exporterLength == 32)
    }
}

#if os(macOS)
@Suite(.serialized) struct ServerConcurrencyTests {
    @Test func gateSnapshotExcludesRecordsOfPreviousIdentity() async throws {
        let identity = try TestIdentityFactory.make()
        let trust = InMemoryTrustStore()
        let stale = Fingerprint(bytes: Data(repeating: 7, count: 32))!
        try trust.add(PeerRecord(peerID: UUID(), fingerprint: stale, localFingerprint: Fingerprint(bytes: Data(repeating: 8, count: 32))!,
                                 name: "old", pairedAt: Date()))
        let server = TransportServer(configuration: ServerConfiguration(identity: identity, trust: trust, audit: NoopAuditSink(),
                                                                        serviceName: nil, interfaces: { [] }, timings: .test))
        _ = try await server.start()
        #expect(!server.gate.current.trusted.contains(stale))
        server.stop()
    }

    @Test func verifyAndStateUpdatesUnderConcurrencyDoNotDeadlock() async throws {
        let identity = try TestIdentityFactory.make()
        let server = TransportServer(configuration: ServerConfiguration(identity: identity, trust: InMemoryTrustStore(), audit: NoopAuditSink(),
                                                                        serviceName: nil, interfaces: { [] }, timings: .test))
        _ = try await server.start()
        let unknown = Fingerprint(bytes: Data(repeating: 3, count: 32))!
        let finished = await withTaskGroup(of: Void.self, returning: Bool.self) { group in
            for i in 0..<1_000 {
                group.addTask {
                    if i % 3 == 0 { _ = server.openPairingWindow() } else if i % 3 == 1 { _ = server.verifyForTesting(unknown) } else { server.cancelPairing() }
                }
            }
            let deadline = Task { try? await Task.sleep(for: .seconds(10)) }
            await group.waitForAll()
            deadline.cancel()
            return true
        }
        #expect(finished)
        server.stop()
    }
}
#endif
