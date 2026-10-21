import Foundation

/// 配對成功的候選有多接近查詢（候選排序計劃 §3.2）：越小越好。只由 `TrackMatcher.quality` 產生，配對與排序共用同一份規則
struct MatchQuality: Comparable, Sendable {
    /// 歌手與曲名 folding 後、空白收斂後字串相等
    let isExact: Bool
    /// 曲名正規化後的編輯距離（配對成功者只會是 0 或 1）
    let titleDistance: Int
    /// min(整串歌手, 拆開後最接近的一位) 正規化後的編輯距離
    let artistDistance: Int
    let durationGap: Double

    static func < (lhs: MatchQuality, rhs: MatchQuality) -> Bool {
        (lhs.isExact ? 0 : 1, lhs.titleDistance, lhs.artistDistance, lhs.durationGap)
            < (rhs.isExact ? 0 : 1, rhs.titleDistance, rhs.artistDistance, rhs.durationGap)
    }
}

extension TimingCandidate {
    /// 每個來源最多逐筆取幾名的時間軸
    static let rankedLimit = 3

    /// 依原始順序以 id 去重、取前 `limit` 個，只留配對成功者，依 `MatchQuality` 排序（同分照來源原始順序），取前 `rankedLimit`
    static func ranked(_ candidates: [TimingCandidate], for query: TimingQuery) -> [TimingCandidate] {
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.id).inserted }.prefix(limit)
        return unique.enumerated()
            .compactMap { index, candidate in TrackMatcher.quality(query, candidate.track).map { (quality: $0, index: index, candidate: candidate) } }
            .sorted { ($0.quality, $0.index) < ($1.quality, $1.index) }
            .prefix(rankedLimit)
            .map(\.candidate)
    }
}

/// 對齊通過的一名候選（`rank`＝`TimingCandidate.ranked` 的名次，0 起算）
struct RankedAlignment: Equatable, Sendable {
    let rank: Int
    let alignment: LRCAligner.Alignment

    /// Music 側與 LRC 側都全部對上：後面的候選最多打平、再以名次輸，不必再取
    var isPerfect: Bool { alignment.musicRate == 1 && alignment.lrcCoverage == 1 }

    /// musicRate 高者 → lrcCoverage 高者 → 名次前者（直接錨點數＝musicRate×行數，與第一鍵等價，不另比）
    static func best(of accepted: [RankedAlignment]) -> RankedAlignment? {
        accepted.min { lhs, rhs in
            (-lhs.alignment.musicRate, -lhs.alignment.lrcCoverage, lhs.rank) < (-rhs.alignment.musicRate, -rhs.alignment.lrcCoverage, rhs.rank)
        }
    }
}
