import Foundation

/// LRCLIB（https://lrclib.net/docs，C 段計劃 §3.7）：先 `/api/get` 精確查、404 才 `/api/search`；
/// 帶 syncedLyrics 且通過 `TrackMatcher` 的候選**唯一**才採用（母計劃 §2.4 R1-4；不送 album，不再用它消歧）
struct LRCLIBProvider: TimedLyricsProvider {
    static let base = URL(string: "https://lrclib.net/api/")!
    /// 文件要求：app 名、版本、首頁網址
    static var userAgent: String { "AzathothsWhisper/\(AppInfo.version) (\(AppInfo.repositoryURL.absoluteString))" }
    /// 文件：序列送出、間隔 200–500 ms（取上限）
    static let minimumInterval: TimeInterval = 0.5

    let gate: SourceGate
    var source: StoredTimingSource { .lrclib }

    func lookup(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        let headers = ["User-Agent": Self.userAgent]
        let exact = try await gate.send(.timingGET(Self.base.appendingPathComponent("get"), query: [
            "artist_name": query.artist, "track_name": query.title, "duration": String(Int(query.duration.rounded())),
        ], headers: headers), cacheable: true)
        let records: [[String: Any]]
        if exact.statusCode == 404 {
            let search = try await gate.send(.timingGET(Self.base.appendingPathComponent("search"), query: [
                "artist_name": query.artist, "track_name": query.title,
            ], headers: headers), cacheable: true)
            records = try TimingJSON.array(search.okBody())
        } else {
            records = [try TimingJSON.dictionary(exact.okBody())]
        }
        return Self.outcome(records, for: query)
    }

    static func outcome(_ records: [[String: Any]], for query: TimingQuery) -> ProviderOutcome {
        let considered = records.prefix(TimingCandidate.limit)
        let matching = considered.filter { TrackMatcher.matches(query, track(of: $0)) }
        guard !matching.isEmpty else { return .noTiming(.miss(among: considered.count)) }
        let synced = matching.filter { !(($0["syncedLyrics"] as? String) ?? "").isEmpty }
        guard synced.count == 1, let only = synced.first, let text = only["syncedLyrics"] as? String else {
            return .noTiming(synced.isEmpty ? .plainOnly : .mismatch)
        }
        return .fromLRCText(text, matched: track(of: only), duration: query.duration)
    }

    private static func track(of record: [String: Any]) -> MatchedTrack {
        MatchedTrack(
            artist: TimingJSON.string(record["artistName"]) ?? "", title: TimingJSON.string(record["trackName"]) ?? "",
            duration: TimingJSON.double(record["duration"])
        )
    }
}
