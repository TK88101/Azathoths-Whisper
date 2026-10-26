import Foundation
import Testing
@testable import RemoteProtocol

// S2（sprint-2-detail.md §4.2、CR-010）：配對與 session 的訊息、信封的 seq／nonce 規則、路徑與方向的 kind 白名單
struct PairingKindTests {
    @Test func pairingAndSessionKindsExist() {
        #expect(MessageKind(rawValue: "pair.proof") == .pairProof)
        #expect(MessageKind(rawValue: "pair.pending") == .pairPending)
        #expect(MessageKind(rawValue: "pair.result") == .pairResult)
        #expect(MessageKind(rawValue: "session.hello") == .sessionHello)
    }

    @Test func pairingErrorCodesExist() {
        #expect(ErrorCode(rawValue: "pairingInvalid") == .pairingInvalid)
        #expect(ErrorCode(rawValue: "pairingUnavailable") == .pairingUnavailable)
        #expect(ErrorCode(rawValue: "notPaired") == .notPaired)
    }
}

struct EnvelopeRuleTests {
    private let nonce = Data(repeating: 7, count: 16)

    private func header(_ kind: MessageKind, seq: UInt64? = nil, nonce: Data? = nil) -> EnvelopeHeader {
        EnvelopeHeader(v: ProtocolVersion.current, id: UUID(), kind: kind, seq: seq, nonce: nonce)
    }

    @Test func pairingPathFromIPadAcceptsOnlyProof() {
        #expect(EnvelopeRules.check(header(.pairProof), direction: .fromIPad, path: .pairing) == nil)
        for kind in MessageKind.allCases where kind != .pairProof {
            #expect(EnvelopeRules.check(header(kind), direction: .fromIPad, path: .pairing) == .invalidRequest, "\(kind)")
        }
    }

    @Test func pairingPathFromMacAcceptsPendingResultError() {
        for kind in [MessageKind.pairPending, .pairResult, .error] {
            #expect(EnvelopeRules.check(header(kind), direction: .fromMac, path: .pairing) == nil)
        }
        #expect(EnvelopeRules.check(header(.sessionHello), direction: .fromMac, path: .pairing) == .invalidRequest)
    }

    @Test func normalPathRejectsPairKindsBothWays() {
        for kind in [MessageKind.pairProof, .pairPending, .pairResult] {
            #expect(EnvelopeRules.check(header(kind, seq: 1, nonce: nonce), direction: .fromIPad, path: .normal) == .invalidRequest)
            #expect(EnvelopeRules.check(header(kind), direction: .fromMac, path: .normal) == .invalidRequest)
        }
    }

    @Test func normalRequestFromIPadRequiresSeqAndNonce() {
        #expect(EnvelopeRules.check(header(.playToggle, seq: 1, nonce: nonce), direction: .fromIPad, path: .normal) == nil)
        #expect(EnvelopeRules.check(header(.playToggle, nonce: nonce), direction: .fromIPad, path: .normal) == .invalidRequest)
        #expect(EnvelopeRules.check(header(.playToggle, seq: 1), direction: .fromIPad, path: .normal) == .replayed)
    }

    @Test func nonceMustBe16Bytes() {
        let short = Data(repeating: 1, count: 15)
        #expect(EnvelopeRules.check(header(.playToggle, seq: 1, nonce: short), direction: .fromIPad, path: .normal) == .invalidRequest)
    }

    @Test func seqAndNonceForbiddenElsewhere() {
        #expect(EnvelopeRules.check(header(.pairProof, seq: 1), direction: .fromIPad, path: .pairing) == .invalidRequest)
        #expect(EnvelopeRules.check(header(.pairProof, nonce: nonce), direction: .fromIPad, path: .pairing) == .invalidRequest)
        #expect(EnvelopeRules.check(header(.sessionHello, seq: 1), direction: .fromMac, path: .normal) == .invalidRequest)
    }

    @Test func iPadCannotSendMacOnlyKindsOnNormalPath() {
        for kind in [MessageKind.sessionHello, .eventPlayback, .eventCatalogChanged, .playResult] {
            #expect(EnvelopeRules.check(header(kind, seq: 1, nonce: nonce), direction: .fromIPad, path: .normal) == .invalidRequest)
        }
    }

    @Test func oversizedMessageIsInvalidBeforeParsing() {
        let big = Data(repeating: 0x20, count: TransportLimits.maxMessageBytes + 1)
        #expect(EnvelopeHeader.decode(big).failure == .invalidRequest)
    }

    @Test func headerWithSeqAndNonceRoundTrips() throws {
        let h = header(.playNext, seq: 42, nonce: nonce)
        #expect(try EnvelopeHeader.decode(JSONEncoder().encode(h)).get() == h)
    }
}

struct PairingBodyTests {
    private func roundTrip<B: Codable & Equatable>(_ body: B) throws -> B {
        try JSONDecoder().decode(B.self, from: JSONEncoder().encode(body))
    }

    @Test func proofValidatesLengths() {
        #expect(PairProof(sessionID: Data(count: 16), proof: Data(count: 32), deviceName: "iPad").isValid)
        #expect(!PairProof(sessionID: Data(count: 15), proof: Data(count: 32), deviceName: "iPad").isValid)
        #expect(!PairProof(sessionID: Data(count: 16), proof: Data(count: 31), deviceName: "iPad").isValid)
        let longName = String(repeating: "あ", count: 22) // 66 bytes
        #expect(!PairProof(sessionID: Data(count: 16), proof: Data(count: 32), deviceName: longName).isValid)
    }

    @Test func pendingSuffixIsFourUppercaseHex() {
        #expect(PairPending(suffix: "0A9F").isValid)
        #expect(!PairPending(suffix: "0a9f").isValid)
        #expect(!PairPending(suffix: "0A9").isValid)
        #expect(!PairPending(suffix: "0A9G").isValid)
    }

    @Test func helloNonceIs16Bytes() {
        #expect(SessionHello(sessionNonce: Data(count: 16)).isValid)
        #expect(!SessionHello(sessionNonce: Data(count: 8)).isValid)
    }

    @Test func bodiesRoundTrip() throws {
        let proof = PairProof(sessionID: Data(repeating: 1, count: 16), proof: Data(repeating: 2, count: 32), deviceName: "iPad")
        #expect(try roundTrip(proof) == proof)
        #expect(try roundTrip(PairResult(outcome: .approved)) == PairResult(outcome: .approved))
        #expect(try roundTrip(ErrorBody(code: .pairingUnavailable, retryable: false)) == ErrorBody(code: .pairingUnavailable, retryable: false))
    }

    @Test func unknownOutcomeFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PairResult.self, from: Data(#"{"outcome":"maybe"}"#.utf8))
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
