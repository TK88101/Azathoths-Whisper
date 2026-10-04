import Foundation
import OSLog

/// 可寫進存檔的來源（母計劃 C.1／C.3）。內嵌 LRC 本來就在 Music 欄位、估算隨時可算，兩者都不存檔——型別層強制
enum StoredTimingSource: String, Sendable, Codable {
    case lrclib, youtubeMusic, deezer, qq, kugou
}

/// 一首歌一份的時間軸存檔（母計劃 C.1）。「查過、沒有」也要存：7 天重試靠它（C.4）
struct TimingRecord: Equatable, Sendable {
    /// `index`＝`LyricsLines.lyricTexts` 的零起序號（只借時間、不借文字：文字永遠取自 Music 欄位）
    struct LineStart: Equatable, Sendable, Codable {
        let index: Int
        let start: Double
    }

    enum Outcome: Equatable, Sendable {
        case found(source: StoredTimingSource, lines: [LineStart])
        case notFound
    }

    let persistentID: String
    let lyricsHash: LyricsFingerprint
    let outcome: Outcome
    /// 最後一次查找的時刻（wall-clock：要跨重啟、跨機器比較，單調時鐘做不到）
    let fetchedAt: Date

    /// 兩份記錄的合併（多台 Mac 經同步資料夾、或同程序先後寫入）：
    /// 詞不同→取新來的（新詞）；同詞：found 勝 notFound；同類→`fetchedAt` 較新者勝
    static func merged(existing: TimingRecord?, incoming: TimingRecord) -> TimingRecord {
        guard let existing, existing.lyricsHash == incoming.lyricsHash else { return incoming }
        switch (existing.outcome, incoming.outcome) {
        case (.found, .notFound): return existing
        case (.notFound, .found): return incoming
        default: return incoming.fetchedAt > existing.fetchedAt ? incoming : existing
        }
    }
}

/// 要不要再去外部找時間軸（母計劃 C.4）
enum TimingLookupPolicy {
    static let retryInterval: TimeInterval = 7 * 86_400
    /// 他機時鐘錯亂寫下的未來時間：超過這麼多就當作該重找，免得永遠不到期
    static let futureTolerance: TimeInterval = 86_400

    static func shouldLookup(record: TimingRecord?, currentHash: LyricsFingerprint, now: Date) -> Bool {
        guard let record else { return true }
        if record.lyricsHash != currentHash { return true }
        if case .found = record.outcome { return false }
        let age = now.timeIntervalSince(record.fetchedAt)
        return age >= retryInterval || age < -futureTolerance
    }
}

private let timingLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "timings")

/// 時間軸存放：單一資料夾、每首一個 `<persistentID>.json`（母計劃 C.1）。
///
/// 預設位置 `defaultDirectory`；之後指向 iCloud Drive 只需換 `directory`。
/// actor：同程序兩個寫入者的「讀→合併→寫」不得互相蓋掉（A1 計劃 §3.6，Codex R2）。
/// 讀不懂的檔（壞 JSON、版本不符、欄位不合法）一律當「未知」回 nil，不當「沒有」
actor TimingStore {
    enum StoreError: Error, Equatable {
        case invalidPersistentID
        /// 認不出來的檔（他機較新版本、沒有版本欄位、超大、符號連結、非一般檔）：讀不懂＝未知，不得蓋掉
        case unrecognizedFileOnDisk
    }

    static let schemaVersion = 1
    /// 一份時間軸幾 KB；同步資料夾裡超過這個大小的檔不讀（防整檔讀進記憶體）
    static let maxFileBytes = 1 << 20
    static let maxLines = 5000

    static let defaultDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.ibridgezhao.azathothswhisper/Timings")

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// 磁碟上這首的檔是什麼狀況。只讀一次檔，讀與寫的判斷都從這裡出（simplify R2 altitude）
    private enum OnDisk {
        case absent
        case current(TimingRecord)
        /// 目前格式但內容壞了、或根本不是 JSON：可以被新結果取代
        case corrupt
        /// 認不出來：不讀、不蓋
        case unrecognized
    }

    func load(persistentID: String) -> TimingRecord? {
        guard let id = Self.canonicalID(persistentID), case .current(let record) = inspect(id) else { return nil }
        return record
    }

    func save(_ record: TimingRecord) throws {
        guard let id = Self.canonicalID(record.persistentID) else { throw StoreError.invalidPersistentID }
        let canonical = TimingRecord(persistentID: id, lyricsHash: record.lyricsHash, outcome: record.outcome, fetchedAt: record.fetchedAt)
        let existing: TimingRecord?
        switch inspect(id) {
        case .unrecognized: throw StoreError.unrecognizedFileOnDisk
        case .current(let record): existing = record
        case .absent, .corrupt: existing = nil
        }
        let merged = TimingRecord.merged(existing: existing, incoming: canonical)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(StoredFile(merged)).write(to: fileURL(for: id), options: .atomic)
    }

    /// Music 的 persistentID 是 16 位 hex；大寫正規化後才驗證與命名（大小寫不同不得變成兩個檔、防路徑穿越）
    static func canonicalID(_ persistentID: String) -> String? {
        let upper = persistentID.uppercased()
        guard upper.count == 16, upper.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return upper
    }

    /// 只讀一般檔案：符號連結（可能指向 FIFO、裝置或別的檔）與超大檔一律認不出來（安全評審 MEDIUM）
    private func inspect(_ id: String) -> OnDisk {
        let url = fileURL(for: id)
        guard (try? url.checkResourceIsReachable()) == true || isSymbolicLink(url) else { return .absent }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= Self.maxFileBytes,
              let data = try? Data(contentsOf: url)
        else { return .unrecognized }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return .corrupt }
        guard let version = try? Self.decoder.decode(SchemaProbe.self, from: data).schemaVersion,
              version <= Self.schemaVersion
        else { return .unrecognized }
        guard let stored = try? Self.decoder.decode(StoredFile.self, from: data), let record = stored.record(expecting: id) else {
            timingLog.error("unreadable timing file ignored")
            return .corrupt
        }
        return .current(record)
    }

    /// 斷掉的符號連結 `checkResourceIsReachable` 會說不存在，但它仍佔著這個檔名
    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
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

/// 只看版本欄位：其餘欄位讀不懂也要知道它是不是較新的格式
private struct SchemaProbe: Decodable {
    let schemaVersion: Int
}

/// 磁碟上的形狀（母計劃 C.1 的欄位）。`source == nil`＝查過沒有
private struct StoredFile: Codable {
    let schemaVersion: Int
    let persistentID: String
    let lyricsHash: LyricsFingerprint
    let source: StoredTimingSource?
    let lines: [TimingRecord.LineStart]
    let fetchedAt: Date

    init(_ record: TimingRecord) {
        schemaVersion = TimingStore.schemaVersion
        persistentID = record.persistentID
        lyricsHash = record.lyricsHash
        fetchedAt = record.fetchedAt
        switch record.outcome {
        case .found(let source, let lines):
            self.source = source
            self.lines = lines
        case .notFound:
            self.source = nil
            self.lines = []
        }
    }

    func record(expecting id: String) -> TimingRecord? {
        guard schemaVersion == TimingStore.schemaVersion,
              TimingStore.canonicalID(persistentID) == id,
              lines.count <= TimingStore.maxLines,
              zip(lines, lines.dropFirst()).allSatisfy({ $0.index < $1.index }),
              lines.allSatisfy({ $0.index >= 0 && $0.start.isFinite && $0.start >= 0 })
        else { return nil }
        switch (source, lines.isEmpty) {
        case (let source?, false):
            return TimingRecord(persistentID: id, lyricsHash: lyricsHash, outcome: .found(source: source, lines: lines), fetchedAt: fetchedAt)
        case (nil, true):
            return TimingRecord(persistentID: id, lyricsHash: lyricsHash, outcome: .notFound, fetchedAt: fetchedAt)
        default:
            return nil
        }
    }
}
