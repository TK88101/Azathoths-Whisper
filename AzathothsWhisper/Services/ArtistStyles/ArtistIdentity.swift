import Foundation

/// MB 候選與曲庫專輯的身分判定（⑥b 計劃 §4.2）。純函式：同樣的輸入永遠同樣的結論
enum ArtistIdentity {
    struct ReleaseGroup: Equatable, Sendable {
        let id: String
        let title: String
    }

    /// 名字或別名與曲庫寫法相同的 MB 歌手，帶齊它的 release-group
    struct Candidate: Equatable, Sendable {
        let id: String
        let name: String
        let aliases: [String]
        let releaseGroups: [ReleaseGroup]
    }

    enum UnresolvedReason: String, Codable, Equatable, Sendable {
        /// MB 沒有同名者
        case notFound
        /// 同名者都對不上曲庫專輯（含唯一命中是泛用標題）
        case noAlbumMatch
        /// 多個同名者都對得上、同名者超過上限，或請求預算用完
        case ambiguous
        /// 不同的曲庫寫法正規化後撞同一個鍵（R2-3）
        case collision
        /// 名字正規化後什麼都不剩（例：`!!!`），不查
        case emptyName
    }

    enum Outcome: Equatable, Sendable {
        case verified(id: String, matchedReleaseGroups: [String])
        case unresolved(UnresolvedReason)
    }

    /// 同名候選超過這個數就不判（R1-5：不靜默丟掉後面的）
    static let maximumCandidates = 8
    /// 正規化後短於等於這個長度的專輯名不足以單獨證明身分
    static let shortTitleLength = 3
    /// 單張命中時不足以證明身分的標題（正規化後比對）
    static let genericTitles: Set<String> = [
        "greatesthits", "bestof", "thebest", "best", "hits", "live", "collection", "thecollection",
        "anthology", "demo", "demos", "singles", "thesingles", "essentials", "theessential",
    ]

    private static let releaseSuffix = try! NSRegularExpression(pattern: #"\s*-\s*(single|ep)\s*$"#, options: [.caseInsensitive])
    private static let editionGroup = try! NSRegularExpression(
        pattern: #"\s*[(\[][^)\]]*(deluxe|edition|remaster|version|expanded|anniversary|bonus|live)[^)\]]*[)\]]"#, options: [.caseInsensitive]
    )

    static func isQueryable(_ artist: String) -> Bool {
        !SongProfileResolver.normalizedArtist(artist).isEmpty
    }

    static func isSameName(_ lhs: String, _ rhs: String) -> Bool {
        let key = SongProfileResolver.normalizedArtist(lhs)
        return !key.isEmpty && key == SongProfileResolver.normalizedArtist(rhs)
    }

    /// 去掉 ` - Single`／` - EP` 與括號裡的版本字樣，再折疊大小寫、變音、全半形，只留字母數字（開頭的 The 保留：專輯名的一部分）
    static func albumKey(_ title: String) -> String {
        var text = title
        for pattern in [releaseSuffix, editionGroup] {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        let posix = Locale(identifier: "en_US_POSIX")
        let folded = text.lowercased(with: posix).folding(options: [.diacriticInsensitive, .widthInsensitive], locale: posix)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// 送給 MB 的專輯名：正規化後去重、去掉空的，保留第一次出現的寫法
    static func outgoingAlbums(_ titles: [String]) -> [String] {
        var seen: Set<String> = []
        return titles.filter { title in
            let key = albumKey(title)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    static func judge(artist: String, libraryAlbums: [String], candidates: [Candidate]) -> Outcome {
        let artistKey = SongProfileResolver.normalizedArtist(artist)
        guard !artistKey.isEmpty else { return .unresolved(.emptyName) }
        let namesakes = candidates.filter { candidate in ([candidate.name] + candidate.aliases).contains { isSameName($0, artist) } }
        guard !namesakes.isEmpty else { return .unresolved(.notFound) }
        guard namesakes.count <= maximumCandidates else { return .unresolved(.ambiguous) }

        let library = Set(libraryAlbums.map(albumKey).filter { !$0.isEmpty })
        let matched = namesakes.compactMap { candidate -> (Candidate, [ReleaseGroup])? in
            let hits = candidate.releaseGroups.filter { group in
                let key = albumKey(group.title)
                return !key.isEmpty && library.contains(key)
            }
            return hits.isEmpty ? nil : (candidate, hits)
        }
        guard matched.count == 1, let (winner, hits) = matched.first else {
            return .unresolved(matched.isEmpty ? .noAlbumMatch : .ambiguous)
        }
        let titles = Set(hits.map { albumKey($0.title) })
        if titles.count < 2, let only = titles.first, isGeneric(only, artistKey: artistKey) { return .unresolved(.noAlbumMatch) }
        return .verified(id: winner.id, matchedReleaseGroups: hits.map(\.id).sorted())
    }

    /// 泛用標題：太短、屬精選／現場之類，或與歌手同名（同名專輯）
    static func isGeneric(_ albumKey: String, artistKey: String) -> Bool {
        albumKey.count <= shortTitleLength || genericTitles.contains(albumKey) || albumKey == artistKey
    }
}
