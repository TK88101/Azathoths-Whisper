import Foundation
import RemoteProtocol

/// detail 封面（原檔分塊，CR-018；sprint-5-detail.md §11）的傳輸生命週期。純值、時間由呼叫端傳入。
/// - 每 peer 最多 1 個、全域最多 2 個傳輸；傳輸自己持有原檔 `Data`（寫時複製），不受封面 LRU 逐出影響，記憶體上限 2 × 6 MiB
/// - 同 peer 以更新的 generation 開新傳輸＝取代舊的（換曲即釋放）；generation 不大於已接受者＝restart，不占名額
/// - 後續塊須符合 key、digest、generation 與序號；不符、逾時回收或已完成＝restart（逾時的傳輸已移除，遲到請求不會復活）
/// - 全部塊送出即釋放；閒置 30 s 回收；斷線清除該 peer 的傳輸與世代紀錄
struct DetailTransferBook {
    static let globalLimit = 2
    static let idleTimeout: TimeInterval = 30

    struct Key: Hashable, Sendable {
        let albumID: String
        let token: String
    }

    struct Payload: Sendable {
        let data: Data
        /// 完整 SHA-256（64 字小寫十六進位）
        let digest: String
        let mime: ArtworkMime
    }

    enum Begin: Equatable {
        case started(ArtworkDetailPart)
        /// 過舊的 generation：回 restart，不建立傳輸
        case restart
        /// 全域名額已滿（其他 peer 佔用）
        case busy

        var part: ArtworkDetailPart? {
            if case .started(let part) = self { return part }
            return nil
        }
    }

    private struct Transfer {
        let key: Key
        let generation: UInt64
        let payload: Payload
        let partCount: Int
        var served: Set<Int>
        var lastActivity: Date
    }

    private var transfers: [UUID: Transfer] = [:]
    private var acceptedGeneration: [UUID: UInt64] = [:]

    var activeCount: Int { transfers.count }

    func activeCount(now: Date) -> Int { transfers.values.filter { !Self.isIdle($0, now: now) }.count }

    mutating func begin(peer: UUID, key: Key, generation: UInt64, payload: Payload, now: Date) -> Begin {
        expire(now: now)
        if let accepted = acceptedGeneration[peer], generation <= accepted { return .restart }
        if transfers[peer] == nil, transfers.count >= Self.globalLimit { return .busy }
        acceptedGeneration[peer] = generation
        let partCount = DetailArtworkLimits.partCount(totalBytes: payload.data.count)
        transfers[peer] = Transfer(key: key, generation: generation, payload: payload, partCount: partCount, served: [],
                                   lastActivity: now)
        return serve(peer: peer, index: 0, now: now).map(Begin.started) ?? .restart
    }

    mutating func part(peer: UUID, key: Key, digest: String, generation: UInt64, index: Int, now: Date) -> ArtworkDetailPart? {
        expire(now: now)
        guard let transfer = transfers[peer], transfer.key == key, transfer.payload.digest == digest,
              transfer.generation == generation, (0..<transfer.partCount).contains(index) else { return nil }
        return serve(peer: peer, index: index, now: now)
    }

    /// 斷線：清掉傳輸與世代紀錄
    @discardableResult
    mutating func peerGone(_ peer: UUID) -> Bool {
        acceptedGeneration[peer] = nil
        return transfers.removeValue(forKey: peer) != nil
    }

    private mutating func serve(peer: UUID, index: Int, now: Date) -> ArtworkDetailPart? {
        guard var transfer = transfers[peer] else { return nil }
        let data = transfer.payload.data
        let start = data.startIndex + index * DetailArtworkLimits.chunkBytes
        let end = min(start + DetailArtworkLimits.chunkBytes, data.endIndex)
        let part = ArtworkDetailPart(part: index, partCount: transfer.partCount, totalBytes: data.count,
                                     digest: transfer.payload.digest, mime: transfer.payload.mime, chunk: data.subdata(in: start..<end))
        transfer.served.formUnion([index])   // echo_gate E2 禁 Bridge 內出現 .insert(
        transfer.lastActivity = now
        transfers[peer] = transfer.served.count == transfer.partCount ? nil : transfer
        return part
    }

    private mutating func expire(now: Date) {
        transfers = transfers.filter { !Self.isIdle($0.value, now: now) }
    }

    private static func isIdle(_ transfer: Transfer, now: Date) -> Bool {
        now.timeIntervalSince(transfer.lastActivity) > idleTimeout
    }
}
