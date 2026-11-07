import Foundation

/// ⑪「時間軸不準」標記的鍵（計劃 §4.2）：同一首的歌詞改版後是另一筆，舊證據不被蓋掉
struct TimingFlagKey: Hashable, Sendable, Codable {
    let persistentID: String
    let lyricsHash: LyricsFingerprint
}

/// 畫面當時實際套用的時間軸（不可變快照）：外部來源＝resolver 交來的錨點；內嵌 LRC＝當時建出的各行起點。
/// 只有序號與秒數，不含歌詞文字
struct AppliedTiming: Equatable, Sendable, Codable {
    let source: TimingSource
    let anchors: [TimingRecord.LineStart]
}

/// 一筆標記（計劃 §4.2）。只記證據，不改任何既有行為
struct TimingFlag: Equatable, Sendable, Codable {
    /// 存檔與畫面的關係：不一致時 `stored` 為 nil，診斷工具據此明示
    enum Provenance: String, Equatable, Sendable, Codable {
        case matched, storeMissing, storeMismatch, embedded
    }

    /// 與畫面一致的那份存檔的身分（來源、對齊器版本、查找時間、跨機來源）
    struct StoredIdentity: Equatable, Sendable, Codable {
        let source: StoredTimingSource
        let alignerRevision: Int
        let fetchedAt: Date
        let sourceRef: String?
        let origin: String?
    }

    static let maxPositions = 10

    /// 位置存 0.1 s 粒度（存檔規格）
    static func quantized(_ seconds: Double) -> Double {
        (seconds * 10).rounded() / 10
    }

    let persistentID: String
    let lyricsHash: LyricsFingerprint
    let markedAt: Date
    /// 每次按下時的播放秒數（0.1 s），新的在後
    let positions: [Double]
    let applied: AppliedTiming
    let stored: StoredIdentity?
    let provenance: Provenance

    var key: TimingFlagKey { TimingFlagKey(persistentID: persistentID, lyricsHash: lyricsHash) }
}

/// VM 在任何 await 之前擷取的標記請求（世代守衛慣例）
struct TimingFlagRequest: Equatable, Sendable {
    let key: TimingFlagKey
    let position: Double?
    let applied: AppliedTiming
    let wantsFlagged: Bool
}

/// 存檔與畫面是否同一份（Codex R1-2：存檔失敗時畫面照樣套用外部時間軸）。
/// 同歌詞、同來源、錨點逐值相同才算 matched；否則不填存檔身分，免得把不相干的存檔當證據
enum TimingFlagProvenance {
    static func resolve(
        applied: AppliedTiming, lyricsHash: LyricsFingerprint, record: TimingRecord?
    ) -> (provenance: TimingFlag.Provenance, stored: TimingFlag.StoredIdentity?) {
        guard applied.source != .embeddedLRC else { return (.embedded, nil) }
        guard let record else { return (.storeMissing, nil) }
        guard record.lyricsHash == lyricsHash, case .found(let source, let lines) = record.outcome,
              source.timingSource == applied.source, lines == applied.anchors
        else { return (.storeMismatch, nil) }
        let stored = TimingFlag.StoredIdentity(
            source: source, alignerRevision: record.alignerRevision, fetchedAt: record.fetchedAt, sourceRef: record.sourceRef, origin: record.origin
        )
        return (.matched, stored)
    }
}

extension LyricsTimeline {
    /// 各行起點（序號＝顯示行序）：內嵌 LRC 的快照用
    var lineStarts: [TimingRecord.LineStart] {
        lines.enumerated().map { .init(index: $0.offset, start: $0.element.start) }
    }
}
