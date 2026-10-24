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
        var remaining = Self.requestBudget - 1   // 搜尋本身
        func spend() -> Bool {
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        let hits = try Self.searchHits(try await get("artist", [("query", "artist:\"\(Self.phraseEscaped(artist))\""), ("limit", String(Self.searchLimit))]))
        guard let namesakes = ArtistIdentity.namesakes(of: artist, in: hits, names: { [$0.name] + $0.aliases }) else { return .unresolved(.ambiguous) }
        guard !namesakes.isEmpty else { return .unresolved(.notFound) }

        // 每位候選：lookup（曲風＋第一頁 release-group），第一頁滿了還沒對上才 browse；預算用完＝無法確認
        let library = Set(albums.map(ArtistIdentity.albumKey).filter { !$0.isEmpty })
        var candidates: [ArtistIdentity.Candidate] = []
        var genresByID: [String: [ArtistStyleBook.Genre]] = [:]
        for hit in namesakes {
            guard spend() else { return .unresolved(.ambiguous) }
            let detail = try Self.lookup(try await get("artist/\(hit.id)", [("inc", "genres+release-groups")]))
            genresByID[hit.id] = detail.genres
            var groups = detail.groups
            if groups.count >= Self.lookupPageSize, !Self.matches(groups, library) {
                groups = []
                for page in 0..<Self.maximumBrowsePages {
                    guard spend() else { return .unresolved(.ambiguous) }
                    let browse = try Self.browse(try await get("release-group", [
                        ("artist", hit.id), ("limit", String(Self.browsePageSize)), ("offset", String(page * Self.browsePageSize)),
                    ]))
                    groups += browse.groups
                    if Self.matches(groups, library) || (page + 1) * Self.browsePageSize >= browse.total || browse.groups.isEmpty { break }
                }
            }
            candidates.append(ArtistIdentity.Candidate(id: hit.id, name: hit.name, aliases: hit.aliases, releaseGroups: groups))
        }
        switch ArtistIdentity.judge(artist: artist, libraryAlbums: albums, candidates: candidates) {
        case .unresolved(let reason):
            return .unresolved(reason)
        case .verified(let id, let groups):
            return .verified(id: id, matchedReleaseGroups: groups, genres: genresByID[id] ?? [])
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
            // MBID 會進下一個請求的路徑：只收 UUID 形狀（安全評審 LOW-1）
            guard let id = TimingJSON.string(artist["id"]), UUID(uuidString: id) != nil, let name = TimingJSON.string(artist["name"]) else { return nil }
            let aliases = (artist["aliases"] as? [[String: Any]] ?? []).compactMap { TimingJSON.string($0["name"]) }
            return SearchHit(id: id, name: name, aliases: aliases)
        }
    }

    static func lookup(_ body: String) throws(ProviderFailure) -> (genres: [ArtistStyleBook.Genre], groups: [ArtistIdentity.ReleaseGroup]) {
        let root = try TimingJSON.dictionary(body)
        let genres = (root["genres"] as? [[String: Any]] ?? []).compactMap { genre -> ArtistStyleBook.Genre? in
            guard let name = TimingJSON.string(genre["name"]) else { return nil }
            return ArtistStyleBook.Genre(name: name, count: integer(genre["count"]) ?? 0)
        }
        return (genres, releaseGroups(root["release-groups"]))
    }

    static func browse(_ body: String) throws(ProviderFailure) -> (groups: [ArtistIdentity.ReleaseGroup], total: Int) {
        let root = try TimingJSON.dictionary(body)
        let groups = releaseGroups(root["release-groups"])
        return (groups, integer(root["release-group-count"]) ?? groups.count)
    }

    /// 非有限或超出 Int 範圍的數字當沒有（不得 trap，安全評審 LOW-4）
    private static func integer(_ value: Any?) -> Int? {
        TimingJSON.double(value).flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil }
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
