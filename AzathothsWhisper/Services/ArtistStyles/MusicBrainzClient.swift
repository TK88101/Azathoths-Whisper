import Foundation

/// MusicBrainz（https://musicbrainz.org/doc/MusicBrainz_API，⑥b 計劃 §4.2、§4.5）：搜尋同名歌手 → 逐一 lookup 曲風與 release-group →
/// 第一頁滿了還沒對上就 browse。外送只有歌手名（搜尋）與 MBID；專輯名只在本機比對（使用者 2026-10-24）。所有請求都經 `gate`
struct MusicBrainzClient: Sendable {
    static let base = URL(string: "https://musicbrainz.org/ws/2/")!
    /// 文件：平均每 IP 每秒 1 次，超過一律 503；多留 0.1 s。逾時比時間軸來源寬（lookup 回應較大）
    static let policy = SourceGate.Policy(minimumInterval: 1.1, timeout: 10)
    /// 文件要求 `App/<版本> ( 聯絡方式 )`；使用者 2026-10-24 選網址、不露 email
    static var userAgent: String { "AzathothsWhisper/\(AppInfo.version) ( \(AppInfo.repositoryURL.absoluteString) )" }
    /// 每位歌手的請求上限（R2-5）：1 搜尋＋各候選 lookup＋必要的 browse
    static let requestBudget = 12
    static let searchLimit = 25
    /// lookup 附帶的 release-group 一頁最多這麼多；滿了才需要 browse
    static let lookupPageSize = 25
    static let browsePageSize = 100
    static let maximumBrowsePages = 3

    let gate: SourceGate

    func identify(artist: String, albums: [String]) async throws(ProviderFailure) -> ArtistStyleBook.Lookup {
        guard ArtistIdentity.isQueryable(artist) else { return .unresolved(.emptyName) }
        var budget = Self.requestBudget
        budget -= 1
        let hits = try Self.searchHits(try await get("artist", [("query", "artist:\"\(Self.phraseEscaped(artist))\""), ("limit", String(Self.searchLimit))]))
        let namesakes = hits.filter { hit in ([hit.name] + hit.aliases).contains { ArtistIdentity.isSameName($0, artist) } }
        guard !namesakes.isEmpty else { return .unresolved(.notFound) }
        guard namesakes.count <= ArtistIdentity.maximumCandidates else { return .unresolved(.ambiguous) }

        let library = Set(albums.map(ArtistIdentity.albumKey).filter { !$0.isEmpty })
        var looked: [(hit: SearchHit, genres: [ArtistStyleBook.Genre], groups: [ArtistIdentity.ReleaseGroup])] = []
        for hit in namesakes {
            guard budget > 0 else { return .unresolved(.ambiguous) }
            budget -= 1
            let detail = try Self.lookup(try await get("artist/\(hit.id)", [("inc", "genres+release-groups")]))
            looked.append((hit, detail.genres, detail.groups))
        }
        var candidates: [ArtistIdentity.Candidate] = []
        for entry in looked {
            var groups = entry.groups
            if groups.count >= Self.lookupPageSize, !Self.matches(groups, library) {
                var offset = 0
                var page = 0
                groups = []
                repeat {
                    guard budget > 0 else { return .unresolved(.ambiguous) }
                    budget -= 1
                    let browse = try Self.browse(try await get("release-group", [
                        ("artist", entry.hit.id), ("limit", String(Self.browsePageSize)), ("offset", String(offset)),
                    ]))
                    groups += browse.groups
                    offset += Self.browsePageSize
                    page += 1
                    if Self.matches(groups, library) || offset >= browse.total || browse.groups.isEmpty { break }
                } while page < Self.maximumBrowsePages
            }
            candidates.append(ArtistIdentity.Candidate(id: entry.hit.id, name: entry.hit.name, aliases: entry.hit.aliases, releaseGroups: groups))
        }
        switch ArtistIdentity.judge(artist: artist, libraryAlbums: albums, candidates: candidates) {
        case .unresolved(let reason):
            return .unresolved(reason)
        case .verified(let id, let groups):
            let genres = looked.first { $0.hit.id == id }?.genres ?? []
            return .verified(id: id, matchedReleaseGroups: groups, genres: genres)
        }
    }

    // MARK: 請求

    private func get(_ path: String, _ query: [(String, String)]) async throws(ProviderFailure) -> String {
        let response = try await gate.send(HTTPRequest(
            method: "GET", url: Self.url(path, query + [("fmt", "json")]),
            headers: ["User-Agent": Self.userAgent, "Accept": "application/json"], timeout: Self.policy.timeout
        ))
        return try response.okBody()
    }

    /// 查詢參數一律百分比編碼到只剩 RFC 3986 unreserved：`+` 不得留著被伺服器讀成空白（R2-4）
    static func url(_ path: String, _ query: [(String, String)]) -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = query.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = encoded
        return components.url!
    }

    /// Lucene phrase 內只有 `\` 與 `"` 有特殊意義
    static func phraseEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: 解析（讀不到的欄位一律當沒有；根不是物件＝unparsable）

    struct SearchHit: Equatable, Sendable {
        let id: String
        let name: String
        let aliases: [String]
    }

    static func searchHits(_ body: String) throws(ProviderFailure) -> [SearchHit] {
        let root = try TimingJSON.dictionary(body)
        let artists = root["artists"] as? [[String: Any]] ?? []
        return artists.compactMap { artist in
            guard let id = TimingJSON.string(artist["id"]), let name = TimingJSON.string(artist["name"]) else { return nil }
            let aliases = (artist["aliases"] as? [[String: Any]] ?? []).compactMap { TimingJSON.string($0["name"]) }
            return SearchHit(id: id, name: name, aliases: aliases)
        }
    }

    static func lookup(_ body: String) throws(ProviderFailure) -> (genres: [ArtistStyleBook.Genre], groups: [ArtistIdentity.ReleaseGroup]) {
        let root = try TimingJSON.dictionary(body)
        let genres = (root["genres"] as? [[String: Any]] ?? []).compactMap { genre -> ArtistStyleBook.Genre? in
            guard let name = TimingJSON.string(genre["name"]) else { return nil }
            return ArtistStyleBook.Genre(name: name, count: Int(TimingJSON.double(genre["count"]) ?? 0))
        }
        return (genres, releaseGroups(root["release-groups"]))
    }

    static func browse(_ body: String) throws(ProviderFailure) -> (groups: [ArtistIdentity.ReleaseGroup], total: Int) {
        let root = try TimingJSON.dictionary(body)
        let groups = releaseGroups(root["release-groups"])
        return (groups, Int(TimingJSON.double(root["release-group-count"]) ?? Double(groups.count)))
    }

    private static func releaseGroups(_ value: Any?) -> [ArtistIdentity.ReleaseGroup] {
        (value as? [[String: Any]] ?? []).compactMap { group in
            guard let id = TimingJSON.string(group["id"]), let title = TimingJSON.string(group["title"]) else { return nil }
            return ArtistIdentity.ReleaseGroup(id: id, title: title)
        }
    }

    private static func matches(_ groups: [ArtistIdentity.ReleaseGroup], _ library: Set<String>) -> Bool {
        groups.contains { library.contains(ArtistIdentity.albumKey($0.title)) }
    }
}
