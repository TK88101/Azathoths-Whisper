import Foundation

/// 網易雲（明文端點，C 段計劃 §3.7；2026-10-19 探針通過才納入）：`cloudsearch/pc`（form POST）→ `song/lyric` 的 `lrc.lyric`。
/// 失效時不改走加密介面（weapi／eapi，另案）
struct NetEaseProvider: TimedLyricsProvider {
    static let searchURL = URL(string: "https://music.163.com/api/cloudsearch/pc")!
    static let lyricURL = URL(string: "https://music.163.com/api/song/lyric")!
    static let referer = "https://music.163.com/"

    let gate: SourceGate
    var source: StoredTimingSource { .netease }

    func lookup(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        let form = ["s": "\(query.artist) \(query.title)", "type": "1", "limit": String(TimingCandidate.limit)]
        let search = try await gate.send(.timingPOST(
            Self.searchURL, body: Data(URLSessionHTTPClient.encodeForm(form).utf8),
            headers: ["Content-Type": "application/x-www-form-urlencoded", "Referer": Self.referer]
        ), cacheable: true)
        let candidates = try Self.candidates(search.okBody())
        guard let picked = TimingCandidate.pick(candidates, for: query) else { return .noTiming(.miss(among: candidates.count)) }
        let response = try await gate.send(.timingGET(
            Self.lyricURL, query: ["id": picked.id, "lv": "-1", "kv": "-1", "tv": "-1"], headers: ["Referer": Self.referer]
        ))
        let text = (try TimingJSON.dictionary(response.okBody())["lrc"] as? [String: Any])?["lyric"] as? String ?? ""
        return .fromLRCText(text, matched: picked.track, duration: query.duration)
    }

    static func candidates(_ body: String) throws(ProviderFailure) -> [TimingCandidate] {
        let root = try TimingJSON.dictionary(body)
        guard TimingJSON.double(root["code"]) == 200 else { throw .unparsable }
        let songs = (root["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []
        return songs.compactMap { song in
            guard let id = TimingJSON.string(song["id"]) else { return nil }
            let artists = (song["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let duration = TimingJSON.double(song["dt"]).map { $0 / 1000 }
            return TimingCandidate(track: MatchedTrack(artist: artists.joined(separator: ", "), title: song["name"] as? String ?? "", duration: duration), id: id)
        }
    }
}
