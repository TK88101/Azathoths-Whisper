import Darwin
import Foundation
import OSLog

private let folderLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "cloud-sync")

/// iCloud 檔是否已下載到本機（⑨ 計劃 §6.5、R1-16）：未下載的檔不讀（讀 dataless 檔可能阻塞到下載完）
protocol SyncDownloadProbing: Sendable {
    func isDownloaded(_ url: URL) -> Bool
    func requestDownload(_ url: URL)
}

/// 真實作：一般資料夾（非 iCloud）的資源值是 nil，當作已在本機；取不到狀態（丟錯）不當成已下載，
/// 本輪不讀、要求下載（計劃附錄 F-d：fail-open 會讓暫時性錯誤退化成直接讀 dataless 檔）
struct UbiquitousDownloadProbe: SyncDownloadProbing {
    typealias StatusReader = @Sendable (URL) throws -> URLUbiquitousItemDownloadingStatus?

    let readStatus: StatusReader

    init(readStatus: @escaping StatusReader = { try $0.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus }) {
        self.readStatus = readStatus
    }

    func isDownloaded(_ url: URL) -> Bool {
        do {
            guard let status = try readStatus(url) else { return true }
            return status == .current
        } catch {
            folderLog.error("download status unavailable")
            return false
        }
    }

    func requestDownload(_ url: URL) {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            folderLog.error("download request failed")
        }
    }
}

/// `<root>/Sync/<writerID>/<kind>.json`（§6.1）。每台只寫自己的資料夾，其他只讀；版面嚴格驗證（R1-18）
struct SyncFolder: Sendable {
    enum Failure: Error, Equatable {
        /// 根目錄或資料夾是符號連結／不是目錄
        case unsafeLayout
        /// iCloud Drive 本身不在（未登入或關閉）：不得自己建出一個假的
        case iCloudDriveUnavailable
        /// 要寫的檔超過該類上限：寫了別台也會整檔略過，不如不寫並在設定頁顯示（安全評審 MEDIUM-4）
        case tooLarge
    }

    /// 他機檔的「沒變」判斷：大小＋修改時間一樣就不重讀（效率評審 #2：沒變的大檔每 10 分鐘全量解碼）
    struct FileStamp: Equatable, Sendable {
        let size: Int
        let modified: Date
    }

    /// 他機資料夾最多讀這麼多個（安全評審 MEDIUM-4：數量不設限會讓每輪匯入與索引無上限）
    static let maxWriters = 16

    struct Scan<Payload: Codable & Sendable>: Sendable {
        var envelopes: [SyncEnvelope<Payload>] = []
        /// 這輪讀到（或確認沒變）的各他機檔；呼叫端採用成功後記下，下輪據以略過
        var stamps: [String: FileStamp] = [:]
        /// 略過的資料夾與檔（非 hex 名、符號連結、衝突副本、壞檔、版本較新…），狀態列顯示
        var skipped = 0
        /// 還在雲端、這輪沒讀的檔
        var pendingDownloads = 0
    }

    /// iCloud Drive 的「Azathoth's Whisper」資料夾
    static let defaultRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Azathoth's Whisper")

    /// 對 iCloud 資料夾的每一次存取（測試計數用：關閉同步後必須是 0 次，§8-9）
    enum Access: Equatable, Sendable {
        case write(SyncKind), ownHash(SyncKind), removeOwn, otherWriters, readOthers(SyncKind)
    }

    let root: URL
    let writerID: String
    let appVersion: String
    let downloads: any SyncDownloadProbing
    var onAccess: @Sendable (Access) -> Void = { _ in }

    private var syncDirectory: URL { root.appendingPathComponent("Sync") }
    private var ownDirectory: URL { syncDirectory.appendingPathComponent(writerID) }

    // MARK: 寫自己的

    func write<Payload: Codable & Sendable>(_ payload: Payload, kind: SyncKind, at date: Date, hash: String? = nil) throws {
        onAccess(.write(kind))
        guard isSafeDirectory(root.deletingLastPathComponent()) else { throw Failure.iCloudDriveUnavailable }
        try ensureDirectory(root)
        try ensureDirectory(syncDirectory)
        try ensureDirectory(ownDirectory)
        let data = try SyncCodec.encode(payload, kind: kind, writerID: writerID, appVersion: appVersion, writtenAt: date, hash: hash)
        guard data.count <= kind.maxBytes else { throw Failure.tooLarge }
        let target = ownDirectory.appendingPathComponent(kind.fileName)
        // 正式檔名被換成資料夾（別台可寫這個 iCloud 資料夾）：拒寫，不跟著改名進去
        if !isSymbolicLink(target), (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            throw Failure.unsafeLayout
        }
        // 點開頭的暫存檔；不用 `.atomic`（它的暫存檔名不受控）。舊的暫存檔不管是什麼（含符號連結）先刪，
        // 再以 O_EXCL|O_NOFOLLOW 新建——預先放好的連結不會被跟著寫到 iCloud 外（安全評審 HIGH-2）
        let temporary = ownDirectory.appendingPathComponent(".\(kind.fileName).tmp")
        // 暫存名被預放成資料夾：unlink 刪不掉，說清楚原因（安全複查 N6）
        if !isSymbolicLink(temporary), (try? temporary.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            throw Failure.unsafeLayout
        }
        unlink(temporary.path)
        try Self.writeExclusively(data, to: temporary)
        // rename(2) 不跟隨目的地的符號連結：連結本身被換掉
        guard rename(temporary.path, target.path) == 0 else {
            unlink(temporary.path)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func writeExclusively(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            unlink(url.path)
            throw error
        }
    }

    /// 自己資料夾那份的 payload 雜湊（啟動時與本機正本比，§6.4）；沒有或讀不懂＝nil
    func ownPayloadHash(_ kind: SyncKind) -> String? {
        onAccess(.ownHash(kind))
        let url = ownDirectory.appendingPathComponent(kind.fileName)
        guard isSafeDirectory(ownDirectory), let (data, _) = readRegularFile(url, limit: kind.maxBytes),
              let probe = try? JSONDecoder().decode(HashProbe.self, from: data), probe.writerID == writerID
        else { return nil }
        return probe.payloadSHA256
    }

    func removeOwnFolder() throws {
        onAccess(.removeOwn)
        guard FileManager.default.fileExists(atPath: ownDirectory.path) || isSymbolicLink(ownDirectory) else { return }
        // 逐層都要是真目錄（安全評審 LOW-7：上層被換成連結時會刪到別處）
        guard [root.deletingLastPathComponent(), root, syncDirectory, ownDirectory].allSatisfy(isSafeDirectory) else { throw Failure.unsafeLayout }
        try FileManager.default.removeItem(at: ownDirectory)
    }

    // MARK: 讀別人的

    func otherWriters() -> [String] {
        onAccess(.otherWriters)
        return candidateWriters().valid
    }

    func readOthers<Payload: Codable & Sendable>(
        _ kind: SyncKind, as type: Payload.Type, unchangedSince known: [String: FileStamp] = [:]
    ) -> Scan<Payload> {
        onAccess(.readOthers(kind))
        var scan = Scan<Payload>()
        let writers = candidateWriters(holding: kind)
        scan.skipped = writers.invalid
        for writer in writers.valid {
            let directory = syncDirectory.appendingPathComponent(writer)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            // 只認確切檔名；其他（iCloud 衝突副本「nolyrics 2.json」等）略過並計數。點開頭的是暫存或系統檔
            scan.skipped += names.filter { !$0.hasPrefix(".") && $0 != kind.fileName && Self.isConflictCopy($0, of: kind) }.count
            guard names.contains(kind.fileName) else { continue }
            let url = directory.appendingPathComponent(kind.fileName)
            guard downloads.isDownloaded(url) else {
                downloads.requestDownload(url)
                scan.pendingDownloads += 1
                continue
            }
            if let previous = known[writer], let current = fileStamp(url), current == previous {
                scan.stamps[writer] = current
                continue
            }
            guard let (data, stamp) = readRegularFile(url, limit: kind.maxBytes) else { scan.skipped += 1; continue }
            switch SyncCodec.decode(data, as: type, kind: kind, expectedWriter: writer) {
            case .success(let envelope):
                scan.envelopes.append(envelope)
                // 只記解碼成功的：壞檔每輪照樣計入略過（安全複查 N8）
                scan.stamps[writer] = stamp
            case .failure(let failure):
                scan.skipped += 1
                folderLog.error("sync file skipped kind=\(kind.rawValue, privacy: .public) reason=\(String(describing: failure), privacy: .public)")
            }
        }
        return scan
    }

    // MARK: 版面

    /// `kind` 給了＝名額只算真的有這類檔的資料夾，且取最近更新的 16 台（安全複查 N4：空資料夾不得擠掉真正的他機）
    private func candidateWriters(holding kind: SyncKind? = nil) -> (valid: [String], invalid: Int) {
        guard isSafeDirectory(root), isSafeDirectory(syncDirectory),
              let names = try? FileManager.default.contentsOfDirectory(atPath: syncDirectory.path)
        else { return ([], 0) }
        let visible = names.filter { !$0.hasPrefix(".") && $0 != writerID }
        let valid = visible.filter { SyncWriterID.isValid($0) && isSafeDirectory(syncDirectory.appendingPathComponent($0)) }.sorted()
        guard let kind else { return (Array(valid.prefix(Self.maxWriters)), visible.count - min(valid.count, Self.maxWriters)) }
        let holding = valid.compactMap { writer -> (String, Date)? in
            fileStamp(syncDirectory.appendingPathComponent(writer).appendingPathComponent(kind.fileName)).map { (writer, $0.modified) }
        }
        let kept = holding.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(Self.maxWriters).map(\.0).sorted()
        return (kept, visible.count - valid.count + holding.count - kept.count)
    }

    /// 同一類的衝突副本（「nolyrics 2.json」）；別類的檔不算
    private static func isConflictCopy(_ name: String, of kind: SyncKind) -> Bool {
        name.hasPrefix(kind.rawValue) && name.hasSuffix(".json")
    }

    private func ensureDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) || isSymbolicLink(url) {
            guard isSafeDirectory(url) else { throw Failure.unsafeLayout }
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    private func isSafeDirectory(_ url: URL) -> Bool {
        guard !isSymbolicLink(url),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true
        else { return false }
        return true
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// 以 O_NOFOLLOW 開檔、對同一個 fd 做 fstat 再讀（安全評審 LOW-8：先查後以路徑重開有時間差）；最多讀 limit+1 bytes
    private func readRegularFile(_ url: URL, limit: Int) -> (Data, FileStamp)? {
        // O_NONBLOCK：FIFO 以唯讀開啟不會卡住等寫入端（安全複查 N5）；對一般檔沒有影響
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, Int(info.st_size) <= limit,
              let data = try? handle.read(upToCount: Int(info.st_size) + 1), data.count <= limit
        else { return nil }
        return (data, FileStamp(size: Int(info.st_size), modified: Self.modificationDate(info)))
    }

    private func fileStamp(_ url: URL) -> FileStamp? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return FileStamp(size: Int(info.st_size), modified: Self.modificationDate(info))
    }

    private static func modificationDate(_ info: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    private struct HashProbe: Decodable {
        let writerID: String
        let payloadSHA256: String
    }
}
