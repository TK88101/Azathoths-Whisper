import Foundation

/// 掃描到的一首曲（⑧ 計劃 §4.5）：歌詞本身不進來，只帶「有無詞」「是不是日文歌」
struct ScannedTrack: Equatable, Sendable {
    let persistentID: String
    let name: String
    let artist: String
    let album: String
    let genre: String
    let hasLyrics: Bool
    let isJapanese: Bool
}

/// 曲庫閘門的報表（⑧ 計劃 §4.1）：逐首四項判定＋計數＋待處理歌手。不可變；決定或掃描變了就重算一份
struct LibraryGateReport: Equatable, Sendable {
    struct Count: Equatable, Sendable {
        let songs: Int
        let artists: Int
        static let zero = Count(songs: 0, artists: 0)
    }

    /// 來源列裡的 MB 狀態；署名與 J-Pop 在 MB 前短路＝不適用（R3-6）
    enum MBStatus: Equatable, Sendable {
        case notApplicable
        case unknown
        case unresolved(ArtistIdentity.UnresolvedReason)
        case verified(hasGenres: Bool)
    }

    /// 組不出樣式的原因（G-SRC：素面也要說得出為什麼）
    enum NoStyleReason: Equatable, Sendable {
        /// 署名樂團但元件不足（署名待補元件，§10-1）
        case signedBandMissingParts
        /// 每一層都沒有可用的列（細節在 trace 與 MB 狀態）
        case noRowMatched
    }

    enum Issue: Hashable, Sendable {
        case identity, composed, readability, source
    }

    struct Row: Equatable, Sendable {
        let track: ScannedTrack
        let explanation: ProfileExplanation
        let mbStatus: MBStatus
        let decision: ArtistDecision?
        let isComposed: Bool
        let noStyleReason: NoStyleReason?
        let passesIdentity: Bool
        let passesReadability: Bool
        let passesSource: Bool

        var issues: Set<Issue> {
            var issues: Set<Issue> = []
            if !passesIdentity { issues.insert(.identity) }
            if !isComposed { issues.insert(.composed) }
            if !passesReadability { issues.insert(.readability) }
            if !passesSource { issues.insert(.source) }
            return issues
        }
    }

    /// 待處理歌手（以寫法家族列，計劃 §4.3）
    struct ArtistIssue: Equatable, Sendable {
        let key: String
        let spellings: [String]
        let songs: Int
        let albums: Int
        let issues: Set<Issue>
        let mbStatus: MBStatus
        let decision: ArtistDecision?
        let isSigned: Bool
        /// 同 `normalizedArtist` 的其他寫法家族（並排、可明示一併套用；R4 A-1）
        let sameNormalizedName: [String]
        /// 每首都已組出樣式：才允許批次「身分不認、照目前樣式」（計劃 §4.3）
        let canKeepFallbackInBulk: Bool
    }

    let rows: [Row]
    let artists: [ArtistIssue]
    let identity: Count
    let identityWithLyrics: Count
    let composed: Count
    let composedWithLyrics: Count
    /// `composed` 的子集：署名樂團組不出（§10-1，照樣擋住閘門）
    let signedPending: Count
    let readability: Count
    let readabilityWithLyrics: Count
    let source: Count

    /// 四項皆 0（含署名待補元件）。空掃描不算達標（R3-4）
    var passed: Bool {
        !rows.isEmpty && [identity, composed, readability, source].allSatisfy { $0 == .zero }
    }

    init(tracks: [ScannedTrack], artistStyles: ArtistStyleBook, decisions: ArtistDecisionBook, audited: Set<ProfileExplanation.AuditKey> = ReadabilityPolicy.audited) {
        let rows = tracks.map { Self.row($0, artistStyles: artistStyles, decisions: decisions, audited: audited) }
        self.rows = rows
        artists = Self.artistIssues(rows)
        let withLyrics = rows.filter(\.track.hasLyrics)
        identity = Self.count(rows) { !$0.passesIdentity }
        identityWithLyrics = Self.count(withLyrics) { !$0.passesIdentity }
        composed = Self.count(rows) { !$0.isComposed }
        composedWithLyrics = Self.count(withLyrics) { !$0.isComposed }
        signedPending = Self.count(rows) { $0.noStyleReason == .signedBandMissingParts }
        readability = Self.count(rows) { !$0.passesReadability }
        readabilityWithLyrics = Self.count(withLyrics) { !$0.passesReadability }
        source = Self.count(rows) { !$0.passesSource }
    }

    private static func row(_ track: ScannedTrack, artistStyles: ArtistStyleBook, decisions: ArtistDecisionBook, audited: Set<ProfileExplanation.AuditKey>) -> Row {
        let genres = artistStyles.genres(forArtist: track.artist)
        let decision = decisions.decision(forArtist: track.artist)
        let explanation = SongProfileResolver.explain(
            artist: track.artist, genre: track.genre, lyrics: .text(isJapanese: track.isJapanese), artistGenres: genres, decision: decision?.choice
        )
        let isComposed = switch explanation.resolution {
        case .jpop: true
        case .pending, .noMatch: false
        default: explanation.resolution.profile.map { Composer.isComposable($0) } ?? false
        }
        let usesMB = SongProfileResolver.needsArtistGenres(track.artist) && explanation.key != .jpop
        let mbStatus: MBStatus = usesMB ? status(genres, record: artistStyles.record(forArtist: track.artist)) : .notApplicable
        let identityOpen = mbStatus == .unknown || { if case .unresolved = mbStatus { true } else { false } }()
        let noStyleReason: NoStyleReason? = isComposed ? nil : (explanation.key == .none ? .noRowMatched : explanation.resolution.source == .signedBand ? .signedBandMissingParts : nil)
        return Row(
            track: track, explanation: explanation, mbStatus: mbStatus, decision: decision, isComposed: isComposed, noStyleReason: noStyleReason,
            passesIdentity: !identityOpen || decision != nil,
            passesReadability: !isComposed || explanation.auditKey.map(audited.contains) == true,
            passesSource: explanation.key != .pending && (isComposed || noStyleReason != nil)
        )
    }

    private static func status(_ genres: ArtistGenres, record: ArtistStyleBook.Record?) -> MBStatus {
        switch genres {
        case .unknown: .unknown
        case .unresolved: .unresolved(record?.reason ?? .collision)
        case .verified(let names): .verified(hasGenres: !names.isEmpty)
        }
    }

    private static func count(_ rows: [Row], where failing: (Row) -> Bool) -> Count {
        let failed = rows.filter(failing)
        return Count(songs: failed.count, artists: Set(failed.map { ArtistDecisionBook.key($0.track.artist) }).count)
    }

    private static func artistIssues(_ rows: [Row]) -> [ArtistIssue] {
        let families = Dictionary(grouping: rows) { ArtistDecisionBook.key($0.track.artist) }
        let byNormalized = Dictionary(grouping: families.keys) { key in SongProfileResolver.normalizedArtist(families[key]?.first?.track.artist ?? key) }
        return families.compactMap { key, songs -> ArtistIssue? in
            let issues = songs.reduce(into: Set<Issue>()) { $0.formUnion($1.issues) }
            guard !issues.isEmpty, let first = songs.first else { return nil }
            let normalized = SongProfileResolver.normalizedArtist(first.track.artist)
            return ArtistIssue(
                key: key, spellings: Array(Set(songs.map(\.track.artist))).sorted(), songs: songs.count, albums: Set(songs.map(\.track.album)).count,
                issues: issues, mbStatus: songs.map(\.mbStatus).first { $0 != .notApplicable } ?? .notApplicable, decision: first.decision,
                isSigned: !SongProfileResolver.needsArtistGenres(first.track.artist),
                sameNormalizedName: (byNormalized[normalized] ?? []).filter { $0 != key }.sorted(),
                canKeepFallbackInBulk: songs.allSatisfy(\.isComposed)
            )
        }
        .sorted { $0.songs != $1.songs ? $0.songs > $1.songs : $0.key < $1.key }
    }
}
