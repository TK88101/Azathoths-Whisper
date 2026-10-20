import Foundation
import SwiftSoup

/// QQ 音樂（非公開介面，C 段計劃 §3.7）：`musicu.fcg` 搜尋 → `fcg_query_lyric_new` 取 LRC。
/// 歌詞端點可能回 JSONP（`MusicJsonCallback(...)`），文字可能帶 HTML 實體（`&#39;`）
struct QQMusicProvider: TimedLyricsProvider {
    static let searchURL = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!
    static let lyricURL = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
    static let referer = "https://y.qq.com/"

    let gate: SourceGate
    var source: StoredTimingSource { .qq }

    func lookup(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        let request: [String: Any] = ["req_1": [
            "method": "DoSearchForQQMusicDesktop", "module": "music.search.SearchCgiService",
            "param": ["num_per_page": TimingCandidate.limit, "page_num": 1, "query": "\(query.artist) \(query.title)", "search_type": 0],
        ]]
        let search = try await gate.send(.timingPOST(
            Self.searchURL, body: try TimingJSON.data(request), headers: ["Content-Type": "application/json", "Referer": Self.referer]
        ), cacheable: true)
        let candidates = try Self.candidates(search.okBody())
        guard let picked = TimingCandidate.pick(candidates, for: query) else { return .noTiming(.miss(among: candidates.count)) }
        let response = try await gate.send(.timingGET(
            Self.lyricURL, query: ["songmid": picked.id, "format": "json", "nobase64": "1", "g_tk": "5381"], headers: ["Referer": Self.referer]
        ))
        return .fromLRCText(try Self.lyric(response.okBody()), matched: picked.track, duration: query.duration)
    }

    static func candidates(_ body: String) throws(ProviderFailure) -> [TimingCandidate] {
        guard let request = try TimingJSON.dictionary(body)["req_1"] as? [String: Any] else { throw .unparsable }
        let list = TimingJSON.values(forKey: "list", in: request).first as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let mid = item["mid"] as? String else { return nil }
            let singers = (item["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let title = item["name"] as? String ?? item["title"] as? String ?? ""
            return TimingCandidate(
                track: MatchedTrack(artist: singers.joined(separator: ", "), title: title, duration: TimingJSON.double(item["interval"])), id: mid
            )
        }
    }

    /// 剝掉 JSONP 外殼、解 HTML 實體
    static func lyric(_ body: String) throws(ProviderFailure) -> String {
        var json = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = json.firstIndex(of: "("), json.hasSuffix(")"), !json.hasPrefix("{") {
            json = String(json[json.index(after: open)..<json.index(before: json.endIndex)])
        }
        let raw = try TimingJSON.dictionary(json)["lyric"] as? String ?? ""
        return (try? Entities.unescape(raw)) ?? raw
    }
}
