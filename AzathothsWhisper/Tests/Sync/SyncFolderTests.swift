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

    @Test func aMissingICloudDriveIsNotCreated() {
        let parent = root()
        let folder = folder(parent.appendingPathComponent("Azathoth's Whisper"))
        #expect(throws: SyncFolder.Failure.iCloudDriveUnavailable) { try folder.write(marks, kind: .nolyrics, at: Self.at) }
        #expect(FileManager.default.fileExists(atPath: parent.path) == false)
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

    // MARK: 安全評審 HIGH-2、MEDIUM-4、LOW-7

    @Test func aPlantedSymbolicLinkTempFileIsNotFollowed() throws {
        let root = root()
        let outside = root.deletingLastPathComponent().appendingPathComponent("azw-victim-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try Data("keep me".utf8).write(to: outside)
        let mine = root.appendingPathComponent("Sync/\(Self.me)")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: mine.appendingPathComponent(".nolyrics.json.tmp"), withDestinationURL: outside)
        try folder(root).write(marks, kind: .nolyrics, at: Self.at)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep me", "不寫到 iCloud 外")
        let written = mine.appendingPathComponent("nolyrics.json")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: written.path)) == nil, "正式檔是一般檔")
        #expect(folder(root).ownPayloadHash(.nolyrics) == SyncCodec.payloadHash(marks))
    }

    @Test func aDirectoryInPlaceOfTheTargetFileIsRefused() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sync/\(Self.me)/nolyrics.json"), withIntermediateDirectories: true)
        #expect(throws: SyncFolder.Failure.unsafeLayout) { try folder(root).write(marks, kind: .nolyrics, at: Self.at) }
    }

    @Test func anExportOverTheSizeLimitIsNotWritten() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let huge: SyncPayload.NoLyrics = Dictionary(uniqueKeysWithValues: (0..<20_000).map {
            (String(format: "AAAA%012d", $0), SyncRegister(value: true, version: SyncVersion(revision: 1, origin: Self.me)))
        })
        #expect(throws: SyncFolder.Failure.tooLarge) { try folder(root).write(huge, kind: .nolyrics, at: Self.at) }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sync/\(Self.me)/nolyrics.json").path) == false)
    }

    @Test func atMostSixteenOtherMacsAreRead() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<20 { try writeOther(root, writer: String(format: "00000000000001%02x", index)) }
        let scan = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        #expect(scan.envelopes.count == SyncFolder.maxWriters)
        #expect(scan.skipped == 20 - SyncFolder.maxWriters)
    }

    /// 安全複查 N4：空資料夾不佔名額
    @Test func emptyFoldersCannotCrowdOutRealMacs() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<20 {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(String(format: "Sync/00000000000000%02x", index)), withIntermediateDirectories: true)
        }
        try writeOther(root, writer: "ffffffffffffff01")
        let scan = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        #expect(scan.envelopes.map(\.writerID) == ["ffffffffffffff01"])
    }

    /// 安全複查 N5：他機檔被換成 FIFO 不會卡住
    @Test func aFIFOInPlaceOfAFileIsSkippedWithoutBlocking() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("Sync/\(Self.other)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(mkfifo(dir.appendingPathComponent("nolyrics.json").path, 0o600) == 0)
        let scan = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        #expect(scan.envelopes.isEmpty)
    }

    /// 安全複查 N6：暫存名被預放成資料夾 → 講清楚是版面問題
    @Test func aDirectoryInPlaceOfTheTempFileIsReportedAsUnsafeLayout() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sync/\(Self.me)/.nolyrics.json.tmp"), withIntermediateDirectories: true)
        #expect(throws: SyncFolder.Failure.unsafeLayout) { try folder(root).write(marks, kind: .nolyrics, at: Self.at) }
    }

    /// 安全複查 N8：壞檔每輪照樣計入略過
    @Test func aBrokenFileIsCountedEveryRound() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("Sync/\(Self.other)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("nolyrics.json"))
        let first = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        let second = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self, unchangedSince: first.stamps)
        #expect(first.skipped == 1)
        #expect(second.skipped == 1)
    }

    @Test func resettingRefusesWhenAParentIsASymbolicLink() throws {
        let root = root()
        let elsewhere = root.deletingLastPathComponent().appendingPathComponent("azw-elsewhere-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createDirectory(at: elsewhere.appendingPathComponent(Self.me), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Sync"), withDestinationURL: elsewhere)
        #expect(throws: SyncFolder.Failure.unsafeLayout) { try folder(root).removeOwnFolder() }
        #expect(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent(Self.me).path), "連結目標底下的資料夾不被刪")
    }

    @Test func anUnchangedFileIsNotReadAgain() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOther(root)
        let first = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self)
        let second = folder(root).readOthers(.nolyrics, as: SyncPayload.NoLyrics.self, unchangedSince: first.stamps)
        #expect(second.envelopes.isEmpty)
        #expect(second.stamps == first.stamps, "沒變的他機仍回報其檔案戳記")
    }

    // MARK: 真下載探針的判斷（計劃附錄 F-d）：取不到狀態（丟錯）不得當成已下載；鍵值 nil＝非 iCloud 一般資料夾，本機檔可讀

    struct StatusUnavailable: Error {}
    private let anyFile = URL(fileURLWithPath: "/sync/000000000000000b/nolyrics.json")

    @Test func aDownloadStatusThatCannotBeReadIsNotTreatedAsDownloaded() {
        let probe = UbiquitousDownloadProbe(readStatus: { _ in throw StatusUnavailable() })
        #expect(probe.isDownloaded(anyFile) == false)
    }

    @Test func aPlainFolderWithoutDownloadStatusIsReadable() {
        let probe = UbiquitousDownloadProbe(readStatus: { _ in nil })
        #expect(probe.isDownloaded(anyFile) == true)
    }

    @Test func onlyTheCurrentVersionCountsAsDownloaded() {
        let statuses: [(URLUbiquitousItemDownloadingStatus, Bool)] = [(.current, true), (.downloaded, false), (.notDownloaded, false)]
        for (status, readable) in statuses {
            #expect(UbiquitousDownloadProbe(readStatus: { _ in status }).isDownloaded(anyFile) == readable, "\(status.rawValue)")
        }
    }
}
