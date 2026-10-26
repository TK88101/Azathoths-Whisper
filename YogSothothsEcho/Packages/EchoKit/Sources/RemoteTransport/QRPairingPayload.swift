import Foundation
import RemoteProtocol

/// Mac 顯示、iPad 掃描的一次性配對載荷（CR-010 ②(a)、sprint-2-detail.md §4.5）。
/// 文字＝"YSE1:" + base64url(version ‖ sessionID ‖ fpM ‖ S ‖ nameLen ‖ instanceName)，不含 IP／URL。
/// `secret` 是一次性秘密：description／reflection 一律遮蔽，不得寫進日誌。
public struct QRPairingPayload: Equatable, Sendable {
    public static let prefix = "YSE1:"
    static let version: UInt8 = 1
    static let secretBytes = 32
    static let maxNameBytes = 63
    /// version(1) + sessionID(16) + fpM(32) + S(32) + nameLen(1)
    static let fixedBytes = 1 + TransportLimits.sessionIDBytes + Fingerprint.byteCount + secretBytes + 1

    public enum DecodeError: Error, Sendable {
        case malformed
    }

    public let sessionID: Data
    public let macFingerprint: Fingerprint
    public let secret: Data
    public let instanceName: String

    public init?(sessionID: Data, macFingerprint: Fingerprint, secret: Data, instanceName: String) {
        guard sessionID.count == TransportLimits.sessionIDBytes, secret.count == Self.secretBytes,
              Self.isValidInstanceName(instanceName) else { return nil }
        self.sessionID = sessionID
        self.macFingerprint = macFingerprint
        self.secret = secret
        self.instanceName = instanceName
    }

    static func isValidInstanceName(_ name: String) -> Bool {
        let count = name.utf8.count
        guard count >= 1, count <= maxNameBytes else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: false
            default: true
            }
        }
    }

    public func encoded() -> String {
        var bytes = Data([Self.version])
        bytes.append(sessionID)
        bytes.append(macFingerprint.bytes)
        bytes.append(secret)
        let name = Data(instanceName.utf8)
        bytes.append(UInt8(name.count))
        bytes.append(name)
        return Self.prefix + bytes.base64URLEncoded()
    }

    /// 嚴格解碼：任一處不符即拒，不嘗試修復
    public static func decode(_ text: String) -> Result<QRPairingPayload, DecodeError> {
        guard text.hasPrefix(prefix), let bytes = Data(base64URL: String(text.dropFirst(prefix.count))),
              bytes.count > fixedBytes else { return .failure(.malformed) }
        let raw = [UInt8](bytes)
        let nameLength = Int(raw[fixedBytes - 1])
        guard raw[0] == version, raw.count == fixedBytes + nameLength else { return .failure(.malformed) }
        var offset = 1
        func take(_ n: Int) -> Data {
            defer { offset += n }
            return Data(raw[offset..<(offset + n)])
        }
        let sessionID = take(TransportLimits.sessionIDBytes)
        guard let fingerprint = Fingerprint(bytes: take(Fingerprint.byteCount)) else { return .failure(.malformed) }
        let secret = take(secretBytes)
        offset += 1
        guard let name = String(bytes: raw[offset...], encoding: .utf8),
              let payload = QRPairingPayload(sessionID: sessionID, macFingerprint: fingerprint, secret: secret,
                                             instanceName: name) else { return .failure(.malformed) }
        return .success(payload)
    }
}

extension QRPairingPayload: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "QRPairingPayload(instance: \(instanceName), mac: …\(macFingerprint.suffix), secret: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["instanceName": instanceName], displayStyle: .struct) }
}
