#if os(macOS)
import CryptoKit
import Foundation
import RemoteProtocol

/// 不可變索引；換版時整份替換（設計 §5.2）
public struct CatalogIndex: Sendable {
    /// 已排序（§3）
    public let albums: [AlbumSummary]
    public let position: [String: Int]
    /// albumID → 代表曲 trackID（有封面者）
    public let representative: [String: UInt64]
    /// 與 albums 同序；TextFold 後的「專輯名＋藝人＋所有曲名＋曲目藝人」
    public let searchCorpus: [String]
    public let version: String
    public let skipped: [SkipReason: Int]
    /// S4：albumID → 依 (disc, 曲序, ID) 排好的曲目（曲目選擇器）
    public let songsByAlbum: [String: [TrackSummary]]
    /// S4：trackID → albumID（狀態推送補 albumID、點歌驗證曲目屬於專輯）
    public let albumOfTrack: [String: String]
    /// S4：albumID → 許可閘門結果（放行者附捷徑計畫）
    public let admission: [String: AdmissionResult]
}

/// 由原始曲目建索引（純函式，sprint-3-detail.md §4.5）
public enum CatalogIndexBuilder {
    public static func build(_ load: CatalogLoad) -> CatalogIndex {
        let orderedGroups = Dictionary(grouping: load.songs.filter { ($0.albumID ?? 0) != 0 }) { $0.albumID! }.mapValues(ordered)
        let entries = orderedGroups.map { albumID, songs in entry(albumID: albumID, songs: songs) }.sorted(by: precedes)
        let titles = PlayAdmission.titleIndex(
            load.songs.compactMap { song in song.albumID.map { (title: song.albumTitle ?? "", albumID: hex($0)) } }
                // 非歌曲項目（MV 等）一律算「別的東西」：即使屬於同一張專輯，捷徑只以專輯名篩選、不分媒體種類，
                // 撈到它首數就對不上（#4-1 真曲庫同定檢查：6／987 張）
                + load.otherAlbumTitles.map { (title: $0.title, albumID: "nonsong:" + hex($0.albumID)) })
        return CatalogIndex(
            albums: entries.map(\.summary),
            position: Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.summary.id, $0) }),
            representative: entries.reduce(into: [:]) { $0[$1.summary.id] = $1.representative },
            searchCorpus: entries.map(\.corpus),
            version: version(of: load),
            skipped: load.skipped,
            songsByAlbum: Dictionary(uniqueKeysWithValues: orderedGroups.map { (hex($0), $1.map(summary)) }),
            albumOfTrack: Dictionary(uniqueKeysWithValues: orderedGroups.flatMap { albumID, songs in
                songs.map { (hex($0.trackID), hex(albumID)) } }),
            admission: Dictionary(uniqueKeysWithValues: orderedGroups.map { albumID, songs in
                (hex(albumID), admission(albumID: hex(albumID), songs: songs, titles: titles)) }))
    }

    private static func summary(_ song: RawTrack) -> TrackSummary {
        TrackSummary(id: hex(song.trackID), title: TextClamp.clamp(song.title ?? ""), artist: TextClamp.clamp(song.artist ?? ""),
                     disc: song.discNumber,
                     number: song.trackNumber, duration: song.duration)
    }

    private static func admission(albumID: String, songs: [RawTrack], titles: [String: Set<String>]) -> AdmissionResult {
        let refs = songs.map { AlbumTrackRef(id: hex($0.trackID), disc: $0.discNumber, number: $0.trackNumber) }
        let albumTitles = songs.map { $0.albumTitle ?? "" }
        if let reason = PlayAdmission.check(albumID: albumID, albumTitles: albumTitles, songs: refs, titleIndex: titles) {
            return .refused(reason)
        }
        let artists = Set(songs.map { $0.artist ?? "" })
        return .admitted(ShortcutPlan(album: albumTitles[0], albumArtist: songs[0].albumArtist ?? "",
                                      artist: artists.count == 1 ? artists.first! : "",
                                      order: AlbumSuffix.ordered(refs) ?? []))
    }

    /// 16 位小寫 hex（不經 String(format:)：建索引時每首歌要算好幾次）
    static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    private struct Entry {
        let summary: AlbumSummary
        let representative: UInt64?
        let corpus: String
        let artistKey: String
        let titleKey: String
    }

    private static func ordered(_ songs: [RawTrack]) -> [RawTrack] {
        songs.sorted { ($0.discNumber, $0.trackNumber, $0.trackID) < ($1.discNumber, $1.trackNumber, $1.trackID) }
    }

    private static func entry(albumID: UInt64, songs: [RawTrack]) -> Entry {
        let title = mode(songs.map(\.albumTitle)) ?? ""
        let artist = mode(songs.map(\.albumArtist)) ?? mode(songs.map(\.artist)) ?? ""
        let representative = songs.first(where: \.hasArtwork)
        let token = representative.map { artworkToken($0) }
        let summary = AlbumSummary(id: hex(albumID), title: TextClamp.clamp(title), artist: TextClamp.clamp(artist),
                                   trackCount: songs.count, artworkToken: token)
        let corpus = TextFold.fold(([title, artist] + songs.flatMap { [$0.title ?? "", $0.artist ?? ""] }).joined(separator: "\n"))
        let artistKey = mode(songs.map(\.sortAlbumArtist)) ?? artist
        let titleKey = mode(songs.map(\.sortAlbumTitle)) ?? title
        return Entry(summary: summary, representative: representative?.trackID, corpus: corpus, artistKey: artistKey,
                     titleKey: titleKey)
    }

    /// 非空值的眾數；平手取最先出現者（songs 已依 (disc, track) 排序）
    private static func mode(_ values: [String?]) -> String? {
        let present = values.compactMap { $0 }.filter { !$0.isEmpty }
        let counts = present.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        guard let best = counts.values.max() else { return nil }
        return present.first { counts[$0] == best }
    }

    private static func precedes(_ a: Entry, _ b: Entry) -> Bool {
        let byArtist = a.artistKey.localizedStandardCompare(b.artistKey)
        if byArtist != .orderedSame { return byArtist == .orderedAscending }
        let byTitle = a.titleKey.localizedStandardCompare(b.titleKey)
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        return a.summary.id < b.summary.id
    }

    private static func artworkToken(_ track: RawTrack) -> String {
        var data = Data()
        Canonical.append(track.trackID, to: &data)
        Canonical.append(track.modifiedAt, to: &data)
        return digestPrefix(data)
    }

    /// 只算版本（週期重建先比這個）；build 也用它
    public static func version(of load: CatalogLoad) -> String {
        var data = Data()
        for song in load.songs.sorted(by: { $0.trackID < $1.trackID }) { Canonical.append(song, to: &data) }
        // S4：非歌曲項目的專輯名會影響許可閘門，也進版本（筆數前綴，無歧義）
        Canonical.append(UInt64(load.otherAlbumTitles.count), to: &data)
        for other in load.otherAlbumTitles.sorted(by: { ($0.albumID, $0.title) < ($1.albumID, $1.title) }) {
            Canonical.append(other.albumID, to: &data)
            Canonical.append(other.title, to: &data)
        }
        return digestPrefix(data)
    }

    private static func digestPrefix(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(CatalogLimits.hexIDLength / 2).map { String(format: "%02x", $0) }.joined()
    }
}

/// 版本雜湊的 canonical 編碼：長度前綴 UTF-8、固定寬度大端整數、UTC 秒；nil 與空字串可區分。不得用 `description`
enum Canonical {
    static func append(_ track: RawTrack, to data: inout Data) {
        append(track.trackID, to: &data)
        append(track.albumID, to: &data)
        for text in [track.albumTitle, track.sortAlbumTitle, track.albumArtist, track.sortAlbumArtist, track.artist, track.title] {
            append(text, to: &data)
        }
        append(UInt64(bitPattern: Int64(track.discNumber)), to: &data)
        append(UInt64(bitPattern: Int64(track.trackNumber)), to: &data)
        append(track.modifiedAt, to: &data)
        data.append(track.hasArtwork ? 1 : 0)
        // S4：時長（有無旗標＋位元樣式；S4 起所有版本值與 S3 不同，iPad 會重同步一次）
        append(track.duration.map(\.bitPattern), to: &data)
    }

    static func append(_ value: UInt64, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    static func append(_ value: UInt64?, to data: inout Data) {
        guard let value else { return data.append(0) }
        data.append(1)
        append(value, to: &data)
    }

    static func append(_ text: String?, to data: inout Data) {
        guard let text else { return data.append(0) }
        data.append(1)
        let bytes = Data(text.utf8)
        append(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }

    static func append(_ date: Date?, to data: inout Data) {
        append(date.map { UInt64(bitPattern: Int64($0.timeIntervalSince1970.rounded(.down))) }, to: &data)
    }
}
#endif
