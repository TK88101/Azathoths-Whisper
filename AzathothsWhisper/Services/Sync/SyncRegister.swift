import Foundation

/// 跨機決勝用的版本（⑨ 計劃 §6.5）：每鍵一個 Lamport 計數＋第一次產生這個版本的機器。
/// `origin` 空字串＝本機改動、還沒蓋章；匯出與匯入前一律先蓋章（§6.3「既有資料補 origin」）
struct SyncVersion: Codable, Equatable, Hashable, Sendable {
    let revision: Int
    let origin: String

    var isStamped: Bool { !origin.isEmpty }

    /// 全序：revision 大者勝；同 revision 取 origin 字典序較小者——可交換、可結合、冪等，三台以上轉手也收斂（R1-1）
    func beats(_ other: SyncVersion) -> Bool {
        revision != other.revision ? revision > other.revision : origin < other.origin
    }
}

/// 最後寫入者勝的暫存器（決定與「沒有歌詞」標記共用的唯一定義，R2-B4）。`value == nil`＝已清除（墓碑）
struct SyncRegister<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let value: Value?
    let version: SyncVersion

    static func fresh(_ value: Value?) -> SyncRegister {
        SyncRegister(value: value, version: SyncVersion(revision: 1, origin: ""))
    }

    /// 本機改動：該鍵已見過的最大 revision＋1（本機暫存器在合併後恆為最大）
    func updated(to value: Value?) -> SyncRegister {
        SyncRegister(value: value, version: SyncVersion(revision: version.revision + 1, origin: ""))
    }

    func stamped(by writer: String) -> SyncRegister {
        version.isStamped ? self : SyncRegister(value: value, version: SyncVersion(revision: version.revision, origin: writer))
    }

    /// 同版本＝同一次改動，留左邊（本機）
    static func merged(_ lhs: SyncRegister, _ rhs: SyncRegister) -> SyncRegister {
        rhs.version.beats(lhs.version) ? rhs : lhs
    }

    static func merged(_ local: [String: SyncRegister], _ remote: [String: SyncRegister]) -> [String: SyncRegister] {
        local.merging(remote) { merged($0, $1) }
    }
}
