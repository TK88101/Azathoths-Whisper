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

        /// 身分還沒定（還沒查或認不出）
        var isIdentityOpen: Bool {
            switch self {
            case .unknown, .unresolved: true
            case .notApplicable, .verified: false
            }
        }
    }

    /// 組不出樣式的原因（G-SRC：素面也要說得出為什麼）
    enum NoStyleReason: Equatable, Sendable {
        /// 署名樂團但元件不足（署名待補元件，§10-1）
        case signedBandMissingParts
        /// 每一層都沒有可用的列（細節在 trace 與 MB 狀態）
        case noRowMatched
    }

    /// 四項；宣告順序＝畫面上的排列順序
    enum Issue: CaseIterable, Hashable, Sendable {
        case identity, composed, readability, source

        static func ordered(_ issues: Set<Issue>) -> [Issue] {
            allCases.filter(issues.contains)
        }
    }

    struct Row: Equatable, Sendable {
        let track: ScannedTrack
        /// 寫法家族鍵（`ArtistDecisionBook.key`）：計數與待處理歌手都以它分組
        let familyKey: String
        let explanation: ProfileExplanation
        let mbStatus: MBStatus
        let decision: ArtistDecision?
        let noStyleReason: NoStyleReason?
        let issues: Set<Issue>

        var isComposed: Bool { !issues.contains(.composed) }
        var passesSource: Bool { !issues.contains(.source) }
    }

    /// 待處理歌手（以寫法家族列，計劃 §4.3）；已有決定的歌手即使沒有問題也列出，才改得了、清得掉（R1-6）
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
        // 判定只看（歌手寫法, 曲風, 是否日文）：整庫一萬多首只有一兩千種組合，每種算一次（simcodex R1 效率）
        var verdicts: [VerdictKey: Verdict] = [:]
        let rows = tracks.map { track in
            let key = VerdictKey(artist: track.artist, genre: track.genre, isJapanese: track.isJapanese)
            let verdict = verdicts[key] ?? {
                let fresh = Self.verdict(key, artistStyles: artistStyles, decisions: decisions, audited: audited)
                verdicts[key] = fresh
                return fresh
            }()
            return Row(
                track: track, familyKey: verdict.familyKey, explanation: verdict.explanation, mbStatus: verdict.mbStatus,
                decision: verdict.decision, noStyleReason: verdict.noStyleReason, issues: verdict.issues
            )
        }
        self.rows = rows
        artists = Self.artistIssues(rows)
        let withLyrics = rows.filter(\.track.hasLyrics)
        identity = Self.count(rows, .identity)
        identityWithLyrics = Self.count(withLyrics, .identity)
        composed = Self.count(rows, .composed)
        composedWithLyrics = Self.count(withLyrics, .composed)
        signedPending = Self.count(rows.filter { $0.noStyleReason == .signedBandMissingParts }, .composed)
        readability = Self.count(rows, .readability)
        readabilityWithLyrics = Self.count(withLyrics, .readability)
        source = Self.count(rows, .source)
    }

    private struct VerdictKey: Hashable {
        let artist: String
        let genre: String
        let isJapanese: Bool
    }

    private struct Verdict {
        let familyKey: String
        let explanation: ProfileExplanation
        let mbStatus: MBStatus
        let decision: ArtistDecision?
        let noStyleReason: NoStyleReason?
        let issues: Set<Issue>
    }

    private static func verdict(_ key: VerdictKey, artistStyles: ArtistStyleBook, decisions: ArtistDecisionBook, audited: Set<ProfileExplanation.AuditKey>) -> Verdict {
        let genres = artistStyles.genres(forArtist: key.artist)
        let decision = decisions.decision(forArtist: key.artist)
        let explanation = SongProfileResolver.explain(
            artist: key.artist, genre: key.genre, lyrics: .text(isJapanese: key.isJapanese), artistGenres: genres, decision: decision?.choice
        )
        // 曲風列各層在 explain 裡已確認組得出；只剩署名團要另外判
        let (isComposed, noStyleReason): (Bool, NoStyleReason?) = switch explanation.resolution {
        case .pending: (false, nil)
        case .noMatch: (false, .noRowMatched)
        case .signedBand(let profile): Composer.isComposable(profile) ? (true, nil) : (false, .signedBandMissingParts)
        default: (true, nil)
        }
        let usesMB = SongProfileResolver.needsArtistGenres(key.artist) && explanation.key != .jpop
        let mbStatus: MBStatus = usesMB ? status(genres, record: artistStyles.record(forArtist: key.artist)) : .notApplicable
        var issues: Set<Issue> = []
        if mbStatus.isIdentityOpen && decision == nil { issues.insert(.identity) }
        if !isComposed { issues.insert(.composed) }
        if isComposed && explanation.auditKey.map(audited.contains) != true { issues.insert(.readability) }
        if explanation.key == .pending { issues.insert(.source) }
        return Verdict(
            familyKey: ArtistDecisionBook.key(key.artist), explanation: explanation, mbStatus: mbStatus, decision: decision,
            noStyleReason: noStyleReason, issues: issues
        )
    }

    private static func status(_ genres: ArtistGenres, record: ArtistStyleBook.Record?) -> MBStatus {
        switch genres {
        case .unknown: .unknown
        case .unresolved: .unresolved(record?.reason ?? .collision)
        case .verified(let names): .verified(hasGenres: !names.isEmpty)
        }
    }

    private static func count(_ rows: [Row], _ issue: Issue) -> Count {
        let failed = rows.filter { $0.issues.contains(issue) }
        return Count(songs: failed.count, artists: Set(failed.map(\.familyKey)).count)
    }

    private static func artistIssues(_ rows: [Row]) -> [ArtistIssue] {
        let families = Dictionary(grouping: rows, by: \.familyKey)
        let normalizedOf = families.mapValues { SongProfileResolver.normalizedArtist($0[0].track.artist) }
        let byNormalized = Dictionary(grouping: families.keys) { normalizedOf[$0] ?? $0 }
        return families.compactMap { key, songs -> ArtistIssue? in
            let issues = songs.reduce(into: Set<Issue>()) { $0.formUnion($1.issues) }
            let first = songs[0]
            guard !issues.isEmpty || first.decision != nil else { return nil }
            return ArtistIssue(
                key: key, spellings: Array(Set(songs.map(\.track.artist))).sorted(), songs: songs.count, albums: Set(songs.map(\.track.album)).count,
                issues: issues, mbStatus: songs.map(\.mbStatus).first { $0 != .notApplicable } ?? .notApplicable, decision: first.decision,
                isSigned: !SongProfileResolver.needsArtistGenres(first.track.artist),
                sameNormalizedName: (byNormalized[normalizedOf[key] ?? key] ?? []).filter { $0 != key }.sorted(),
                canKeepFallbackInBulk: songs.allSatisfy(\.isComposed)
            )
        }
        .sorted { $0.songs != $1.songs ? $0.songs > $1.songs : $0.key < $1.key }
    }
}
