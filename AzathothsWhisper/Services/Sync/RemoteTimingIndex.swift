import CryptoKit
import Foundation

/// 他機時間軸的記憶體索引（⑨ 計劃 §6.5「時間軸，跨 persistentID」）：每台他機一份、整份換；鍵＝歌詞雜湊。
/// 只用來在本機查無可用記錄時、打外部來源之前找「同一首」；採用條件見 `pick`
actor RemoteTimingIndex {
    private var byWriter: [String: [LyricsFingerprint: [TimingRecord]]] = [:]

    func replace(writer: String, records: [TimingRecord]) {
        byWriter[writer] = Dictionary(grouping: records.filter(\.isFound), by: \.lyricsHash)
    }

    func candidates(for hash: LyricsFingerprint) -> [TimingRecord] {
        byWriter.keys.sorted().flatMap { byWriter[$0]?[hash] ?? [] }
    }

    /// 跨 ID 曲長容差：同一個檔在兩台應相同（/thecure：比外部來源的 3 s 嚴得多）
    static let durationTolerance: TimeInterval = 0.5

    /// 採用條件（§12-1）：found、歌詞雜湊相同、歌手與曲名 `exactKey` 完全相同（不容一字差、不忽略 remaster，R2）、
    /// 曲長差 ≤ 0.5 s、對齊器版本不低於現行、錨點套得上；依 `sourceRef` 去重（同一來源多版本依全序選代表，R3-4）後
    /// 恰一個、或多個但錨點完全相同（取 sourceRef 小者）才採用
    static func pick(_ candidates: [TimingRecord], for query: TimingQuery, lyricsHash: LyricsFingerprint, lineCount: Int) -> TimingRecord? {
        let eligible = candidates.filter { record in
            guard case .found(_, let lines) = record.outcome, record.lyricsHash == lyricsHash,
                  let match = record.match, let sourceRef = record.sourceRef, !sourceRef.isEmpty,
                  record.alignerRevision >= LRCAligner.revision,
                  TrackMatcher.exactKey(match.artist) == TrackMatcher.exactKey(query.artist),
                  TrackMatcher.exactKey(match.title) == TrackMatcher.exactKey(query.title),
                  abs(match.duration - query.duration) <= durationTolerance,
                  LRCAligner.storedLinesFit(lines, lineCount: lineCount)
            else { return false }
            return true
        }
        let representatives = Dictionary(grouping: eligible) { $0.sourceRef ?? "" }
            .compactMap { _, versions in versions.min(by: precedes) }
            .sorted { ($0.sourceRef ?? "") < ($1.sourceRef ?? "") }
        guard let first = representatives.first else { return nil }
        return representatives.allSatisfy({ anchors(of: $0) == anchors(of: first) }) ? first : nil
    }

    /// 同一 sourceRef 的版本全序：alignerRevision 大者優先 → 錨點正規化 JSON 的 SHA-256 小者
    private static func precedes(_ lhs: TimingRecord, _ rhs: TimingRecord) -> Bool {
        if lhs.alignerRevision != rhs.alignerRevision { return lhs.alignerRevision > rhs.alignerRevision }
        return anchorDigest(lhs) < anchorDigest(rhs)
    }

    private static func anchors(of record: TimingRecord) -> [TimingRecord.LineStart] {
        if case .found(_, let lines) = record.outcome { return lines }
        return []
    }

    private static func anchorDigest(_ record: TimingRecord) -> String {
        SHA256.hash(data: (try? SyncCodec.canonicalData(anchors(of: record))) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}
