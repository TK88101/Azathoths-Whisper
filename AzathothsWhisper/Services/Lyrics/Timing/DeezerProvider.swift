import Foundation

/// Deezer（C 段計劃 §3.7）：公開搜尋 API（一般關鍵字）→ 匿名 JWT → `pipe.deezer.com` GraphQL 的 `synchronizedLines`。
/// JWT 只放記憶體、跨查找共用；401 時重取一次
struct DeezerProvider: TimedLyricsProvider {
    static let searchURL = URL(string: "https://api.deezer.com/search")!
    static let tokenURL = URL(string: "https://auth.deezer.com/login/anonymous?jo=p&rto=c&i=c")!
    static let graphURL = URL(string: "https://pipe.deezer.com/api")!
    static let lyricsQuery = "query L($trackId: String!) { track(trackId: $trackId) { lyrics { text synchronizedLines { milliseconds line } } } }"

    let gate: SourceGate
    private let token = AnonymousToken()
    var source: StoredTimingSource { .deezer }

    init(gate: SourceGate) {
        self.gate = gate
    }

    func lookup(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome {
        let search = try await gate.send(
            .timingGET(Self.searchURL, query: ["q": "\(query.artist) \(query.title)", "limit": String(TimingCandidate.limit)]), cacheable: true
        )
        let candidates = try Self.candidates(search.okBody())
        guard let picked = TimingCandidate.pick(candidates, for: query) else { return .noTiming(.miss(among: candidates.count)) }
        let lyrics = try await lyrics(trackID: picked.id, retryingExpiredToken: true)
        let synced = (lyrics?["synchronizedLines"] as? [[String: Any]] ?? []).compactMap(Self.line)
        guard !synced.isEmpty else {
            return .noTiming(((lyrics?["text"] as? String) ?? "").isEmpty ? .notFound : .plainOnly)
        }
        return .validatedTiming(synced, matched: picked.track, duration: query.duration)
    }

    private func lyrics(trackID: String, retryingExpiredToken: Bool) async throws(ProviderFailure) -> [String: Any]? {
        let jwt = try await currentToken()
        let body = try TimingJSON.data(["operationName": "L", "variables": ["trackId": trackID], "query": Self.lyricsQuery])
        let response = try await gate.send(.timingPOST(
            Self.graphURL, body: body, headers: ["Content-Type": "application/json", "Authorization": "Bearer \(jwt)"]
        ))
        if response.statusCode == 401, retryingExpiredToken {
            await token.clear()
            return try await lyrics(trackID: trackID, retryingExpiredToken: false)
        }
        let root = try TimingJSON.dictionary(response.okBody())
        let track = (root["data"] as? [String: Any])?["track"] as? [String: Any]
        return track?["lyrics"] as? [String: Any]
    }

    private func currentToken() async throws(ProviderFailure) -> String {
        if let jwt = await token.value { return jwt }
        let response = try await gate.send(.timingGET(Self.tokenURL))
        guard let jwt = try TimingJSON.dictionary(response.okBody())["jwt"] as? String, Self.isWellFormedToken(jwt)
        else { throw .unparsable }
        await token.set(jwt)
        return jwt
    }

    /// JWT 只會有 base64url 字元與「.」：其他字元（CR／LF）不得進 Authorization 標頭（安全評審 LOW-5）
    static func isWellFormedToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 4096
            && token.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)) }
    }

    static func candidates(_ body: String) throws(ProviderFailure) -> [TimingCandidate] {
        let root = try TimingJSON.dictionary(body)
        guard root["error"] == nil else { throw .unparsable }
        return (root["data"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = TimingJSON.string(item["id"]) else { return nil }
            let artist = (item["artist"] as? [String: Any])?["name"] as? String ?? ""
            return TimingCandidate(
                track: MatchedTrack(artist: artist, title: item["title"] as? String ?? "", duration: TimingJSON.double(item["duration"])), id: id
            )
        }
    }

    private static func line(_ entry: [String: Any]) -> LRCLine? {
        guard let milliseconds = TimingJSON.double(entry["milliseconds"]) else { return nil }
        return LRCLine(start: milliseconds / 1000, text: entry["line"] as? String ?? "")
    }
}

/// 匿名 JWT：只在記憶體（C 段計劃 §3.7）
private actor AnonymousToken {
    private(set) var value: String?

    func set(_ token: String) { value = token }
    func clear() { value = nil }
}
