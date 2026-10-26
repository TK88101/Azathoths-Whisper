import CryptoKit
import Foundation

/// proof = HMAC-SHA256(S, "yse-pair-v1" ‖ 0x01 ‖ sessionID ‖ fpM ‖ fpI ‖ exporter)（設計 §4.2-4、sprint-2-detail.md §4.5）。
/// fpI 由 Mac 取自 verify 看到的對端 leaf，不信 iPad 自報。
public enum PairingProof {
    static let domain = Data("yse-pair-v1".utf8)
    static let version: UInt8 = 1

    static func message(sessionID: Data, macFingerprint: Fingerprint, ipadFingerprint: Fingerprint, exporter: Data) -> Data {
        var data = domain
        data.append(version)
        data.append(sessionID)
        data.append(macFingerprint.bytes)
        data.append(ipadFingerprint.bytes)
        data.append(exporter)
        return data
    }

    public static func compute(secret: Data, sessionID: Data, macFingerprint: Fingerprint,
                               ipadFingerprint: Fingerprint, exporter: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(
            for: message(sessionID: sessionID, macFingerprint: macFingerprint, ipadFingerprint: ipadFingerprint, exporter: exporter),
            using: SymmetricKey(data: secret))
        return Data(mac)
    }

    /// 常數時間比對（CryptoKit）
    public static func verify(_ proof: Data, secret: Data, sessionID: Data, macFingerprint: Fingerprint,
                              ipadFingerprint: Fingerprint, exporter: Data) -> Bool {
        guard proof.count == SHA256.byteCount else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: message(sessionID: sessionID, macFingerprint: macFingerprint, ipadFingerprint: ipadFingerprint,
                                    exporter: exporter),
            using: SymmetricKey(data: secret))
    }
}
