import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.1：每台只寫自己的 `<writerID>/`；版面嚴格驗證（真目錄、16 位小寫 hex、確切檔名）；
// 衝突副本略過並計數；未下載的檔本輪跳過並要求下載（R1-16、R1-17、R1-18）。一律在臨時目錄
@Suite("Sync folder")
struct SyncFolderTests {
    static let me = "000000000000000a"
    static let other = "000000000000000b"
    static let at = Date(timeIntervalSince1970: 1_790_000_000)

    final class FakeDownloads: SyncDownloadProbing, @unchecked Sendable {
        private let lock = NSLock()
        var notDownloaded: Set<String> = []
        private(set) var requested: [String] = []
        func isDownloaded(_ url: URL) -> Bool { lock.withLock { !notDownloaded.contains(url.lastPathComponent) } }
        func requestDownload(_ url: URL) { lock.withLock { requested.append(url.lastPathComponent) } }
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-sync-folder-\(UUID().uuidString)")
    }

    private func folder(_ root: URL, downloads: FakeDownloads = FakeDownloads()) -> SyncFolder {
        SyncFolder(root: root, writerID: Self.me, appVersion: "3.1.0", downloads: downloads)
    }

    private let marks: SyncPayload.NoLyrics = ["AAAA000000000001": SyncRegister(value: true, version: SyncVersion(revision: 1, origin: other))]

    private func writeOther(_ root: URL, writer: String = other, kind: SyncKind = .nolyrics, name: String? = nil) throws {
        let dir = root.appendingPathComponent("Sync/\(writer)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try SyncCodec.encode(marks, kind: kind, writerID: writer, appVersion: "3.1.0", writtenAt: Self.at)
            .write(to: dir.appendingPathComponent(name ?? kind.fileName))
    }

    @Test func itWritesOnlyIntoItsOwnFolderAndLeavesNoTempFile() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = folder(root)
        try folder.write(marks, kind: .nolyrics, at: Self.at)
        let mine = root.appendingPathComponent("Sync/\(Self.me)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: mine.path) == ["nolyrics.json"])
        #expect(folder.ownPayloadHash(.nolyrics) == SyncCodec.payloadHash(marks))
        try folder.write(marks, kind: .nolyrics, at: Self.at.addingTimeInterval(1))
        #expect(try FileManager.default.contentsOfDirectory(atPath: mine.path) == ["nolyrics.json"], "改名替換，不留暫存檔")
    }

    @Test func itReadsOtherWritersButNeverItself() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = folder(root)
        try folder.write(marks, kind: .nolyrics, at: Self.at)
        try writeOther(root)
        let scan = folder.readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        #expect(scan.envelopes.map(\.writerID) == [Self.other])
        #expect(scan.envelopes.first?.payload == marks)
        #expect(scan.skipped == 0)
    }

    @Test func badFoldersAndConflictCopiesAreSkippedAndCounted() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOther(root)
        try writeOther(root, writer: "NOT-A-WRITER")
        try writeOther(root, name: "nolyrics 2.json")
        let sync = root.appendingPathComponent("Sync")
        try FileManager.default.createSymbolicLink(at: sync.appendingPathComponent("000000000000000c"), withDestinationURL: sync.appendingPathComponent(Self.other))
        let scan = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        #expect(scan.envelopes.map(\.writerID) == [Self.other])
        #expect(scan.skipped == 3, "非 hex 資料夾、衝突副本、符號連結資料夾")
    }

    @Test func aRejectedFileIsSkippedWithoutAffectingOthers() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOther(root)
        let dir = root.appendingPathComponent("Sync/000000000000000c")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("nolyrics.json"))
        let scan = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        #expect(scan.envelopes.map(\.writerID) == [Self.other])
        #expect(scan.skipped == 1)
    }

    @Test func aFileThatIsNotDownloadedIsRequestedAndSkippedThisRound() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOther(root)
        let downloads = FakeDownloads()
        downloads.notDownloaded = ["nolyrics.json"]
        let scan = folder(root, downloads: downloads).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        #expect(scan.envelopes.isEmpty)
        #expect(scan.pendingDownloads == 1)
        #expect(downloads.requested == ["nolyrics.json"])
    }

    @Test func aSymbolicLinkRootIsNeitherReadNorWritten() throws {
        let real = root()
        let link = root()
        defer { try? FileManager.default.removeItem(at: real); try? FileManager.default.removeItem(at: link) }
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(throws: SyncFolder.Failure.unsafeLayout) { try folder(link).write(marks, kind: .nolyrics, at: Self.at) }
        #expect(folder(link).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self).envelopes.isEmpty)
    }

    @Test func otherWritersAreListedWithTheirLastWriteTime() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOther(root)
        #expect(folder(root).otherWriters() == [Self.other])
    }

    @Test func resettingRemovesOnlyThisMacsFolder() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = folder(root)
        try folder.write(marks, kind: .nolyrics, at: Self.at)
        try writeOther(root)
        try folder.removeOwnFolder()
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sync/\(Self.me)").path) == false)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sync/\(Self.other)/nolyrics.json").path))
    }
}
