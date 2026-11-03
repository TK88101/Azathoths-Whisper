import Foundation
import OSLog

private let folderLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "cloud-sync")

/// iCloud 檔是否已下載到本機（⑨ 計劃 §6.5、R1-16）：未下載的檔不讀（讀 dataless 檔可能阻塞到下載完）
protocol SyncDownloadProbing: Sendable {
    func isDownloaded(_ url: URL) -> Bool
    func requestDownload(_ url: URL)
}

/// 真實作：一般資料夾（非 iCloud）的資源值是 nil，當作已在本機
struct UbiquitousDownloadProbe: SyncDownloadProbing {
    func isDownloaded(_ url: URL) -> Bool {
        guard let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus else { return true }
        return status == .current
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
    }

    struct Scan<Payload: Codable & Sendable>: Sendable {
        var envelopes: [SyncEnvelope<Payload>] = []
        /// 略過的資料夾與檔（非 hex 名、符號連結、衝突副本、壞檔、版本較新…），狀態列顯示
        var skipped = 0
        /// 還在雲端、這輪沒讀的檔
        var pendingDownloads = 0
    }

    /// iCloud Drive 的「Azathoth's Whisper」資料夾
    static let defaultRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Azathoth's Whisper")

    let root: URL
    let writerID: String
    let appVersion: String
    let downloads: any SyncDownloadProbing

    private var syncDirectory: URL { root.appendingPathComponent("Sync") }
    private var ownDirectory: URL { syncDirectory.appendingPathComponent(writerID) }

    // MARK: 寫自己的

    func write<Payload: Codable & Sendable>(_ payload: Payload, kind: SyncKind, at date: Date) throws {
        try ensureDirectory(root)
        try ensureDirectory(syncDirectory)
        try ensureDirectory(ownDirectory)
        let data = try SyncCodec.encode(payload, kind: kind, writerID: writerID, appVersion: appVersion, writtenAt: date)
        let target = ownDirectory.appendingPathComponent(kind.fileName)
        let temporary = ownDirectory.appendingPathComponent(".\(kind.fileName).tmp")
        try data.write(to: temporary)
        guard rename(temporary.path, target.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// 自己資料夾那份的 payload 雜湊（啟動時與本機正本比，§6.4）；沒有或讀不懂＝nil
    func ownPayloadHash(_ kind: SyncKind) -> String? {
        let url = ownDirectory.appendingPathComponent(kind.fileName)
        guard isSafeDirectory(ownDirectory), let data = readRegularFile(url, limit: kind.maxBytes),
              let probe = try? JSONDecoder().decode(HashProbe.self, from: data), probe.writerID == writerID
        else { return nil }
        return probe.payloadSHA256
    }

    func removeOwnFolder() throws {
        guard FileManager.default.fileExists(atPath: ownDirectory.path) else { return }
        guard isSafeDirectory(ownDirectory) else { throw Failure.unsafeLayout }
        try FileManager.default.removeItem(at: ownDirectory)
    }

    // MARK: 讀別人的

    func otherWriters() -> [String] {
        candidateWriters().valid
    }

    func readOthers<Payload: Codable & Sendable>(_ kind: SyncKind, as type: Payload.Type) -> Scan<Payload> {
        var scan = Scan<Payload>()
        let writers = candidateWriters()
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
            guard let data = readRegularFile(url, limit: kind.maxBytes) else { scan.skipped += 1; continue }
            switch SyncCodec.decode(data, as: type, kind: kind, expectedWriter: writer) {
            case .success(let envelope): scan.envelopes.append(envelope)
            case .failure(let failure):
                scan.skipped += 1
                folderLog.error("sync file skipped kind=\(kind.rawValue, privacy: .public) reason=\(String(describing: failure), privacy: .public)")
            }
        }
        return scan
    }

    // MARK: 版面

    private func candidateWriters() -> (valid: [String], invalid: Int) {
        guard isSafeDirectory(root), isSafeDirectory(syncDirectory),
              let names = try? FileManager.default.contentsOfDirectory(atPath: syncDirectory.path)
        else { return ([], 0) }
        let visible = names.filter { !$0.hasPrefix(".") && $0 != writerID }
        let valid = visible.filter { SyncWriterID.isValid($0) && isSafeDirectory(syncDirectory.appendingPathComponent($0)) }.sorted()
        return (valid, visible.count - valid.count)
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

    private func readRegularFile(_ url: URL, limit: Int) -> Data? {
        guard !isSymbolicLink(url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= limit
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private struct HashProbe: Decodable {
        let writerID: String
        let payloadSHA256: String
    }
}
