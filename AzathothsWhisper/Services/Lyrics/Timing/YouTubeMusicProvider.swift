import Foundation

/// YouTube Music（InnerTube 非公開介面，C 段計劃 §3.7）：免登入。
/// WEB_REMIX 搜尋歌曲 → `next` 找 `MPLY…` 歌詞分頁 → ANDROID_MUSIC `browse` 的 `timedLyricsData[].cueRange`。
/// 客戶端版本號是常數：失效時跟著 ytmusicapi 更新（2026-10-19 探針實測可用）
struct YouTubeMusicProvider: TimedLyricsProvider {
    static let endpoint = "https://music.youtube.com/youtubei/v1/"
    static var webClient: [String: Any] { ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "en", "gl": "US"] }
    static let androidVersion = "7.21.50"
    static var androidClient: [String: Any] { ["clientName": "ANDROID_MUSIC", "clientVersion": androidVersion, "androidSdkVersion": 30, "hl": "en", "gl": "US"] }
    static let androidUserAgent = "com.google.android.apps.youtube.music/\(androidVersion) (Linux; U; Android 11) gzip"
    /// 搜尋只看「歌曲」分類
    static let songsFilter = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="

    let gate: SourceGate
    var source: StoredTimingSource { .youtubeMusic }

    func candidates(for query: TimingQuery) async throws(ProviderFailure) -> [TimingCandidate] {
        let search = try await post("search", client: Self.webClient, ["query": "\(query.artist) \(query.title)", "params": Self.songsFilter], cacheable: true)
        return Self.candidates(search)
    }

    func timing(of picked: TimingCandidate, for query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        let next = try await post("next", client: Self.webClient, ["videoId": picked.id, "isAudioOnly": true], cacheable: true)
        guard let browseID = TimingJSON.values(forKey: "browseId", in: next).compactMap({ $0 as? String }).first(where: { $0.hasPrefix("MPLY") })
        else { return .noTiming(.notFound) }
        let lyrics = try await post("browse", client: Self.androidClient, ["browseId": browseID], userAgent: Self.androidUserAgent)
        let entries = TimingJSON.values(forKey: "timedLyricsData", in: lyrics).first as? [[String: Any]] ?? []
        let timed = entries.compactMap(Self.line)
        guard !timed.isEmpty else { return .noTiming(entries.isEmpty ? .notFound : .plainOnly) }
        return .validatedTiming(timed, matched: picked.track, duration: query.duration)
    }

    private func post(
        _ method: String, client: [String: Any], _ fields: [String: Any], userAgent: String? = nil, cacheable: Bool = false
    ) async throws(ProviderFailure) -> Any {
        var body = fields
        body["context"] = ["client": client]
        guard let url = URL(string: Self.endpoint + method + "?prettyPrint=false") else { throw .unparsable }
        var headers = ["Content-Type": "application/json", "Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/"]
        if let userAgent { headers["User-Agent"] = userAgent }
        let response = try await gate.send(.timingPOST(url, body: try TimingJSON.data(body), headers: headers), cacheable: cacheable)
        return try TimingJSON.object(response.okBody())
    }

    /// 搜尋結果前幾筆：第一欄＝曲名；第二欄＝歌手 • 專輯 • 長度（可能有「Song」標籤）
    static func candidates(_ search: Any) -> [TimingCandidate] {
        let items = TimingJSON.values(forKey: "musicResponsiveListItemRenderer", in: search).compactMap { $0 as? [String: Any] }
        return items.compactMap { item -> TimingCandidate? in
            let columns = (item["flexColumns"] as? [Any] ?? []).map(runTexts)
            guard columns.count >= 2,
                  let videoID = TimingJSON.values(forKey: "videoId", in: item["playlistItemData"] ?? item).first as? String
            else { return nil }
            let details = columns[1].filter { !["", "•"].contains($0.trimmingCharacters(in: .whitespaces)) }
            let artist = details.first.flatMap { ["Song", "Video"].contains($0) ? details.dropFirst().first : $0 } ?? ""
            let track = MatchedTrack(artist: artist, title: columns[0].joined(), duration: details.lazy.compactMap(seconds).first)
            return TimingCandidate(track: track, id: videoID)
        }
    }

    /// `3:21`、`1:02:03`
    static func seconds(_ text: String) -> Double? {
        // 只認 ASCII 數字：`isNumber` 對全形「５」、上標「²」也成立，但 Double() 讀不了（安全評審 HIGH-2）
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    private static func runTexts(_ column: Any) -> [String] {
        let runs = TimingJSON.values(forKey: "runs", in: column).first as? [[String: Any]] ?? []
        return runs.compactMap { $0["text"] as? String }
    }

    private static func line(_ entry: [String: Any]) -> LRCLine? {
        guard let cue = entry["cueRange"] as? [String: Any], let start = TimingJSON.double(cue["startTimeMilliseconds"]) else { return nil }
        return LRCLine(start: start / 1000, text: TimingJSON.string(entry["lyricLine"]) ?? "")
    }
}
