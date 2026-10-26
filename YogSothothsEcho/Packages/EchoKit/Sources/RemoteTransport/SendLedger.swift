import Foundation

/// 待送位元組帳本（CR-012；sprint-3-detail.md §4.5「待送位元組記帳」）：回應編碼後、送出前以實際位元組
/// 同時向「該連線」與「全域」原子預留，取得一次性 token；完成回呼以 token 釋放。釋放是冪等的，
/// 連線關閉或被取代時 `releaseAll` 一次清掉，之後晚到的完成回呼不會重複扣回。任何時刻兩個上限都成立、計數不為負。
struct SendLedger: Sendable {
    struct Token: Hashable, Sendable {
        let connection: ConnectionID
        let serial: UInt64
    }

    let perConnectionLimit: Int
    let totalLimit: Int
    private var reservations: [Token: Int] = [:]
    private var perConnection: [ConnectionID: Int] = [:]
    private var serial: UInt64 = 0
    private(set) var total = 0

    init(perConnectionLimit: Int, totalLimit: Int) {
        self.perConnectionLimit = perConnectionLimit
        self.totalLimit = totalLimit
    }

    func pending(for connection: ConnectionID) -> Int { perConnection[connection] ?? 0 }

    mutating func reserve(_ bytes: Int, for connection: ConnectionID) -> Token? {
        guard bytes > 0, pending(for: connection) + bytes <= perConnectionLimit, total + bytes <= totalLimit else { return nil }
        serial += 1
        let token = Token(connection: connection, serial: serial)
        reservations[token] = bytes
        perConnection[connection] = pending(for: connection) + bytes
        total += bytes
        return token
    }

    mutating func release(_ token: Token) {
        guard let bytes = reservations.removeValue(forKey: token) else { return }
        let left = pending(for: token.connection) - bytes
        perConnection[token.connection] = left > 0 ? left : nil
        total -= bytes
    }

    mutating func releaseAll(for connection: ConnectionID) {
        for token in reservations.keys where token.connection == connection { release(token) }
    }
}
