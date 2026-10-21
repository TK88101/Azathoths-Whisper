import Foundation

/// LRCLIB（https://lrclib.net/docs，C 段計劃 §3.7）：先 `/api/get` 精確查；404 或該筆沒有 syncedLyrics 才 `/api/search`。
/// 帶 syncedLyrics 的紀錄全部是候選（候選排序計劃 §3.1 廢除「唯一」規則；排序在 resolver）；不送 album
struct LRCLIBProvider: TimedLyricsProvider {
    static let base = URL(string: "https://lrclib.net/api/")!
    /// 文件要求：app 名、版本、首頁網址
    static var userAgent: String { "AzathothsWhisper/\(AppInfo.version) (\(AppInfo.repositoryURL.absoluteString))" }
    /// 文件：序列送出、間隔 200–500 ms（取上限）
    static let minimumInterval: TimeInterval = 0.5

    let gate: SourceGate
    var source: StoredTimingSource { .lrclib }

    func candidates(for query: TimingQuery) async throws(ProviderFailure) -> [TimingCandidate] {
        let headers = ["User-Agent": Self.userAgent]
        let exact = try await gate.send(.timingGET(Self.base.appendingPathComponent("get"), query: [
            "artist_name": query.artist, "track_name": query.title, "duration": String(Int(query.duration.rounded())),
        ], headers: headers), cacheable: true)
        if exact.statusCode != 404 {
            let found = Self.candidates([try TimingJSON.dictionary(exact.okBody())])
            if !found.isEmpty { return found }
        }
        let search = try await gate.send(.timingGET(Self.base.appendingPathComponent("search"), query: [
            "artist_name": query.artist, "track_name": query.title,
        ], headers: headers), cacheable: true)
        return Self.candidates(try TimingJSON.array(search.okBody()))
    }

    func timing(of candidate: TimingCandidate, for query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        .fromLRCText(candidate.embeddedLRC ?? "", matched: candidate.track, duration: query.duration)
    }

    /// 只有帶 syncedLyrics 的紀錄（純文字的佔掉前幾名的名額沒有意義）；沒有 id 的以位置代替
    static func candidates(_ records: [[String: Any]]) -> [TimingCandidate] {
        records.enumerated().compactMap { index, record in
            guard let synced = record["syncedLyrics"] as? String, !synced.isEmpty else { return nil }
            return TimingCandidate(track: track(of: record), id: TimingJSON.string(record["id"]) ?? "#\(index)", embeddedLRC: synced)
        }
    }

    private static func track(of record: [String: Any]) -> MatchedTrack {
        MatchedTrack(
            artist: TimingJSON.string(record["artistName"]) ?? "", title: TimingJSON.string(record["trackName"]) ?? "",
            duration: TimingJSON.double(record["duration"])
        )
    }
}
