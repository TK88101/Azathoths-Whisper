import Foundation
import OSLog

/// 可寫進存檔的來源（母計劃 C.1／C.3）。內嵌 LRC 本來就在 Music 欄位、估算隨時可算，兩者都不存檔——型別層強制
enum StoredTimingSource: String, Sendable, Codable, Hashable {
    case lrclib, youtubeMusic, deezer, qq, netease

    var timingSource: TimingSource {
        switch self {
        case .lrclib: return .lrclib
        case .youtubeMusic: return .youtubeMusic
        case .deezer: return .deezer
        case .qq: return .qq
        case .netease: return .netease
        }
    }
}

/// 跨 persistentID 比對用的曲目身分（⑨ 計劃 §6.5）：寫入當下的查詢欄位。只存在本機正本與自己的 iCloud 檔，不進日誌
struct TimingMatch: Codable, Equatable, Sendable {
    let artist: String
    let title: String
    let duration: Double
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
    /// 對出這份錨點的 `LRCAligner.revision`；欄位出現前寫下的檔＝1
    let alignerRevision: Int
    /// ⑨ §6.3：第一次產生這份結果的機器；nil＝本機、還沒蓋章
    let origin: String?
    /// ⑨ §6.5：不可變的來源（`<origin>:<原始 persistentID>`）。只有本機由外部來源新查到的 found 會產生新的；
    /// 跨 ID 採用、匯入、同 ID 合併一律原樣保留（整體確認 2）
    let sourceRef: String?
    let match: TimingMatch?

    init(persistentID: String, lyricsHash: LyricsFingerprint, outcome: Outcome, fetchedAt: Date, alignerRevision: Int = LRCAligner.revision,
         origin: String? = nil, sourceRef: String? = nil, match: TimingMatch? = nil) {
        self.persistentID = persistentID
        self.lyricsHash = lyricsHash
        self.outcome = outcome
        self.fetchedAt = fetchedAt
        self.alignerRevision = alignerRevision
        self.origin = origin
        self.sourceRef = sourceRef
        self.match = match
    }

    var isFound: Bool {
        if case .found = outcome { return true }
        return false
    }

    var isStamped: Bool { SyncWriterID.isStamped(origin) }

    func stamped(by writer: String) -> TimingRecord {
        guard !isStamped else { return self }
        // 先算成 String?：直接傳給 String?? 參數時，`??` 會被提升成雙層 Optional，左邊的 nil 變成「有值」而右邊永遠用不到
        let ref: String? = sourceRef ?? (isFound ? "\(writer):\(persistentID)" : nil)
        return copy(origin: .some(writer), sourceRef: .some(ref))
    }

    /// 換成另一個 persistentID（正規化、跨 ID 採用）；出身欄位原樣保留
    func withPersistentID(_ id: String) -> TimingRecord {
        copy(persistentID: id)
    }

    /// 欄位複製的唯一一處（R3 重用評審：新增欄位時只改這裡）
    private func copy(persistentID: String? = nil, origin: String?? = nil, sourceRef: String?? = nil) -> TimingRecord {
        TimingRecord(persistentID: persistentID ?? self.persistentID, lyricsHash: lyricsHash, outcome: outcome, fetchedAt: fetchedAt,
                     alignerRevision: alignerRevision, origin: origin ?? self.origin, sourceRef: sourceRef ?? self.sourceRef, match: match)
    }

    /// 他機時鐘超前這麼多的記錄不收（R1-5）
    static let remoteFutureTolerance: TimeInterval = 86_400

    /// 遠端記錄的逐筆驗證（§6.3）：檔案層已驗 pid 與錨點；這裡驗 origin 格式、時鐘、對齊器版本、sourceRef 格式。
    /// 對齊器版本高於本版的不收（安全評審 MEDIUM-3：否則可永久蓋掉本機正確的結果、且本機永不重查；新版的結果由本機自己重查）
    func isAcceptableRemote(now: Date) -> Bool {
        guard SyncWriterID.isAcceptableOrigin(origin, allowUnstamped: false), fetchedAt.timeIntervalSince(now) <= Self.remoteFutureTolerance,
              (1...LRCAligner.revision).contains(alignerRevision)
        else { return false }
        guard isFound else { return true }
        return sourceRef.map(Self.isValidSourceRef) ?? false
    }

    /// `<writerID>:<16 位大寫 hex persistentID>`（安全評審 LOW-6）
    static func isValidSourceRef(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return SyncWriterID.isValid(String(parts[0])) && TimingStore.isCanonicalID(String(parts[1]))
    }

    /// 匯入他機記錄（§6.5）：不用時鐘決勝。本機沒有→採用；同詞 found 勝 notFound、兩邊 found 取**有效**版本大者
    /// （`LRCAligner.effectiveRevision`：可信的版本同級→保留本機，⑩ 計劃 §4.3）；
    /// 其餘（含異詞）保留本機——時間軸是對本機目前歌詞有效的快取，不要求兩台逐位相同（R1-1）
    static func importMerged(local: TimingRecord?, remote: TimingRecord) -> TimingRecord {
        guard let local else { return remote }
        guard local.lyricsHash == remote.lyricsHash else { return local }
        switch (local.isFound, remote.isFound) {
        case (false, true): return remote
        case (true, true):
            return LRCAligner.effectiveRevision(remote.alignerRevision) > LRCAligner.effectiveRevision(local.alignerRevision) ? remote : local
        default: return local
        }
    }

    /// 兩份記錄的合併（多台 Mac 經同步資料夾、或同程序先後寫入）：
    /// 詞不同→取新來的（新詞）；同詞：found 勝 notFound；同類→`fetchedAt` 較新者勝（同時刻取新來的）
    static func merged(existing: TimingRecord?, incoming: TimingRecord) -> TimingRecord {
        guard let existing, existing.lyricsHash == incoming.lyricsHash else { return incoming }
        switch (existing.outcome, incoming.outcome) {
        case (.found, .notFound):
            // 錨點留著，但記下這個對齊版本已重查過：否則舊版本 found 每次都會再查（Codex review P2）。
            // 最多記到 `foundCompatibleRevision`：不把舊錨點標成新演算法對出來的（⑩ 計劃 §4.3、§8 R5）
            return TimingRecord(
                persistentID: existing.persistentID, lyricsHash: existing.lyricsHash, outcome: existing.outcome, fetchedAt: existing.fetchedAt,
                alignerRevision: max(existing.alignerRevision, LRCAligner.effectiveRevision(incoming.alignerRevision)),
                origin: existing.origin, sourceRef: existing.sourceRef, match: existing.match
            )
        case (.notFound, .found): return incoming
        // 同時刻＝新寫入者勝（它是剛查到的；舊的可能是錨點已套不上的壞檔）
        default: return incoming.fetchedAt >= existing.fetchedAt ? incoming : existing
        }
    }
}

extension Array where Element == TimingRecord.LineStart {
    /// 錨點本身的合法性（存檔讀取與對齊重建共用的唯一定義）：index 非負且遞增、時間有限、非負、單調不減
    var areWellFormedAnchors: Bool {
        allSatisfy { $0.index >= 0 && $0.start.isFinite && $0.start >= 0 }
            && zip(self, dropFirst()).allSatisfy { $0.index < $1.index && $0.start <= $1.start }
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
        // found：錨點不可信才重查（⑩ 計劃 G3：revision 3 不重查既有 found）；notFound：舊演算法判的可能是漏判，重查一次
        if case .found = record.outcome { return record.alignerRevision < LRCAligner.foundCompatibleRevision }
        if record.alignerRevision < LRCAligner.revision { return true }
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

    /// v2（C 段 §3.4）：加了 netease。舊版讀到 v2 判認不出來、不覆寫；v1 檔照讀
    static let schemaVersion = 2
    static let oldestReadableVersion = 1
    /// 一份時間軸幾 KB；同步資料夾裡超過這個大小的檔不讀（防整檔讀進記憶體）
    static let maxFileBytes = 1 << 20
    static let maxLines = 5000

    static let defaultDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.ibridgezhao.azathothswhisper/Timings")

    private let directory: URL
    /// ⑨：查找寫入成功後通知（iCloud 匯出的 dirty）；匯入（adopt）與蓋章不通知，由同步自己處理
    private var onSaved: (@Sendable () -> Void)?
    /// ⑨：全掃補章做過之後的 writerID——之後新寫入當場蓋章，不再全掃（效率評審 #1）。全掃中途失敗不設，下次再掃
    private var stampedBy: String?

    init(directory: URL) {
        self.directory = directory
    }

    func setOnSaved(_ hook: @escaping @Sendable () -> Void) {
        onSaved = hook
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

    /// 回傳實際寫下的（與磁碟既有者合併後的）記錄
    @discardableResult
    func save(_ record: TimingRecord) throws -> TimingRecord {
        guard let id = Self.canonicalID(record.persistentID) else { throw StoreError.invalidPersistentID }
        let canonical = record.withPersistentID(id)
        let merged = TimingRecord.merged(existing: try existingRecord(id), incoming: canonical)
        let stored = stampedBy.map { merged.stamped(by: $0) } ?? merged
        try write(stored, id: id)
        onSaved?()
        return stored
    }

    // MARK: ⑨ 跨機同步（計劃 §6.5）

    /// 匯入一筆他機記錄（不走 `merged` 的「新來的勝」）。true＝本機有變
    @discardableResult
    func adopt(_ record: TimingRecord) throws -> Bool {
        guard let id = Self.canonicalID(record.persistentID) else { throw StoreError.invalidPersistentID }
        let existing = try existingRecord(id)
        let merged = TimingRecord.importMerged(local: existing, remote: record.withPersistentID(id))
        guard merged != existing else { return false }
        try write(merged, id: id)
        return true
    }

    /// 跨 ID 採用（⑨ §6.5）：呼叫端已確定本機那份不可用，直接取代（不合併）
    func replace(_ record: TimingRecord) throws {
        guard let id = Self.canonicalID(record.persistentID) else { throw StoreError.invalidPersistentID }
        if case .unrecognized = inspect(id) { throw StoreError.unrecognizedFileOnDisk }
        try write(record.withPersistentID(id), id: id)
        onSaved?()
    }

    /// 匯出用：所有讀得懂的記錄，依 persistentID 排序
    func allRecords() -> [TimingRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard name.hasSuffix(".json"), let id = Self.canonicalID(String(name.dropLast(5))), case .current(let record) = inspect(id) else { return nil }
            return record
        }
    }

    /// 替缺 origin 的記錄蓋上本機 writerID 並寫回（§6.3；冪等，中斷後下次只補仍缺的）。回傳補了幾筆。
    /// 補完之後的新寫入當場蓋章，所以之後的呼叫不再全掃
    @discardableResult
    func stampAll(by writer: String) throws -> Int {
        guard stampedBy == nil else { return 0 }
        let stamped = try allRecords().filter { !$0.isStamped }.reduce(0) { count, record in
            try write(record.stamped(by: writer), id: record.persistentID)
            return count + 1
        }
        stampedBy = writer
        return stamped
    }

    private func existingRecord(_ id: String) throws -> TimingRecord? {
        switch inspect(id) {
        case .unrecognized: throw StoreError.unrecognizedFileOnDisk
        case .current(let record): return record
        case .absent, .corrupt: return nil
        }
    }

    private func write(_ record: TimingRecord, id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(TimingRecordFile(record)).write(to: fileURL(for: id), options: .atomic)
    }

    /// 已是正規形式（16 位大寫 hex）：遠端資料的 pid 必須原樣合格
    static func isCanonicalID(_ value: String) -> Bool {
        canonicalID(value) == value
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
        guard let stored = try? Self.decoder.decode(TimingRecordFile.self, from: data), let record = stored.record(expecting: id) else {
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

/// 磁碟上的形狀（母計劃 C.1 的欄位）。`source == nil`＝查過沒有。⑨：iCloud 檔的時間軸 payload 也是這個形狀
struct TimingRecordFile: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let persistentID: String
    let lyricsHash: LyricsFingerprint
    let source: StoredTimingSource?
    let lines: [TimingRecord.LineStart]
    let fetchedAt: Date
    /// 可選欄位：舊版讀到會忽略，所以不必升 schemaVersion
    let alignerRevision: Int?
    /// ⑨ 同上，可選欄位
    let origin: String?
    let sourceRef: String?
    let match: TimingMatch?

    init(_ record: TimingRecord) {
        schemaVersion = TimingStore.schemaVersion
        persistentID = record.persistentID
        lyricsHash = record.lyricsHash
        fetchedAt = record.fetchedAt
        alignerRevision = record.alignerRevision
        origin = record.origin
        sourceRef = record.sourceRef
        match = record.match
        switch record.outcome {
        case .found(let source, let lines):
            self.source = source
            self.lines = lines
        case .notFound:
            self.source = nil
            self.lines = []
        }
    }

    /// 以自己的 persistentID 驗證（iCloud payload 用）
    var record: TimingRecord? {
        TimingStore.canonicalID(persistentID).flatMap(record(expecting:))
    }

    func record(expecting id: String) -> TimingRecord? {
        guard (TimingStore.oldestReadableVersion...TimingStore.schemaVersion).contains(schemaVersion),
              TimingStore.canonicalID(persistentID) == id,
              lines.count <= TimingStore.maxLines,
              lines.areWellFormedAnchors
        else { return nil }
        switch (source, lines.isEmpty) {
        case (let source?, false):
            return TimingRecord(
                persistentID: id, lyricsHash: lyricsHash, outcome: .found(source: source, lines: lines), fetchedAt: fetchedAt,
                alignerRevision: alignerRevision ?? 1, origin: origin, sourceRef: sourceRef, match: match.flatMap(\.validated)
            )
        case (nil, true):
            return TimingRecord(persistentID: id, lyricsHash: lyricsHash, outcome: .notFound, fetchedAt: fetchedAt, alignerRevision: alignerRevision ?? 1,
                                origin: origin, sourceRef: sourceRef, match: match.flatMap(\.validated))
        default:
            return nil
        }
    }
}

private extension TimingMatch {
    /// 壞的比對欄位只讓這筆不參與跨 ID，不讓整筆記錄失效
    var validated: TimingMatch? {
        guard !artist.isEmpty, !title.isEmpty, artist.count <= TrackMatcher.maxNameLength, title.count <= TrackMatcher.maxNameLength,
              duration.isFinite, duration > 0
        else { return nil }
        return self
    }
}
