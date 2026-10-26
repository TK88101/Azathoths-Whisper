import CryptoKit
import Foundation
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S2 T2（sprint-2-detail.md §4.3–§4.5、§4.8）：純值元件

struct FingerprintTests {
    @Test func derFingerprintIsSHA256AndSuffixIsLastTwoBytesUppercaseHex() throws {
        let der = Data("certificate".utf8)
        let fp = Fingerprint(der: der)
        #expect(fp.bytes == Data(SHA256.hash(data: der)))
        let tail = fp.bytes.suffix(2).map { String(format: "%02X", $0) }.joined()
        #expect(fp.suffix == tail)
        #expect(fp.suffix.count == 4)
    }

    @Test func rawInitRequires32Bytes() {
        #expect(Fingerprint(bytes: Data(count: 32)) != nil)
        #expect(Fingerprint(bytes: Data(count: 31)) == nil)
    }

    @Test func codableRejectsWrongLength() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Fingerprint.self, from: JSONEncoder().encode(Data(count: 8)))
        }
    }
}

struct DeviceNameTests {
    @Test func stripsControlAndBidiCharacters() {
        #expect(DeviceName.sanitize("iPad\u{202E}dap\u{0007}", fallback: "iPad") == "iPaddap")
    }

    @Test func truncatesTo32Characters() {
        #expect(DeviceName.sanitize(String(repeating: "x", count: 50), fallback: "iPad").count == TransportLimits.displayNameMaxCharacters)
    }

    @Test func emptyAfterCleaningFallsBack() {
        #expect(DeviceName.sanitize("\u{0000}\u{200F}  ", fallback: "iPad") == "iPad")
    }

    @Test func normalizesToNFC() {
        #expect(DeviceName.sanitize("Cafe\u{0301}", fallback: "x") == "Caf\u{00E9}")
    }
}

struct QRPairingPayloadTests {
    private func sample(name: String = "Azathoth-1A2B") -> QRPairingPayload {
        QRPairingPayload(sessionID: Data(repeating: 1, count: 16),
                         macFingerprint: Fingerprint(bytes: Data(repeating: 2, count: 32))!,
                         secret: Data(repeating: 3, count: 32), instanceName: name)!
    }

    @Test func roundTrips() throws {
        let p = sample()
        let text = p.encoded()
        #expect(text.hasPrefix("YSE1:"))
        #expect(try QRPairingPayload.decode(text).get() == p)
    }

    @Test func randomRoundTrips200() throws {
        for _ in 0..<200 {
            let name = String((0..<Int.random(in: 1...63)).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789-".randomElement()! })
            let p = QRPairingPayload(sessionID: Data((0..<16).map { _ in UInt8.random(in: 0...255) }),
                                     macFingerprint: Fingerprint(bytes: Data((0..<32).map { _ in UInt8.random(in: 0...255) }))!,
                                     secret: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), instanceName: name)!
            #expect(try QRPairingPayload.decode(p.encoded()).get() == p)
        }
    }

    @Test func rejectsMalformed() {
        let good = sample().encoded()
        let body = String(good.dropFirst(5))
        for bad in ["", "YSE2:" + body, "yse1:" + body, good + "=", good + "!", "YSE1:" + body.dropLast(4),
                    "YSE1:" + body + "AAAA", "https://example.com"] {
            #expect((try? QRPairingPayload.decode(bad).get()) == nil, "\(bad.prefix(12))")
        }
    }

    @Test func rejectsWrongVersionByteAndBadName() {
        var bytes = [UInt8](Data(base64URL: String(sample().encoded().dropFirst(5)))!)
        bytes[0] = 2
        #expect((try? QRPairingPayload.decode("YSE1:" + Data(bytes).base64URLEncoded()).get()) == nil)
        #expect(QRPairingPayload(sessionID: Data(count: 16), macFingerprint: Fingerprint(bytes: Data(count: 32))!,
                                 secret: Data(count: 32), instanceName: "") == nil)
        #expect(QRPairingPayload(sessionID: Data(count: 16), macFingerprint: Fingerprint(bytes: Data(count: 32))!,
                                 secret: Data(count: 32), instanceName: "a\u{0007}b") == nil)
        #expect(QRPairingPayload(sessionID: Data(count: 16), macFingerprint: Fingerprint(bytes: Data(count: 32))!,
                                 secret: Data(count: 32), instanceName: String(repeating: "a", count: 64)) == nil)
    }

    @Test func descriptionDoesNotRevealSecret() {
        let p = sample()
        let text = String(describing: p) + String(reflecting: p)
        #expect(!text.contains(p.secret.base64EncodedString()))
        #expect(!text.contains(p.encoded()))
        #expect(!text.contains("030303"))
    }
}

struct PairingProofTests {
    private let secret = Data(repeating: 9, count: 32)
    private let sid = Data(repeating: 1, count: 16)
    private let fpM = Fingerprint(bytes: Data(repeating: 2, count: 32))!
    private let fpI = Fingerprint(bytes: Data(repeating: 3, count: 32))!
    private let exporter = Data(repeating: 4, count: 32)

    private func proof(secret: Data? = nil, sid: Data? = nil, fpM: Fingerprint? = nil, fpI: Fingerprint? = nil, exporter: Data? = nil) -> Data {
        PairingProof.compute(secret: secret ?? self.secret, sessionID: sid ?? self.sid, macFingerprint: fpM ?? self.fpM,
                             ipadFingerprint: fpI ?? self.fpI, exporter: exporter ?? self.exporter)
    }

    @Test func matchesSpecifiedHMAC() {
        var message = Data("yse-pair-v1".utf8)
        message.append(1)
        message.append(sid); message.append(fpM.bytes); message.append(fpI.bytes); message.append(exporter)
        let expected = Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        #expect(proof() == expected)
        #expect(proof().count == 32)
    }

    @Test func verifiesOnlyExactBinding() {
        let p = proof()
        #expect(PairingProof.verify(p, secret: secret, sessionID: sid, macFingerprint: fpM, ipadFingerprint: fpI, exporter: exporter))
        let other = Fingerprint(bytes: Data(repeating: 5, count: 32))!
        #expect(!PairingProof.verify(p, secret: Data(repeating: 8, count: 32), sessionID: sid, macFingerprint: fpM, ipadFingerprint: fpI, exporter: exporter))
        #expect(!PairingProof.verify(p, secret: secret, sessionID: Data(repeating: 6, count: 16), macFingerprint: fpM, ipadFingerprint: fpI, exporter: exporter))
        #expect(!PairingProof.verify(p, secret: secret, sessionID: sid, macFingerprint: other, ipadFingerprint: fpI, exporter: exporter))
        #expect(!PairingProof.verify(p, secret: secret, sessionID: sid, macFingerprint: fpM, ipadFingerprint: other, exporter: exporter))
        #expect(!PairingProof.verify(p, secret: secret, sessionID: sid, macFingerprint: fpM, ipadFingerprint: fpI, exporter: Data(repeating: 7, count: 32)))
        #expect(!PairingProof.verify(Data(p.dropLast()), secret: secret, sessionID: sid, macFingerprint: fpM, ipadFingerprint: fpI, exporter: exporter))
    }
}

struct ReplayGuardTests {
    private let nonce = Data(repeating: 4, count: 16)

    /// 依序送出，回傳每一步的結果（#expect 內不能呼叫 mutating）
    private func run(_ steps: [(Data?, UInt64?)]) -> [ErrorCode?] {
        var guardian = ReplayGuard(nonce: nonce)
        return steps.map { guardian.accept(nonce: $0.0, seq: $0.1) }
    }

    @Test func acceptsStrictlyIncreasingFromOne() {
        #expect(run([(nonce, 1), (nonce, 2), (nonce, 10)]) == [nil, nil, nil])
    }

    @Test func rejectsReplayAndNonIncreasing() {
        let results = run([(nonce, 0), (nonce, 3), (nonce, 3), (nonce, 2), (nonce, 4)])
        #expect(results == [.replayed, nil, .replayed, .replayed, nil])
    }

    @Test func rejectsWrongOrMissingNonceAndMissingSeq() {
        let results = run([(Data(repeating: 5, count: 16), 1), (nil, 1), (nonce, nil), (nonce, 1)])
        // 被拒的不推進序號：最後的 seq 1 仍可受理
        #expect(results == [.replayed, .replayed, .invalidRequest, nil])
    }
}

struct RateLimiterTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func takes(_ bucket: inout TokenBucket, at offsets: [TimeInterval]) -> [Bool] {
        offsets.map { bucket.take(now: t0.addingTimeInterval($0)) }
    }

    @Test func bucketAllowsCapacityThenRefills() {
        var bucket = TokenBucket(capacity: 3, refillPerSecond: 3, now: t0)
        #expect(takes(&bucket, at: [0, 0, 0, 0, 0.34, 0.34]) == [true, true, true, false, true, false])
    }

    @Test func bucketDoesNotOverfill() {
        var bucket = TokenBucket(capacity: 2, refillPerSecond: 2, now: t0)
        #expect(takes(&bucket, at: [100, 100, 100]) == [true, true, false])
    }

    @Test func keyedLimiterSeparatesKeys() {
        var limiter = KeyedRateLimiter<String>(capacity: 1, refillPerSecond: 1)
        let results = [limiter.take("a", now: t0), limiter.take("a", now: t0), limiter.take("b", now: t0)]
        #expect(results == [true, false, true])
    }

    @Test func clockGoingBackwardsDoesNotMintTokens() {
        var bucket = TokenBucket(capacity: 1, refillPerSecond: 1, now: t0)
        #expect(takes(&bucket, at: [0, -50]) == [true, false])
    }
}

struct ReconnectBackoffTests {
    @Test func doublesFromOneAndCapsAt30() {
        let delays = (1...8).map { ReconnectBackoff.delay(attempt: $0, jitter: 1) }
        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30])
    }

    @Test func jitterIsClampedTo20Percent() {
        #expect(ReconnectBackoff.delay(attempt: 3, jitter: 0.5) == 4 * 0.8)
        #expect(ReconnectBackoff.delay(attempt: 3, jitter: 2) == 4 * 1.2)
        #expect(ReconnectBackoff.delay(attempt: 0, jitter: 1) == 1)
    }
}
