import CryptoKit
import Foundation
import OSLog

private let consensusLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "artist-consensus")

/// 同歌手 Apple 曲風共識的落盤（增補計劃 §4.2 快照 v0.5、R5）：最近一次成功完整掃描算出的表，播放啟動時載入。
/// 可重建的衍生資料（不同於使用者決定）：版本不符、壞檔、列目錄指紋不符都當沒有，下次完整掃描直接覆寫。
/// 防線沿用 `ArtistDecisionStore`——不跟符號連結、超大檔不讀、atomic 寫
struct ArtistConsensusStore: Sendable {
    enum StoreError: Error, Equatable {
        case symbolicLink
    }

    /// 播放端用的共識：以「最近一次完整掃描當時」為準，不驗證目前曲庫（R5 過期語義）
    struct Snapshot: Equatable, Sendable {
        let builtAt: Date
        let table: [String: AppleGenreConsensus]
    }

    static let schemaVersion = 1
    /// 數百位歌手約數十 KB；超過不讀
    static let maxFileBytes = 1 << 20
    static let fileName = "consensus.json"

    static let defaultDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.ibridgezhao.azathothswhisper/ArtistConsensus")

    static let currentFingerprint = fingerprint(
        rows: SongProfileResolver.keywordRows, genericRows: SongProfileResolver.genericRows, policyVersion: ReadabilityPolicy.version
    )

    private let directory: URL
    private let fingerprint: String

    init(directory: URL, fingerprint: String = Self.currentFingerprint) {
        self.directory = directory
        self.fingerprint = fingerprint
    }

    private struct StoredFile: Codable {
        let schemaVersion: Int
        let builtAt: Date
        let fingerprint: String
        let table: [String: AppleGenreConsensus]
    }

    /// 列目錄（依序：id、關鍵字、是否通用、所在清單）＋可讀性政策版本，固定格式串接後 SHA-256。
    /// 列的軸值與標籤改變不在指紋內：播放時「組不出／被拒絕」會退回逐曲判定
    static func fingerprint(rows: [SongProfileResolver.KeywordRow], genericRows: [SongProfileResolver.KeywordRow], policyVersion: Int) -> String {
        func lines(_ list: String, _ rows: [SongProfileResolver.KeywordRow]) -> [String] {
            rows.map { "\(list)|\($0.id)|\($0.isGeneric)|\($0.keywords.joined(separator: ","))" }
        }
        let canonical = (lines("rows", rows) + lines("generic", genericRows) + ["policy|\(policyVersion)"]).joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func load() -> Snapshot? {
        guard !isSymbolicLink, let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= Self.maxFileBytes,
              let data = try? Data(contentsOf: fileURL)
        else { return nil }
        guard let stored = try? Self.decoder.decode(StoredFile.self, from: data),
              stored.schemaVersion == Self.schemaVersion, stored.fingerprint == fingerprint
        else {
            consensusLog.info("artist consensus file not usable; per-song genres until the next full scan")
            return nil
        }
        return Snapshot(builtAt: stored.builtAt, table: stored.table.compactMapValues(Self.sanitized))
    }

    private static let catalogSize = SongProfileResolver.keywordRows.count + SongProfileResolver.genericRows.count

    /// 被竄改的檔可塞空、重複或比目錄還長的列清單，播放時每次都要逐一比對（安全評審 L2）：載入時就丟掉這種票
    private static func sanitized(_ consensus: AppleGenreConsensus) -> AppleGenreConsensus? {
        AppleGenreConsensus.nonEmpty(
            genreRows: consensus.genreRows.flatMap { $0.isWellFormed(maxRows: catalogSize) ? $0 : nil },
            genericRows: consensus.genericRows.flatMap { $0.isWellFormed(maxRows: catalogSize) ? $0 : nil }
        )
    }

    func save(_ snapshot: Snapshot) throws {
        guard !isSymbolicLink else { throw StoreError.symbolicLink }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = StoredFile(schemaVersion: Self.schemaVersion, builtAt: snapshot.builtAt, fingerprint: fingerprint, table: snapshot.table)
        try Self.encoder.encode(file).write(to: fileURL, options: .atomic)
    }

    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    private var isSymbolicLink: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path)) != nil
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
