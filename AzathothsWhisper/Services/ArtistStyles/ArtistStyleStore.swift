import Foundation
import OSLog

private let artistStyleLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "artist-styles")

/// 歌手曲風的落盤（⑥b 計劃 §4.4）：單一 JSON 檔。防線沿用 `TimingStore`——不跟符號連結、超大檔不讀、看不懂的版本不讀不蓋、atomic 寫
struct ArtistStyleStore: Sendable {
    enum StoreError: Error, Equatable {
        case unrecognizedFileOnDisk
    }

    struct Loaded: Equatable, Sendable {
        let book: ArtistStyleBook
        /// false＝磁碟上有看不懂的檔（新版、符號連結、超大）：只讀空的，不得覆寫
        let isWritable: Bool
    }

    static let schemaVersion = 1
    /// 416 位約 100 KB；超過這個不讀（防整檔讀進記憶體；計劃 §4.4 上限 1 MiB）
    static let maxFileBytes = 1 << 20
    static let fileName = "artists.json"

    static let defaultDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.ibridgezhao.azathothswhisper/ArtistStyles")

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    private struct StoredFile: Codable {
        let schemaVersion: Int
        let summary: ArtistStyleBook.Summary
        let artists: [String: ArtistStyleBook.Record]
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private enum OnDisk {
        case absent
        case current(ArtistStyleBook)
        case corrupt
        case unrecognized
    }

    func load() -> Loaded {
        switch inspect() {
        case .absent, .corrupt: Loaded(book: ArtistStyleBook(), isWritable: true)
        case .current(let book): Loaded(book: book, isWritable: true)
        case .unrecognized: Loaded(book: ArtistStyleBook(), isWritable: false)
        }
    }

    func save(_ book: ArtistStyleBook) throws {
        if case .unrecognized = inspect() { throw StoreError.unrecognizedFileOnDisk }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = StoredFile(schemaVersion: Self.schemaVersion, summary: book.summary, artists: book.records)
        try Self.encoder.encode(file).write(to: fileURL, options: .atomic)
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
            artistStyleLog.error("unreadable artist style file ignored")
            return .corrupt
        }
        return .current(ArtistStyleBook(records: stored.artists, lastNetworkError: stored.summary.lastNetworkError, lastNetworkErrorAt: stored.summary.lastNetworkErrorAt))
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
