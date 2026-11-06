import Foundation

/// 跨機決勝用的版本（⑨ 計劃 §6.5）：每鍵一個 Lamport 計數＋第一次產生這個版本的機器。
/// `origin` 空字串＝本機改動、還沒蓋章；匯出與匯入前一律先蓋章（§6.3「既有資料補 origin」）
struct SyncVersion: Codable, Equatable, Hashable, Sendable {
    let revision: Int
    let origin: String

    var isStamped: Bool { SyncWriterID.isStamped(origin) }

    /// revision 上限（安全評審 HIGH-1）：他機檔塞 `Int.max` 會讓本機下一次改動溢位崩潰。正常使用一輩子到不了。
    /// 遠端與本機收同一個範圍（安全複查 N1、codex R3：範圍不同會讓本機改動在重讀時消失、或同伴拒收而分歧）；
    /// 到上限後改動飽和、不再嚴格較新，同 revision 依 origin 決勝——只有偽造資料到得了，偽造者本來就能贏最後寫入者勝
    static let maxRevision = Int(Int32.max)

    /// 遠端與本機載入共用的合法性：origin 是 writerID 格式（或本機未蓋章的空字串，視 `allowUnstamped`）、revision 在範圍內
    func isAcceptable(allowUnstamped: Bool) -> Bool {
        (0...Self.maxRevision).contains(revision) && SyncWriterID.isAcceptableOrigin(origin, allowUnstamped: allowUnstamped)
    }

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
        // 飽和：到上限就停在上限（決勝仍正確，不會溢位）
        SyncRegister(value: value, version: SyncVersion(revision: min(version.revision, SyncVersion.maxRevision - 1) + 1, origin: ""))
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
