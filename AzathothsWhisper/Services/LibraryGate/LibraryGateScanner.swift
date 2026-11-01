import Foundation
import OSLog

private let gateLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "library-gate")

/// 一次完整的曲庫掃描（⑧ 計劃 §4.5）
struct LibraryScan: Equatable, Sendable {
    let tracks: [ScannedTrack]
    let startedAt: Date
    let finishedAt: Date
}

enum LibraryScanOutcome: Equatable, Sendable {
    case complete(LibraryScan)
    /// 讀不完整：不得拿來判定達標（R3-4）
    case incomplete(Reason)

    enum Reason: Equatable, Sendable {
        case snapshotFailed, artistReadFailed, tracksMissing, emptyLibrary
    }
}

/// 曲庫閘門的掃描（⑧ 計劃 §4.5）：整庫五欄一次讀完 → 以 `normalizedArtist` 分組、組內每種原始寫法各讀一次歌詞
///（`whose artist == X` 比原始字串，只讀一種會漏曲）→ 以 persistentID 去重並回填。
/// 一次只 await 一個 AE 工作、每個回來後先檢查取消才排下一個；AE 開始後無法中斷（`MusicAppleEventsClient.run`）
struct LibraryGateScanner: Sendable {
    let music: any MusicControlling
    var now: @Sendable () -> Date = { Date() }

    func scan(progress: @Sendable (_ done: Int, _ total: Int) async -> Void) async throws -> LibraryScanOutcome {
        let startedAt = now()
        let clock = ContinuousClock()
        let began = clock.now
        guard let snapshot = try? await music.libraryTrackSnapshot() else { return .incomplete(.snapshotFailed) }
        try Task.checkCancellation()
        guard !snapshot.isEmpty else { return .incomplete(.emptyLibrary) }
        let spellings = Self.spellingsByGroup(snapshot)
        await progress(0, spellings.count)
        /// 讀回來就只留兩個旗標，歌詞全文不駐留（simcodex R1 安全／效率）
        var flagsByID: [String: LyricsFlags] = [:]
        for (index, spelling) in spellings.enumerated() {
            guard let rows = try? await music.artistLyrics(artist: spelling) else {
                gateLog.error("library gate artist read failed at \(index, privacy: .public)")
                return .incomplete(.artistReadFailed)
            }
            try Task.checkCancellation()
            for row in rows where flagsByID[row.persistentID] == nil { flagsByID[row.persistentID] = LyricsFlags(row.lyrics) }
            await progress(index + 1, spellings.count)
        }
        guard snapshot.allSatisfy({ flagsByID[$0.persistentID] != nil }) else { return .incomplete(.tracksMissing) }
        let tracks = snapshot.map { row in
            let flags = flagsByID[row.persistentID] ?? LyricsFlags("")
            return ScannedTrack(
                persistentID: row.persistentID, name: row.name, artist: row.artist, album: row.album, genre: row.genre,
                hasLyrics: flags.hasLyrics, isJapanese: flags.isJapanese
            )
        }
        let elapsed = clock.now - began
        gateLog.info("library gate scan tracks=\(tracks.count, privacy: .public) reads=\(spellings.count, privacy: .public) elapsed=\(elapsed, privacy: .public)")
        return .complete(LibraryScan(tracks: tracks, startedAt: startedAt, finishedAt: now()))
    }

    private struct LyricsFlags {
        let hasLyrics: Bool
        let isJapanese: Bool

        init(_ lyrics: String) {
            hasLyrics = !LyricsText.isBlank(lyrics)
            isJapanese = hasLyrics && LyricsScript.isJapaneseSong(lyrics)
        }
    }

    /// 依 `normalizedArtist` 分組後攤平的原始寫法（同組相鄰、寫法去重、順序固定）
    static func spellingsByGroup(_ rows: [LibraryTrackRow]) -> [String] {
        let groups = Dictionary(grouping: Set(rows.map(\.artist)), by: SongProfileResolver.normalizedArtist)
        return groups.keys.sorted().flatMap { (groups[$0] ?? []).sorted() }
    }
}
