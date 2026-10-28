import Foundation
import OSLog

private let decisionLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "artist-decisions")

/// 使用者決定的落盤（⑧ 曲庫閘門計劃 §4.3）：與 MB 快取分開，快取重建不會帶走使用者決定。
/// 防線沿用 `ArtistStyleStore`／`TimingStore`——不跟符號連結、超大檔不讀、看不懂的版本不讀不蓋、atomic 寫
struct ArtistDecisionStore: Sendable {
    enum StoreError: Error, Equatable {
        case unrecognizedFileOnDisk
    }

    struct Loaded: Equatable, Sendable {
        let book: ArtistDecisionBook
        /// false＝磁碟上有看不懂的檔（新版、符號連結、超大）：只讀空的，不得覆寫
        let isWritable: Bool
    }

    static let schemaVersion = 1
    /// 數百位歌手約數十 KB；超過不讀
    static let maxFileBytes = 1 << 20
    static let fileName = "decisions.json"

    static let defaultDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.ibridgezhao.azathothswhisper/ArtistDecisions")

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    private struct StoredFile: Codable {
        let schemaVersion: Int
        let decisions: [String: ArtistDecision]
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private enum OnDisk {
        case absent
        case current(ArtistDecisionBook)
        case corrupt
        case unrecognized
    }

    func load() -> Loaded {
        switch inspect() {
        case .absent, .corrupt: Loaded(book: ArtistDecisionBook(), isWritable: true)
        case .current(let book): Loaded(book: book, isWritable: true)
        case .unrecognized: Loaded(book: ArtistDecisionBook(), isWritable: false)
        }
    }

    func save(_ book: ArtistDecisionBook) throws {
        if case .unrecognized = inspect() { throw StoreError.unrecognizedFileOnDisk }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(StoredFile(schemaVersion: Self.schemaVersion, decisions: book.decisions)).write(to: fileURL, options: .atomic)
    }

    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    private func inspect() -> OnDisk {
        let url = fileURL
        let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
        guard (try? url.checkResourceIsReachable()) == true || isLink else { return .absent }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= Self.maxFileBytes,
              let data = try? Data(contentsOf: url)
        else { return .unrecognized }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return .corrupt }
        guard let version = try? Self.decoder.decode(SchemaProbe.self, from: data).schemaVersion else { return .corrupt }
        guard version <= Self.schemaVersion else { return .unrecognized }
        guard let stored = try? Self.decoder.decode(StoredFile.self, from: data) else {
            decisionLog.error("unreadable artist decision file ignored")
            return .corrupt
        }
        return .current(ArtistDecisionBook(decisions: stored.decisions))
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
