import Foundation
import Testing

@testable import AzathothsWhisper

// S4 T9（sprint-4-detail.md §4.2、§4.10）：點歌狀態機讀 Queue.dat 的唯讀包裝。
// 順序模式＝小寫 persistent ID 序列；隨機、讀不到、檔案不在＝nil；檔案沒變＝沿用上一次結果

@Suite("RelayQueueReader")
struct RelayQueueReaderTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("relay-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var file: URL { directory.appendingPathComponent(QueueFileSource.queueFileName) }

    private func write(_ data: Data, modified: Date) throws {
        try data.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    }

    @Test func orderedQueueIsLowercasePersistentIDs() async throws {
        try write(QueueFixtures.queue(list: [.init(0xAB), .init(0x1F)]), modified: Date(timeIntervalSince1970: 1000))
        let reader = RelayQueueReader(directory: directory)
        #expect(await reader.read() == ["00000000000000ab", "000000000000001f"])
        // 沒變＝沿用（QueueFileSource 回 unchanged）
        #expect(await reader.read() == ["00000000000000ab", "000000000000001f"])
    }

    @Test func shuffledQueueIsUnusable() async throws {
        try write(QueueFixtures.queue(list: [.init(1)], shuffled: [.init(1)], shuffleMode: "songs"), modified: Date(timeIntervalSince1970: 1000))
        #expect(await RelayQueueReader(directory: directory).read() == nil)
    }

    /// C′（s6-61-cprime.md）：捷徑清單開隨機但沒寫 shuffledList＝照 list 播 → 點歌比對拿得到序列
    @Test func shortcutPlaylistWithShuffleOnIsReadInListOrder() async throws {
        let data = QueueFixtures.queue(list: [.init(0xAB), .init(0x1F)], shuffleMode: "tracks",
                                       subcKind: QueueFixtures.simp, spcID: Int64(7), spcl: QueueFixtures.shortcutSpcl(id: 7))
        try write(data, modified: Date(timeIntervalSince1970: 1000))
        #expect(await RelayQueueReader(directory: directory).read() == ["00000000000000ab", "000000000000001f"])
    }

    /// Music 介面起播的隨機佇列照舊不給序列（不猜）
    @Test func musicAppShuffleStaysUnusable() async throws {
        let data = QueueFixtures.queue(list: [.init(1), .init(2)], shuffled: [.init(2), .init(1)], shuffleMode: "tracks",
                                       subcKind: QueueFixtures.trls, spcID: Int64(7), spcl: QueueFixtures.musicAppSpcl(id: 7))
        try write(data, modified: Date(timeIntervalSince1970: 1000))
        #expect(await RelayQueueReader(directory: directory).read() == nil)
    }

    @Test func missingOrCorruptQueueIsNilAndForgetsPreviousValue() async throws {
        let reader = RelayQueueReader(directory: directory)
        #expect(await reader.read() == nil)
        try write(QueueFixtures.queue(list: [.init(2)]), modified: Date(timeIntervalSince1970: 1000))
        #expect(await reader.read() == ["0000000000000002"])
        try write(Data("not a plist".utf8), modified: Date(timeIntervalSince1970: 2000))
        #expect(await reader.read() == nil)
    }

    @Test func disabledDirectoryReadsNothing() async {
        #expect(await RelayQueueReader(directory: nil).read() == nil)
    }

    /// N-07 輔助證據（§4.10）：讀了許多次，檔案內容與修改時間都不變——只證明本程式沒寫，不代表真機上檔案不變
    @Test func relayDoesNotWriteQueueFiles() async throws {
        let data = QueueFixtures.queue(list: [.init(3), .init(4)])
        let stamp = Date(timeIntervalSince1970: 1234)
        try write(data, modified: stamp)
        let reader = RelayQueueReader(directory: directory)
        for _ in 0..<5 { _ = await reader.read() }
        #expect(try Data(contentsOf: file) == data)
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(modified == stamp)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [QueueFileSource.queueFileName])
    }
}
