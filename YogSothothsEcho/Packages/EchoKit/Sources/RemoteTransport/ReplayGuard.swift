import Foundation
import RemoteProtocol

/// 應用層防重放（設計 §4.2-7）：每條正常連線一個，連線取消即丟棄
public struct ReplayGuard: Sendable {
    private let nonce: Data
    private var lastSeq: UInt64 = 0

    public init(nonce: Data) { self.nonce = nonce }

    /// 合格回 nil 並推進序號；被拒時序號不動。nonce 缺或不符＝replayed、seq 缺＝invalidRequest、seq ≤ 上一個＝replayed
    public mutating func accept(nonce received: Data?, seq: UInt64?) -> ErrorCode? {
        guard let received, received == nonce else { return .replayed }
        guard let seq else { return .invalidRequest }
        guard seq > lastSeq else { return .replayed }
        lastSeq = seq
        return nil
    }
}
