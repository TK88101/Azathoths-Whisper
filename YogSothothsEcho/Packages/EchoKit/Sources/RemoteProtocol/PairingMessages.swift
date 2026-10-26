import Foundation

// 配對與 session 的 body（sprint-2-detail.md §4.2）。`isValid` 只驗形狀；語意（proof 對不對）由 RemoteTransport 判定。
// Data 以 JSONEncoder 預設的 base64 編碼。

public struct PairProof: Codable, Sendable, Equatable {
    public let sessionID: Data
    public let proof: Data
    public let deviceName: String

    public init(sessionID: Data, proof: Data, deviceName: String) {
        self.sessionID = sessionID
        self.proof = proof
        self.deviceName = deviceName
    }

    public var isValid: Bool {
        sessionID.count == TransportLimits.sessionIDBytes && proof.count == TransportLimits.proofBytes
            && deviceName.utf8.count <= TransportLimits.deviceNameMaxBytes
    }
}

public struct PairPending: Codable, Sendable, Equatable {
    /// 對端（iPad）指紋末 2 bytes 的大寫十六進位；iPad 自算比對
    public let suffix: String

    public init(suffix: String) { self.suffix = suffix }

    public var isValid: Bool {
        suffix.count == 4 && suffix.unicodeScalars.allSatisfy { "0123456789ABCDEF".unicodeScalars.contains($0) }
    }
}

public enum PairOutcome: String, Codable, Sendable, CaseIterable {
    case approved, rejected, expired, cancelled
}

public struct PairResult: Codable, Sendable, Equatable {
    public let outcome: PairOutcome
    public init(outcome: PairOutcome) { self.outcome = outcome }
}

public struct SessionHello: Codable, Sendable, Equatable {
    public let sessionNonce: Data
    public init(sessionNonce: Data) { self.sessionNonce = sessionNonce }
    public var isValid: Bool { sessionNonce.count == TransportLimits.nonceBytes }
}

public struct ErrorBody: Codable, Sendable, Equatable {
    public let code: ErrorCode
    public let retryable: Bool
    public init(code: ErrorCode, retryable: Bool) {
        self.code = code
        self.retryable = retryable
    }
}
