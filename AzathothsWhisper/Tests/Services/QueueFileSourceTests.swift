import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 D13／D16／D17、AC8c：只讀、檔案屬性變了才重讀、讀到壞檔回報失敗（由 session 保留上一份）
@Suite("QueueFileSource")
struct QueueFileSourceTests {
    private typealias Item = QueueFixtures.Item

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QueueFileSourceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ data: Data, _ name: String, in directory: URL) throws {
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    @Test func disabledSourceReadsNothing() async {
        let source = QueueFileSource(directory: nil)
        #expect(await source.readQueue() == .missing)
        #expect(await source.readHistory(keepLast: 10) == .missing)
    }

    @Test func missingFilesReportMissing() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = QueueFileSource(directory: directory)

        #expect(await source.readQueue() == .missing)
        #expect(await source.readHistory(keepLast: 10) == .missing)
    }

    /// 檔在、讀不出來 ≠ 檔不存在（simcodex R1）：回報 failed，由 session 沿用上一份有效快照（AC8b 單次讀取失敗）
    @Test func unreadableFileIsAFailedReadNotAMissingFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 同名目錄：屬性讀得到、內容讀不出來
        for name in [QueueFileSource.queueFileName, QueueFileSource.historyFileName] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        let source = QueueFileSource(directory: directory)

        #expect(await source.readQueue() == .failed)
        #expect(await source.readHistory(keepLast: 10) == .failed)
    }

    @Test func readsOnceThenReportsUnchanged() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(QueueFixtures.queue(list: [Item(1, itemID: 10)]), QueueFileSource.queueFileName, in: directory)
        let source = QueueFileSource(directory: directory)

        guard case .snapshot(let snapshot) = await source.readQueue() else {
            Issue.record("第一次應讀到快照")
            return
        }
        #expect(snapshot.entries.map(\.itemID) == [10])
        #expect(await source.readQueue() == .unchanged)
    }

    @Test func replacedFileIsReadAgain() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(QueueFixtures.queue(list: [Item(1, itemID: 10)]), QueueFileSource.queueFileName, in: directory)
        let source = QueueFileSource(directory: directory)
        _ = await source.readQueue()

        try write(QueueFixtures.queue(list: [Item(1, itemID: 10), Item(2, itemID: 11)]), QueueFileSource.queueFileName, in: directory)
        guard case .snapshot(let snapshot) = await source.readQueue() else {
            Issue.record("換檔後應重讀")
            return
        }
        #expect(snapshot.entries.count == 2)
    }

    @Test func corruptFileReportsFailedAndRecoversOnReplacement() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Data("garbage".utf8), QueueFileSource.queueFileName, in: directory)
        let source = QueueFileSource(directory: directory)

        #expect(await source.readQueue() == .failed)
        try write(QueueFixtures.queue(list: [Item(1, itemID: 10)]), QueueFileSource.queueFileName, in: directory)
        guard case .snapshot = await source.readQueue() else {
            Issue.record("修好的檔應可讀")
            return
        }
    }

    @Test func readsHistoryKeepingTheRequestedTail() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(QueueFixtures.history([1, 2, 3]), QueueFileSource.historyFileName, in: directory)
        let source = QueueFileSource(directory: directory)

        guard case .snapshot(let snapshot) = await source.readHistory(keepLast: 2) else {
            Issue.record("應讀到履歴")
            return
        }
        #expect(snapshot.recent.map(\.persistentID) == [QueueFixtures.pid(2), QueueFixtures.pid(3)])
        #expect(await source.readHistory(keepLast: 2) == .unchanged)
    }

    /// 預設位置＝使用者的 Music 曲庫（L7：自訂位置一律退回）
    @Test func defaultDirectoryIsTheMusicLibraryPreferences() {
        #expect(QueueFileSource.defaultDirectory.path.hasSuffix("Music/Music/Music Library.musiclibrary/Preferences"))
    }
}
