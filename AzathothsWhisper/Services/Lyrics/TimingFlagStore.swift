import Foundation
import OSLog

private let flagLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "timing-flags")

/// ⑪ 標記的存取邊界（protocol＋替身慣例）
protocol TimingFlagStoring: Sendable {
    func isFlagged(_ key: TimingFlagKey) async -> Bool
    func flag(_ flag: TimingFlag) async throws
    func clear(_ key: TimingFlagKey) async throws
}

/// 「時間軸不準」標記的單檔存檔（計劃 §4.2）。只給我離線診斷用：不同步、不影響任何行為。
/// 讀不懂的檔（壞 JSON、較新版本、超大、符號連結、非一般檔）不讀也不覆寫——同 `TimingStore` 的「未知不得蓋掉」
actor TimingFlagStore: TimingFlagStoring {
    enum StoreError: Error, Equatable {
        case invalidPersistentID
        case unrecognizedFileOnDisk
    }

    static let schemaVersion = 1
    static let fileName = "flags.json"
    /// 讀取上限
    static let maxFileBytes = 1 << 20
    /// 寫入上限：嚴於讀取上限，保證寫出的檔一定讀得回來（Codex R1-6）
    static let maxWriteBytes = 512 * 1024

    static let defaultDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.ibridgezhao.azathothswhisper/TimingFlags")

    private struct StoredFile: Codable {
        let schemaVersion: Int
        let flags: [TimingFlag]
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private enum OnDisk {
        case absent
        case current([TimingFlag])
        case unrecognized
    }

    private let directory: URL
    private let maxWriteBytes: Int

    init(directory: URL, maxWriteBytes: Int = TimingFlagStore.maxWriteBytes) {
        self.directory = directory
        self.maxWriteBytes = maxWriteBytes
    }

    func isFlagged(_ key: TimingFlagKey) -> Bool {
        guard let key = Self.canonical(key), case .current(let flags) = inspect() else { return false }
        return flags.contains { $0.key == key }
    }

    /// 同鍵＝合併：positions 接在後面（留最後 10 筆），其餘欄位取新的
    func flag(_ flag: TimingFlag) throws {
        guard let id = TimingStore.canonicalID(flag.persistentID) else { throw StoreError.invalidPersistentID }
        let incoming = flag.withPersistentID(id)
        let existing = try currentFlags()
        let previous = existing.first { $0.key == incoming.key }
        let merged = incoming.withPositions(Array(((previous?.positions ?? []) + incoming.positions).suffix(TimingFlag.maxPositions)))
        try write(existing.filter { $0.key != incoming.key } + [merged])
    }

    func clear(_ key: TimingFlagKey) throws {
        guard let key = Self.canonical(key) else { throw StoreError.invalidPersistentID }
        let existing = try currentFlags()
        guard existing.contains(where: { $0.key == key }) else { return }
        try write(existing.filter { $0.key != key })
    }

    /// 診斷與測試用：全部標記，依 (persistentID, lyricsHash) 排序
    func all() throws -> [TimingFlag] {
        try currentFlags().sorted(by: Self.byKey)
    }

    // MARK: 內部

    private func currentFlags() throws -> [TimingFlag] {
        switch inspect() {
        case .absent: return []
        case .current(let flags): return flags
        case .unrecognized: throw StoreError.unrecognizedFileOnDisk
        }
    }

    /// 超過寫入上限就從最舊的丟起（同時刻以鍵排序，結果穩定）
    private func write(_ flags: [TimingFlag]) throws {
        var kept = flags.sorted { ($0.markedAt, $0.persistentID, $0.lyricsHash.hex) < ($1.markedAt, $1.persistentID, $1.lyricsHash.hex) }
        var data = try Self.encode(kept)
        while data.count > maxWriteBytes, !kept.isEmpty {
            kept.removeFirst()
            data = try Self.encode(kept)
        }
        if kept.count < flags.count { flagLog.info("timing flags trimmed: dropped \(flags.count - kept.count) oldest") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func inspect() -> OnDisk {
        let url = fileURL
        let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
        guard isLink || FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard !isLink, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= Self.maxFileBytes,
              let data = try? Data(contentsOf: url),
              let version = try? Self.decoder.decode(SchemaProbe.self, from: data).schemaVersion, version == Self.schemaVersion,
              let stored = try? Self.decoder.decode(StoredFile.self, from: data)
        else {
            flagLog.error("timing flag file unrecognized; left untouched")
            return .unrecognized
        }
        return .current(stored.flags)
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private static func canonical(_ key: TimingFlagKey) -> TimingFlagKey? {
        TimingStore.canonicalID(key.persistentID).map { TimingFlagKey(persistentID: $0, lyricsHash: key.lyricsHash) }
    }

    private static func byKey(_ lhs: TimingFlag, _ rhs: TimingFlag) -> Bool {
        (lhs.persistentID, lhs.lyricsHash.hex) < (rhs.persistentID, rhs.lyricsHash.hex)
    }

    private static func encode(_ flags: [TimingFlag]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(StoredFile(schemaVersion: schemaVersion, flags: flags))
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 只在記憶體的標記（UI 測試組裝用；不碰使用者的檔）
actor InMemoryTimingFlagStore: TimingFlagStoring {
    private var flags: [TimingFlagKey: TimingFlag] = [:]

    func isFlagged(_ key: TimingFlagKey) -> Bool {
        flags[key] != nil
    }

    func flag(_ flag: TimingFlag) {
        flags[flag.key] = flag
    }

    func clear(_ key: TimingFlagKey) {
        flags[key] = nil
    }
}

extension TimingFlag {
    func withPersistentID(_ id: String) -> TimingFlag {
        TimingFlag(persistentID: id, lyricsHash: lyricsHash, markedAt: markedAt, positions: positions, applied: applied, stored: stored, provenance: provenance)
    }

    func withPositions(_ positions: [Double]) -> TimingFlag {
        TimingFlag(persistentID: persistentID, lyricsHash: lyricsHash, markedAt: markedAt, positions: positions, applied: applied, stored: stored, provenance: provenance)
    }
}
