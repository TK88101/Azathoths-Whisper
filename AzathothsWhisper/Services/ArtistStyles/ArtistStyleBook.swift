import Foundation

/// resolver 吃的 MB 證據（⑥b 計劃 §4.3）：`unknown`＝還沒查、`unresolved`＝查了但認不出是誰或撞鍵、`verified`＝MB 曲風（前 3）
enum ArtistGenres: Equatable, Sendable {
    case unknown
    case unresolved
    case verified([String])
}

/// 所有歌手的查詢結果（⑥b 計劃 §4.4）。不可變值：每次記錄都回傳新的一份，`AppModel` 拿它當 snapshot（R1-6）
struct ArtistStyleBook: Equatable, Sendable {
    struct Genre: Codable, Equatable, Sendable {
        let name: String
        let count: Int
    }

    struct Record: Codable, Equatable, Sendable {
        /// 曲庫裡出現過、正規化後落在這個鍵的寫法（只差大小寫、全半形、變音）
        let spellings: [String]
        let mbid: String?
        let matchedReleaseGroups: [String]
        /// MB 回的原始曲風清單（名＋票數）
        let genres: [Genre]
        /// nil＝verified
        let reason: ArtistIdentity.UnresolvedReason?
        let fetchedAt: Date
    }

    enum Lookup: Equatable, Sendable {
        case verified(id: String, matchedReleaseGroups: [String], genres: [Genre])
        case unresolved(ArtistIdentity.UnresolvedReason)
    }

    struct Summary: Codable, Equatable, Sendable {
        let verified: Int
        let unresolved: Int
        let lastNetworkError: String?
        let lastNetworkErrorAt: Date?
    }

    /// resolver 只看票數最高的幾個曲風（R1-7）
    static let genreLimit = 3

    private(set) var records: [String: Record]
    private(set) var lastNetworkError: String?
    private(set) var lastNetworkErrorAt: Date?

    init(records: [String: Record] = [:], lastNetworkError: String? = nil, lastNetworkErrorAt: Date? = nil) {
        self.records = records
        self.lastNetworkError = lastNetworkError
        self.lastNetworkErrorAt = lastNetworkErrorAt
    }

    var summary: Summary {
        let verified = records.values.filter { $0.reason == nil }.count
        return Summary(verified: verified, unresolved: records.count - verified, lastNetworkError: lastNetworkError, lastNetworkErrorAt: lastNetworkErrorAt)
    }

    static func key(_ artist: String) -> String {
        SongProfileResolver.normalizedArtist(artist)
    }

    /// 同一歌手的寫法：只折疊大小寫、全半形、變音與多餘空白，保留標點（`AC/DC` 與 `ACDC` 不同）——與時間軸比對的「完全一致」同一個定義
    static func spellingFamily(_ artist: String) -> String {
        TrackMatcher.exactKey(artist)
    }

    func record(forArtist artist: String) -> Record? {
        records[Self.key(artist)]
    }

    func hasRecord(forArtist artist: String) -> Bool {
        record(forArtist: artist) != nil
    }

    func genres(forArtist artist: String) -> ArtistGenres {
        guard let record = record(forArtist: artist) else { return .unknown }
        guard record.reason == nil, Self.isVariant(artist, of: record) else { return .unresolved }
        let ranked = record.genres.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return .verified(ranked.prefix(Self.genreLimit).map(\.name))
    }

    func recording(_ lookup: Lookup, forSpelling spelling: String, at date: Date) -> ArtistStyleBook {
        let key = Self.key(spelling)
        if let existing = records[key], !Self.isVariant(spelling, of: existing) {
            return replacing(key, with: existing.adding(spelling, reason: .collision))
        }
        let spellings = Set((records[key]?.spellings ?? []) + [spelling]).sorted()
        let record: Record
        switch lookup {
        case .verified(let id, let groups, let genres):
            record = Record(spellings: spellings, mbid: id, matchedReleaseGroups: groups, genres: genres, reason: nil, fetchedAt: date)
        case .unresolved(let reason):
            record = Record(spellings: spellings, mbid: nil, matchedReleaseGroups: [], genres: [], reason: reason, fetchedAt: date)
        }
        return replacing(key, with: record)
    }

    /// 曲庫掃描到的寫法：已有記錄的鍵上出現同一歌手的新寫法就併進來，出現不同寫法就整個鍵記撞鍵（不覆寫 mbid）
    func noting(spellings: [String]) -> ArtistStyleBook {
        spellings.reduce(self) { book, spelling in
            let key = Self.key(spelling)
            guard let existing = book.records[key], !existing.spellings.contains(spelling) else { return book }
            return book.replacing(key, with: existing.adding(spelling, reason: Self.isVariant(spelling, of: existing) ? existing.reason : .collision))
        }
    }

    /// 整庫掃描的寫法（撞鍵規則的唯一入口，simcodex R1）：已有記錄的鍵照 `noting`；
    /// 還沒有記錄的鍵上出現不同的寫法＝撞鍵，直接記下、不查
    func reconcilingLibrary(_ spellings: [String], at date: Date) -> ArtistStyleBook {
        let noted = noting(spellings: spellings)
        let fresh = Dictionary(grouping: Set(spellings).filter { !Self.key($0).isEmpty && noted.records[Self.key($0)] == nil }, by: Self.key)
        return fresh.values.reduce(noted) { book, group in
            let sorted = group.sorted()
            guard Set(sorted.map(Self.spellingFamily)).count > 1, let first = sorted.first else { return book }
            return book.recording(.unresolved(.collision), forSpelling: first, at: date).noting(spellings: Array(sorted.dropFirst()))
        }
    }

    func recordingNetworkFailure(_ kind: String, at date: Date) -> ArtistStyleBook {
        ArtistStyleBook(records: records, lastNetworkError: kind, lastNetworkErrorAt: date)
    }

    private func replacing(_ key: String, with record: Record) -> ArtistStyleBook {
        ArtistStyleBook(records: records.merging([key: record]) { _, new in new }, lastNetworkError: lastNetworkError, lastNetworkErrorAt: lastNetworkErrorAt)
    }

    private static func isVariant(_ spelling: String, of record: Record) -> Bool {
        let family = spellingFamily(spelling)
        return record.spellings.allSatisfy { spellingFamily($0) == family }
    }
}

private extension ArtistStyleBook.Record {
    /// 併入一個寫法；撞鍵時只改原因，不覆寫 mbid
    func adding(_ spelling: String, reason: ArtistIdentity.UnresolvedReason?) -> Self {
        Self(spellings: Set(spellings + [spelling]).sorted(), mbid: mbid, matchedReleaseGroups: matchedReleaseGroups, genres: genres, reason: reason, fetchedAt: fetchedAt)
    }
}
