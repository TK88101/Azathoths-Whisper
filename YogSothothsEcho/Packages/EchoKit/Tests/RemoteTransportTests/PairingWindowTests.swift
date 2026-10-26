import Foundation
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S2 T4（sprint-2-detail.md §4.6；CR-010 ②(e)(g)(k)）：配對窗純狀態機

struct PairingWindowTests {
    let t0 = Date(timeIntervalSince1970: 10_000)
    let secret = Data(repeating: 0x5A, count: 32)
    let sid = Data(repeating: 0x11, count: 16)
    let fpM = Fingerprint(bytes: Data(repeating: 0xA1, count: 32))!
    let fpI = Fingerprint(bytes: Data(repeating: 0xB2, count: 32))!
    let exporter = Data(repeating: 0xC3, count: 32)
    let conn = ConnectionID()
    let peerID = UUID()

    func opened() -> (PairingWindow, QRPairingPayload) {
        var window = PairingWindow()
        let (payload, _) = window.open(sessionID: sid, secret: secret, macFingerprint: fpM, instanceName: "Azathoth-A1A1", now: t0)
        return (window, payload)
    }

    func proof(_ window: inout PairingWindow, conn: ConnectionID? = nil, secret: Data? = nil, sid: Data? = nil,
               fpI: Fingerprint? = nil, name: String = "iPad", at offset: TimeInterval = 1) -> [PairingEffect] {
        let p = PairingProof.compute(secret: secret ?? self.secret, sessionID: sid ?? self.sid, macFingerprint: fpM,
                                     ipadFingerprint: fpI ?? self.fpI, exporter: exporter)
        return window.handleProof(PairProof(sessionID: sid ?? self.sid, proof: p, deviceName: name), from: conn ?? self.conn,
                                  ipadFingerprint: fpI ?? self.fpI, exporter: exporter, now: t0.addingTimeInterval(offset))
    }

    @Test func openProducesPayloadBoundToWindow() {
        let (window, payload) = opened()
        #expect(window.isOpen)
        #expect(payload.sessionID == sid && payload.secret == secret && payload.macFingerprint == fpM)
    }

    @Test func validProofMovesToPendingAndAsksForConfirmation() {
        var (window, _) = opened()
        let effects = proof(&window)
        #expect(!window.isOpen)
        #expect(effects.contains(.sendPending(conn, suffix: fpI.suffix)))
        #expect(effects.contains(.showConfirm(name: "iPad", suffix: fpI.suffix)))
    }

    @Test func invalidProofKeepsWindowOpenAndIsCounted() {
        var (window, _) = opened()
        let effects = proof(&window, secret: Data(repeating: 1, count: 32))
        #expect(window.isOpen)
        #expect(effects.contains(.sendError(conn, .pairingInvalid)))
        #expect(effects.contains(.close(conn)))
        #expect(window.invalidAttempts == 1)
    }

    @Test func wrongSessionIDIsInvalidNotAccepted() {
        var (window, _) = opened()
        let other = Data(repeating: 0x22, count: 16)
        let effects = proof(&window, sid: other)
        #expect(window.isOpen)
        #expect(effects.contains(.sendError(conn, .pairingInvalid)))
    }

    @Test func malformedBodyIsInvalid() {
        var (window, _) = opened()
        let effects = window.handleProof(PairProof(sessionID: Data(count: 3), proof: Data(count: 32), deviceName: "x"),
                                         from: conn, ipadFingerprint: fpI, exporter: exporter, now: t0)
        #expect(window.isOpen && effects.contains(.sendError(conn, .pairingInvalid)))
    }

    @Test func excessInvalidAttemptsTriggerCooldownWithoutClosing() {
        var (window, _) = opened()
        for i in 0..<TransportLimits.maxInvalidPairingAttempts {
            _ = proof(&window, conn: ConnectionID(), secret: Data(repeating: 1, count: 32), at: Double(i) * 0.1)
        }
        let now = t0.addingTimeInterval(1.5)
        #expect(window.isOpen)
        #expect(window.isCoolingDown(now: now))
        #expect(!window.isCoolingDown(now: now.addingTimeInterval(TransportLimits.pairingCooldown + 1)))
    }

    @Test func invalidTLSIsCountedAndKeepsWindowOpen() {
        var (window, _) = opened()
        window.recordInvalidAttempt(now: t0)
        #expect(window.isOpen && window.invalidAttempts == 1)
    }

    @Test func concurrentValidProofsExactlyOneWins() {
        var (window, _) = opened()
        let a = ConnectionID(), b = ConnectionID()
        let first = proof(&window, conn: a)
        let second = proof(&window, conn: b, fpI: Fingerprint(bytes: Data(repeating: 0xEE, count: 32))!)
        #expect(first.contains(.sendPending(a, suffix: fpI.suffix)))
        #expect(second.contains(.sendError(b, .pairingUnavailable)))
        #expect(second.contains(.close(b)))
    }

    @Test func approveRecordsPeerBoundToMacFingerprint() {
        var (window, _) = opened()
        _ = proof(&window, name: "iPad\u{202E}x")
        let effects = window.approve(peerID: peerID, now: t0.addingTimeInterval(5))
        let expected = PeerRecord(peerID: peerID, fingerprint: fpI, localFingerprint: fpM, name: "iPadx",
                                  pairedAt: t0.addingTimeInterval(5))
        #expect(effects.contains(.recordPeer(expected)))
        #expect(effects.contains(.sendResult(conn, .approved)))
        #expect(effects.contains(.dismissConfirm))
        #expect(window.outcome == .approved)
    }

    @Test func rejectAndCancelFinishWithoutRecord() {
        var (w1, _) = opened()
        _ = proof(&w1)
        let rejected = w1.reject()
        #expect(rejected.contains(.sendResult(conn, .rejected)) && !rejected.contains { if case .recordPeer = $0 { true } else { false } })
        var (w2, _) = opened()
        _ = proof(&w2)
        #expect(w2.cancel().contains(.sendResult(conn, .cancelled)))
        #expect(w2.outcome == .cancelled)
    }

    @Test func windowExpiresAt60s() {
        var (window, _) = opened()
        _ = window.tick(now: t0.addingTimeInterval(TransportLimits.qrLifetime - 0.1))
        #expect(window.isOpen)
        _ = window.tick(now: t0.addingTimeInterval(TransportLimits.qrLifetime))
        #expect(window.outcome == .expired)
    }

    @Test func pendingExpiresAfterApprovalTimeout() {
        var (window, _) = opened()
        _ = proof(&window, at: 10)
        let effects = window.tick(now: t0.addingTimeInterval(10 + TransportLimits.approvalTimeout))
        #expect(window.outcome == .expired)
        #expect(effects.contains(.sendResult(conn, .expired)) && effects.contains(.dismissConfirm))
    }

    @Test func proofAfterFinishIsUnavailable() {
        var (window, _) = opened()
        _ = window.cancel()
        let effects = proof(&window)
        #expect(effects.contains(.sendError(conn, .pairingUnavailable)))
    }

    @Test func pendingConnectionDroppingCancels() {
        var (window, _) = opened()
        _ = proof(&window)
        let effects = window.connectionClosed(conn)
        #expect(window.outcome == .cancelled && effects.contains(.dismissConfirm))
    }

    @Test func cancelRacingApproveYieldsSingleOutcome() {
        var (window, _) = opened()
        _ = proof(&window)
        _ = window.cancel()
        let late = window.approve(peerID: peerID, now: t0.addingTimeInterval(3))
        #expect(late.isEmpty)
        #expect(window.outcome == .cancelled)
    }

    @Test func reopeningReplacesWindowWithNewSession() {
        var (window, _) = opened()
        let newSid = Data(repeating: 0x33, count: 16)
        let (payload, _) = window.open(sessionID: newSid, secret: Data(repeating: 9, count: 32), macFingerprint: fpM,
                                       instanceName: "Azathoth-A1A1", now: t0.addingTimeInterval(2))
        #expect(payload.sessionID == newSid && window.isOpen)
        // 舊 session 的 proof 無效
        #expect(proof(&window, at: 3).contains(.sendError(conn, .pairingInvalid)))
    }

    /// `S` 的 API 不變式（§4.6）：離開 open 後，狀態與所有效果都取不到 S
    @Test func secretIsNotReachableAfterLeavingOpen() {
        var (window, _) = opened()
        let hex = secret.map { String(format: "%02x", $0) }.joined()
        var all: [PairingEffect] = proof(&window)
        all += window.approve(peerID: peerID, now: t0.addingTimeInterval(2))
        let dump = String(reflecting: window) + all.map { String(reflecting: $0) }.joined()
        #expect(!dump.contains(secret.base64EncodedString()))
        #expect(!dump.lowercased().contains(hex))
        #expect(!String(reflecting: opened().0).contains(secret.base64EncodedString()))
    }
}
